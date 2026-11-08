#!/bin/bash
# Installs the phone-as-touchpad support for Zorin Connect. Run with sudo; safe to repeat.
# Exit status: 0 ok, 2 Zorin Connect too old (Zorin OS 17 and earlier), 1 anything else.
# The original mousepad.js is kept as mousepad.js.zc-orig. After a Zorin Connect package
# update run this again, or install the optional hook with install-update-hook.sh.
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
STATUS=0

# Update Zorin Connect itself first (newer versions fix compatibility problems).
if command -v apt-get >/dev/null; then
    apt-get update -qq || echo "note: apt-get update failed"
    apt-get install -y -q --only-upgrade gnome-shell-extension-zorin-connect zorin-connect ||
        echo "note: could not update Zorin Connect"
fi

# Installs a package and remembers it, so uninstall.sh removes only what we added.
STATE=/var/lib/zorin-connect-touchpad
install_pkg() {
    dpkg -s "$1" >/dev/null 2>&1 && return 0
    apt-get install -y -q "$1" || return 1
    mkdir -p "$STATE"
    grep -qx "$1" "$STATE/packages" 2>/dev/null || echo "$1" >> "$STATE/packages"
}

# The helper needs python-evdev.
python3 -c 'import evdev' 2>/dev/null || install_pkg python3-evdev || {
    echo "FAILED: could not install python3-evdev"
    STATUS=1
}

"$SRC/apply.sh"
APPLY=$?
[ $APPLY -ne 0 ] && STATUS=$APPLY

rm -f /etc/udev/rules.d/99-zorin-uinput.rules
# must sort before 73-seat-late.rules for the uaccess tag to take effect
install -m 0644 "$SRC/70-zorin-uinput.rules" /etc/udev/rules.d/70-zorin-uinput.rules
udevadm control --reload-rules
udevadm trigger --name-match=uinput --action=change || true
# optional: gives `libinput debug-events` for checking what GNOME sees
command -v libinput >/dev/null 2>&1 || install_pkg libinput-tools || true
# keep the optional apt update hook current if it is installed
[ -e /etc/apt/apt.conf.d/99zorin-connect-touchpad ] && "$SRC/install-update-hook.sh"
[ $STATUS -eq 0 ] && echo "done. Restart the daemon: pkill -f zorin-connect@zorinos.com/service/daemon.js"
exit $STATUS
