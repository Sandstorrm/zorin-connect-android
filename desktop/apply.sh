#!/bin/bash
# Applies the touchpad support to the installed Zorin Connect extension. Idempotent;
# also run by an apt hook after package updates (which ignores the exit status).
# Exit status: 0 ok, 1 failed, 2 unsupported (Zorin Connect too old: Zorin OS 17 and earlier).
EXT=/usr/share/gnome-shell/extensions/zorin-connect@zorinos.com/service
HERE="$(cd "$(dirname "$0")" && pwd)"
PLUGIN="$EXT/plugins/mousepad.js"
[ -f "$PLUGIN" ] || { echo "zorin-connect-touchpad: Zorin Connect is not installed" >&2; exit 1; }

install -m 0755 "$HERE/zorin-touchpad-helper.py" "$EXT/zorin-touchpad-helper.py"
install -m 0644 "$HERE/touchpad.js" "$EXT/utils/touchpad.js"

grep -q TouchpadBridge "$PLUGIN" && exit 0

cp -a "$PLUGIN" "$PLUGIN.zc-orig"
python3 "$HERE/patch_mousepad.py" "$PLUGIN"
rc=$?
if [ $rc -ne 0 ]; then
    cp -a "$PLUGIN.zc-orig" "$PLUGIN"
    echo "zorin-connect-touchpad: could not patch mousepad.js (exit $rc); the touchpad stays in classic mode" >&2
    echo "zorin-connect-touchpad: zorin-connect $(dpkg-query -W -f='${Version}' gnome-shell-extension-zorin-connect 2>/dev/null)" >&2
    grep -n -E "import \* as Components|_handleInput|switch \(true\)|disconnected\(|_sendState|share-control" "$PLUGIN" >&2
fi
exit $rc
