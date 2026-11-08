# Phone as a real touchpad (desktop side)

With "Raw touchpad mode" on, the Android app sends the full finger state (`kdeconnect.mousepad.request`
with a `touch` body) instead of pre-digested mouse deltas. The daemon replays it as a virtual multitouch
touchpad through uinput, so GNOME/libinput does scrolling, taps and 3-finger gestures natively.

    phone -> daemon (plugins/mousepad.js, `touch` case) -> TouchpadBridge (utils/touchpad.js)
          -> zorin-touchpad-helper.py (python-evdev UInput) -> libinput -> GNOME

Frame: `{"touch": {"seq": 12, "t": <phone ms>, "w": mm, "h": mm, "p": [[pointerId, x_mm, y_mm], ...]}}`.
An empty `p` means every finger is up. The daemon announces support with `rawTouch: true` in its
`kdeconnect.mousepad.keyboardstate` packet; without it the app uses its classic gestures.

## Install (Zorin Connect 74.1.2)

    sudo bash desktop/install.sh                # patch + helper + /dev/uinput access (udev uaccess rule)
    sudo bash desktop/install-update-hook.sh    # optional: re-apply after package updates
    pkill -f "[z]orin-connect@zorinos.com/service/daemon.js"

`patch_mousepad.py` edits the stock `mousepad.js` by code anchors (not line numbers), so it applies to every
Zorin Connect release for GNOME 46+ (tested on 58.2, 62.1, 66.1, 71, 72, 74, 74.1.1, 74.1.2). If an anchor is
missing it leaves the original untouched (exit 1); `apply.sh` keeps the original and the app falls back to classic mode.

## Supported systems

Zorin OS 18 (GNOME 46+, Zorin Connect 58+). Zorin OS 17 and earlier ship Zorin Connect 55.x, which uses the old
GJS `imports.` module system and cannot be patched; there the app shows "Update Zorin OS first" (it recognises the
old version because 55.x still announces the `kdeconnect.photo` capability) with an **Update Zorin OS for me**
button that opens the Zorin OS upgrader on the computer (`gtk-launch com.zorin.desktop.upgrader`), and the script
itself refuses GNOME < 46 and tells the phone. `install.sh` first upgrades the Zorin Connect packages and installs
`python3-evdev`; exit status 2 means "too old", 1 means any other failure (the log is sent to the phone).

## Installing on a new PC from the phone

Opening *Remote input* on a computer that has not announced `rawTouch` shows a chooser: **Install drivers**
or **Use legacy input** (remembered; the toolbar menu has *Install touchpad drivers* to run it later).
"Install drivers" makes the app press Ctrl+Alt+T on the computer and type

    bash <(curl -fsSL https://raw.githubusercontent.com/Sandstorrm/zorin-connect-android/master/desktop/update-from-github.sh)

then Enter. The computer must be unlocked, and a sudo password, if asked, is typed in that terminal (on the
PC keyboard or the phone's keyboard). `update-from-github.sh` downloads only `desktop/` (curl + tar, no git),
runs `install.sh` as root, adds the *Update touchpad support (GitHub)* button to the phone's Run command list,
installs `~/.local/bin/zorin-touchpad-update` and restarts the daemon so the phone reconnects.
`ZC_TOUCHPAD_REPO` (owner/name) and `ZC_TOUCHPAD_BRANCH` override the source. Log:
`~/.cache/zorin-connect-touchpad/update.log`. It runs repo code as root: only use a repo you control.

If the install fails, the script sends its log (with a short system summary: OS, GNOME and Zorin Connect versions,
uinput state) to the phone that started it. The app types `ZC_PHONE_ID=<phone id>` in front of the command, and the
Run command path gets the id from the daemon. The file arrives in the phone's Downloads / received files, and can be
pulled with `adb pull /sdcard/Download/touchpad-install-failure-*.log`.

The Run command button (`register-run-command.sh`, run by the script above) is for later updates; it uses
`sudo -n`, or a graphical `pkexec` prompt if sudo needs a password.

## Test without a phone

    python3 desktop/test_frames.py [--cold]

Replays a one-finger move and a two-finger scroll. `journalctl --user -f | grep libinput` should show no
"touch jump" errors; the helper never skips frames and paces any backlog for that reason.
