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

`mousepad.patch` is the diff against the stock `mousepad.js` (`mousepad.js.orig`). If upstream changes that
file so the patch no longer applies, `apply.sh` keeps the original and the app falls back to classic mode.

## Test without a phone

    python3 desktop/test_frames.py [--cold]

Replays a one-finger move and a two-finger scroll. `journalctl --user -f | grep libinput` should show no
"touch jump" errors; the helper never skips frames and paces any backlog for that reason.
