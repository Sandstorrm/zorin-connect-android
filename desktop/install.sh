#!/bin/bash
# Installs the phone-as-touchpad support for Zorin Connect. Run with sudo; safe to repeat.
# The original mousepad.js is kept as mousepad.js.zc-orig. After a Zorin Connect package
# update run this again, or install the optional hook with install-update-hook.sh.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
EXT=/usr/share/gnome-shell/extensions/zorin-connect@zorinos.com/service

# an earlier version of this installer copied a whole patched mousepad.js: restore the original first
[ -e "$EXT/plugins/mousepad.js.zc-orig" ] && cp -a "$EXT/plugins/mousepad.js.zc-orig" "$EXT/plugins/mousepad.js"
"$SRC/apply.sh"

rm -f /etc/udev/rules.d/99-zorin-uinput.rules
# must sort before 73-seat-late.rules for the uaccess tag to take effect
install -m 0644 "$SRC/70-zorin-uinput.rules" /etc/udev/rules.d/70-zorin-uinput.rules
udevadm control --reload-rules
udevadm trigger --name-match=uinput --action=change || true
# optional: gives `libinput debug-events` for checking what GNOME sees
command -v libinput >/dev/null 2>&1 || apt-get install -y -q libinput-tools || true
# keep the optional apt update hook current if it is installed
[ -e /etc/apt/apt.conf.d/99zorin-connect-touchpad ] && "$SRC/install-update-hook.sh"
echo "done. Restart the daemon: pkill -f zorin-connect@zorinos.com/service/daemon.js"
