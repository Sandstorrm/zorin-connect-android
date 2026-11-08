#!/usr/bin/python3
"""Feeds fake phone frames to the helper: a one-finger move, then a two-finger scroll."""
import json
import subprocess
import sys
import time
from pathlib import Path

helper = Path(__file__).with_name('zorin-touchpad-helper.py')
proc = subprocess.Popen([sys.executable, str(helper)], stdin=subprocess.PIPE, text=True)
seq = 0
if '--cold' not in sys.argv:
    time.sleep(1.0)  # let the helper create its device before the first frame
t0 = time.monotonic()


def frame(points):
    global seq
    seq += 1
    t = int((time.monotonic() - t0) * 1000) + 1_000_000
    proc.stdin.write(json.dumps({'touch': {'seq': seq, 't': t, 'p': points}}) + '\n')
    proc.stdin.flush()


def drag(fingers, dx, dy, steps, seconds):
    for i in range(1, steps + 1):
        f = i / steps
        frame([[pid, x + dx * f, y + dy * f] for pid, x, y in fingers])
        time.sleep(seconds / steps)


# one finger moving right/down (cursor should move)
drag([(0, 40, 60)], 40, 20, 40, 0.4)
frame([])
time.sleep(0.6)
# two fingers moving up (should scroll down the focused window)
drag([(0, 40, 90), (1, 55, 90)], 0, -50, 60, 0.5)
frame([])
time.sleep(0.5)
proc.stdin.close()
sys.exit(proc.wait())
