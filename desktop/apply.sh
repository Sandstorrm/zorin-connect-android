#!/bin/bash
# Applies the touchpad support to the installed Zorin Connect extension. Idempotent;
# also run by an apt hook after package updates. Never fails the package manager.
EXT=/usr/share/gnome-shell/extensions/zorin-connect@zorinos.com/service
HERE="$(cd "$(dirname "$0")" && pwd)"
[ -d "$EXT" ] || exit 0

install -m 0755 "$HERE/zorin-touchpad-helper.py" "$EXT/zorin-touchpad-helper.py"
install -m 0644 "$HERE/touchpad.js" "$EXT/utils/touchpad.js"

PLUGIN="$EXT/plugins/mousepad.js"
if grep -q TouchpadBridge "$PLUGIN"; then
    exit 0
fi
cp -a "$PLUGIN" "$PLUGIN.zc-orig"
if ! patch --forward --silent "$PLUGIN" < "$HERE/mousepad.patch"; then
    echo "zorin-connect-touchpad: mousepad.js changed upstream, patch not applied (touchpad falls back to classic mode)" >&2
    rm -f "$PLUGIN.rej" "$PLUGIN.orig"
    cp -a "$PLUGIN.zc-orig" "$PLUGIN"
fi
exit 0
