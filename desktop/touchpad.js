// SPDX-License-Identifier: GPL-2.0-or-later

import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

const HELPER = GLib.build_filenamev([
    GLib.path_get_dirname(GLib.filename_from_uri(import.meta.url)[0]),
    '..',
    'zorin-touchpad-helper.py',
]);

/**
 * Whether touch frames can be replayed here: the helper is installed and /dev/uinput is writable.
 * Announced to the phone, which falls back to its classic gestures otherwise.
 *
 * @returns {boolean} True if raw touch is usable
 */
export function isAvailable() {
    return GLib.file_test(HELPER, GLib.FileTest.EXISTS) && GLib.access('/dev/uinput', 2) === 0;
}

const MIN_BACKOFF = 1;
const MAX_BACKOFF = 30;

/**
 * Forwards phone touch frames to zorin-touchpad-helper.py, which replays them as a
 * virtual touchpad. The helper is started on the first frame and restarted, with a
 * backoff, if it dies.
 */
export default class TouchpadBridge {
    constructor() {
        this._proc = null;
        this._stdin = null;
        this._inFlight = false;
        this._pending = null;
        this._backoff = MIN_BACKOFF;
        this._retryAt = 0;
        this._destroyed = false;
    }

    /**
     * @param {object} touch - The `touch` object of a `kdeconnect.mousepad.request`
     */
    sendFrame(touch) {
        if (this._destroyed)
            return;

        if (!this._ensureHelper())
            return;

        this._write(`${JSON.stringify({touch})}\n`);
    }

    /**
     * Lift every finger, e.g. when the device disconnects.
     */
    release() {
        if (this._proc)
            this._write(`${JSON.stringify({touch: {seq: 0, t: 0, p: []}})}\n`);
    }

    destroy() {
        this._destroyed = true;
        this.release();
        this._stop();
    }

    _ensureHelper() {
        if (this._proc)
            return true;

        if (GLib.get_monotonic_time() / 1e6 < this._retryAt)
            return false;

        try {
            this._proc = new Gio.Subprocess({
                argv: ['python3', HELPER],
                flags: Gio.SubprocessFlags.STDIN_PIPE | Gio.SubprocessFlags.STDERR_PIPE,
            });
            this._proc.init(null);
        } catch (e) {
            logError(e, 'Zorin Connect: failed to start touchpad helper');
            this._proc = null;
            this._scheduleRetry();
            return false;
        }

        const proc = this._proc;
        this._stdin = proc.get_stdin_pipe();
        this._inFlight = false;
        this._pending = null;

        proc.wait_async(null, () => {
            if (this._proc !== proc)
                return;

            const status = proc.get_if_exited() ? proc.get_exit_status() : -1;
            if (status !== 0)
                log(`Zorin Connect: touchpad helper exited (${status})`);

            this._proc = null;
            this._stdin = null;
            if (!this._destroyed && status !== 0)
                this._scheduleRetry();
        });

        return true;
    }

    _scheduleRetry() {
        this._retryAt = GLib.get_monotonic_time() / 1e6 + this._backoff;
        this._backoff = Math.min(this._backoff * 2, MAX_BACKOFF);
    }

    // One write in flight at a time. Frames carry the full finger state, so under
    // backpressure only the newest waiting frame needs to be kept.
    _write(line) {
        if (this._inFlight) {
            this._pending = line;
            return;
        }

        this._inFlight = true;
        const stdin = this._stdin;
        stdin.write_bytes_async(new GLib.Bytes(new TextEncoder().encode(line)), GLib.PRIORITY_DEFAULT, null, (s, res) => {
            this._inFlight = false;
            try {
                s.write_bytes_finish(res);
                this._backoff = MIN_BACKOFF;
            } catch (e) {
                return; // helper went away; wait_async handles the restart
            }

            if (this._pending !== null && this._stdin === stdin) {
                const next = this._pending;
                this._pending = null;
                this._write(next);
            }
        });
    }

    _stop() {
        if (!this._proc)
            return;

        const proc = this._proc;
        this._proc = null;
        try {
            this._stdin.close(null);
        } catch (e) {
            // already closed
        }
        this._stdin = null;
        // EOF on stdin makes the helper release the pad and exit; make sure it does.
        GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 2, () => {
            proc.force_exit();
            return GLib.SOURCE_REMOVE;
        });
    }
}
