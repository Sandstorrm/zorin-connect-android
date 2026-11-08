#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Replays phone touch frames as a virtual multitouch touchpad (uinput).

Reads JSON lines on stdin, one per frame:
    {"touch": {"seq": 12, "t": 1203441, "p": [[pointerId, x_mm, y_mm], ...]}}
Every frame carries the complete finger state; an empty "p" means all fingers are up.
The phone's event times ("t", ms) are used to re-create the original spacing between
frames, delayed by a small playout buffer, so network jitter does not reach libinput.
"""
import json
import queue
import sys
import threading
import time

from evdev import AbsInfo, UInput, ecodes as e

# The virtual pad is a fixed square so the phone can rotate without recreating the device.
PAD_MM = 170
UNITS_PER_MM = 30
PAD_MAX = PAD_MM * UNITS_PER_MM
MAX_SLOTS = 5

PLAYOUT_DELAY = 0.030   # seconds of buffering added on top of the estimated network delay
CATCH_UP = 0.5          # a backlog is replayed at up to 1/CATCH_UP times real speed
NEW_TOUCH_GAP = 0.5     # a gap this long restarts clock estimation (and accepts a seq reset)

TOOL_BUTTONS = [None, e.BTN_TOOL_FINGER, e.BTN_TOOL_DOUBLETAP, e.BTN_TOOL_TRIPLETAP,
                e.BTN_TOOL_QUADTAP, e.BTN_TOOL_QUINTTAP]


def create_device():
    pos = AbsInfo(0, 0, PAD_MAX, 0, 0, UNITS_PER_MM)
    caps = {
        e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_TOUCH] + TOOL_BUTTONS[1:],
        e.EV_ABS: [
            (e.ABS_X, pos),
            (e.ABS_Y, pos),
            (e.ABS_MT_SLOT, AbsInfo(0, 0, MAX_SLOTS - 1, 0, 0, 0)),
            (e.ABS_MT_TRACKING_ID, AbsInfo(0, 0, 65535, 0, 0, 0)),
            (e.ABS_MT_POSITION_X, pos),
            (e.ABS_MT_POSITION_Y, pos),
        ],
    }
    return UInput(caps, name='Zorin Connect Touchpad', vendor=0x1209, product=0x7a01,
                  version=1, input_props=[e.INPUT_PROP_POINTER])


class Pad:
    def __init__(self):
        self.dev = create_device()
        self.slots = {}          # slot -> [pointerId, x, y, trackingId]
        self.next_tracking_id = 0
        self.tool_count = 0
        self.first = None        # (x, y) last reported through ABS_X/ABS_Y

    @staticmethod
    def _units(mm):
        return max(0, min(PAD_MAX, int(round(mm * UNITS_PER_MM))))

    def apply(self, fingers):
        d = self.dev
        wanted = {}
        for pid, x, y in fingers[:MAX_SLOTS]:
            wanted[int(pid)] = (self._units(x), self._units(y))

        for slot, (pid, _, _, _) in list(self.slots.items()):
            if pid not in wanted:
                d.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
                d.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, -1)
                del self.slots[slot]

        by_pid = {v[0]: s for s, v in self.slots.items()}
        for pid, (x, y) in wanted.items():
            slot = by_pid.get(pid)
            if slot is None:
                slot = next(s for s in range(MAX_SLOTS) if s not in self.slots)
                tid = self.next_tracking_id
                self.next_tracking_id = (tid + 1) % 65535
                self.slots[slot] = [pid, x, y, tid]
                d.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
                d.write(e.EV_ABS, e.ABS_MT_TRACKING_ID, tid)
                d.write(e.EV_ABS, e.ABS_MT_POSITION_X, x)
                d.write(e.EV_ABS, e.ABS_MT_POSITION_Y, y)
            else:
                s = self.slots[slot]
                if (s[1], s[2]) != (x, y):
                    d.write(e.EV_ABS, e.ABS_MT_SLOT, slot)
                    if s[1] != x:
                        d.write(e.EV_ABS, e.ABS_MT_POSITION_X, x)
                    if s[2] != y:
                        d.write(e.EV_ABS, e.ABS_MT_POSITION_Y, y)
                    s[1], s[2] = x, y

        # ABS_X/ABS_Y follow the lowest active slot, as on a single-touch-compatible pad.
        count = len(self.slots)
        if count:
            s = self.slots[min(self.slots)]
            if self.first != (s[1], s[2]):
                d.write(e.EV_ABS, e.ABS_X, s[1])
                d.write(e.EV_ABS, e.ABS_Y, s[2])
                self.first = (s[1], s[2])
        else:
            self.first = None

        if count != self.tool_count:
            if self.tool_count:
                d.write(e.EV_KEY, TOOL_BUTTONS[self.tool_count], 0)
            if count:
                d.write(e.EV_KEY, TOOL_BUTTONS[count], 1)
            d.write(e.EV_KEY, e.BTN_TOUCH, 1 if count else 0)
            self.tool_count = count
        d.syn()

    def close(self):
        try:
            self.apply([])
        finally:
            self.dev.close()


def reader(frames):
    for line in sys.stdin:
        try:
            touch = json.loads(line)['touch']
            frames.put((time.monotonic(), touch))
        except (ValueError, KeyError, TypeError):
            continue
    frames.put(None)


def main():
    try:
        pad = Pad()
    except Exception as err:  # UInputError is not an OSError
        sys.stderr.write(f'zorin-touchpad-helper: cannot create uinput device: {err}\n')
        return 1

    frames = queue.Queue()
    threading.Thread(target=reader, args=(frames,), daemon=True).start()

    base = None          # estimated (arrival - phone time) for the fastest packets, seconds
    last_arrival = 0.0
    last_seq = -1
    last_phone_t = 0.0
    last_applied = 0.0
    try:
        while True:
            item = frames.get()
            if item is None:
                break
            arrival, touch = item
            try:
                seq = int(touch.get('seq', 0))
                phone_t = float(touch['t']) / 1000.0
                fingers = [(p[0], float(p[1]), float(p[2])) for p in touch.get('p', [])]
            except (KeyError, TypeError, ValueError, IndexError):
                continue

            fresh = arrival - last_arrival > NEW_TOUCH_GAP
            if seq <= last_seq and not fresh:
                continue
            last_seq, last_arrival = seq, arrival

            offset = arrival - phone_t
            base = offset if (base is None or fresh) else min(base, offset) + 0.00005
            due = phone_t + base + PLAYOUT_DELAY

            # Never skip frames to catch up: libinput reads the skipped distance as a jump
            # ("touch jump detected") and discards the touch. Late frames are applied at once.
            # A backlog (slow helper start, network stall) must not be applied as one burst
            # either, so keep at least half of the original spacing between applied frames.
            if not fresh:
                due = max(due, last_applied + (phone_t - last_phone_t) * CATCH_UP)
            now = time.monotonic()
            if now < due:
                time.sleep(due - now)
            pad.apply(fingers)
            last_phone_t, last_applied = phone_t, time.monotonic()
    finally:
        pad.close()
    return 0


if __name__ == '__main__':
    sys.exit(main())
