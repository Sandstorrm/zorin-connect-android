#!/bin/bash
# Removes everything the touchpad support added to this computer, so it is back to stock Zorin Connect:
#   - typed into a terminal by the app ("Remove touchpad drivers"): bash <(curl -fsSL <raw url of this file>)
#   - or run from the phone's "Run command" list (~/.local/bin/zorin-touchpad-uninstall)
#   - or by hand: bash uninstall.sh   (as your normal user; it asks for sudo itself)
# Self-contained: needs nothing else from the repo.
# Not undone: Zorin Connect package upgrades. Packages the installer added (python3-evdev, libinput-tools)
# are removed only if the installer recorded that it installed them.

STATE_ROOT=/var/lib/zorin-connect-touchpad
EXT=/usr/share/gnome-shell/extensions/zorin-connect@zorinos.com/service
STATE_USER="${XDG_STATE_HOME:-$HOME/.local/state}/zorin-connect-touchpad"
CACHE_USER="${XDG_CACHE_HOME:-$HOME/.cache}/zorin-connect-touchpad"

if [ -t 1 ]; then INTERACTIVE=1; else INTERACTIVE=0; fi
notify() { notify-send -a "Zorin Connect" -i input-touchpad "$1" "$2" 2>/dev/null || true; }

# Everything that needs root. Runs in its own shell (see as_root), so it must not use outer variables.
root_part() {
    EXT=/usr/share/gnome-shell/extensions/zorin-connect@zorinos.com/service
    STATE_ROOT=/var/lib/zorin-connect-touchpad
    PLUGIN="$EXT/plugins/mousepad.js"
    echo "Removing the update hook..."
    rm -f /etc/apt/apt.conf.d/99zorin-connect-touchpad
    rm -rf /usr/local/share/zorin-connect-touchpad

    echo "Restoring Zorin Connect's own mousepad plugin..."
    if [ -f "$PLUGIN.zc-orig" ] && ! grep -q TouchpadBridge "$PLUGIN.zc-orig"; then
        mv -f "$PLUGIN.zc-orig" "$PLUGIN"
    elif [ -f "$PLUGIN" ] && grep -q TouchpadBridge "$PLUGIN"; then
        echo "  no backup found, reinstalling the Zorin Connect package instead"
        apt-get install -y -q --reinstall gnome-shell-extension-zorin-connect || echo "  FAILED to reinstall"
    fi
    rm -f "$PLUGIN.zc-orig"
    rm -f "$EXT/zorin-touchpad-helper.py" "$EXT/utils/touchpad.js"

    echo "Removing the /dev/uinput permission rule..."
    rm -f /etc/udev/rules.d/70-zorin-uinput.rules /etc/udev/rules.d/99-zorin-uinput.rules
    udevadm control --reload-rules
    udevadm trigger --name-match=uinput --action=change || true
    setfacl -b /dev/uinput 2>/dev/null || true   # drop the per-user permission udev gave the logged-in user

    if [ -s "$STATE_ROOT/packages" ]; then
        # shellcheck disable=SC2046
        echo "Removing packages the installer added: $(tr '\n' ' ' < "$STATE_ROOT/packages")"
        apt-get remove -y -q $(cat "$STATE_ROOT/packages") || echo "  could not remove them"
    fi
    rm -rf "$STATE_ROOT"
    return 0
}

as_root() {
    local code
    code="$(declare -f root_part); root_part"
    if [ "$(id -u)" = 0 ]; then
        bash -c "$code"
    elif sudo -n true 2>/dev/null; then
        sudo -n bash -c "$code"
    elif [ "$INTERACTIVE" = 1 ]; then
        echo "This needs root; enter your sudo password if asked."
        sudo bash -c "$code"
    else
        pkexec bash -c "$code"
    fi
}

# Everything for the normal user: Run Command buttons, the GNOME touchpad setting, launchers, caches.
user_part() {
    if command -v python3 >/dev/null; then
        python3 - <<'PY' 2>/dev/null
from gi.repository import Gio, GLib

KEYS = ('zorin-connect-touchpad-update', 'zorin-connect-touchpad-uninstall')
ROOT = Gio.Settings.new('org.gnome.Shell.Extensions.ZorinConnect')
for dev in ROOT.get_strv('devices'):
    s = Gio.Settings.new_with_path(
        'org.gnome.Shell.Extensions.ZorinConnect.Plugin.RunCommand',
        f'/org/gnome/shell/extensions/zorin-connect/device/{dev}/plugin/runcommand/')
    current = s.get_value('command-list')
    entries = {}
    for i in range(current.n_children()):
        item = current.get_child_value(i)
        key = item.get_child_value(0).get_string()
        if key not in KEYS:
            entries[key] = item.get_child_value(1).get_variant()
    if len(entries) != current.n_children():
        s.set_value('command-list', GLib.Variant('a{sv}', entries))
        print(f'removed the Run Command buttons for device {dev}')
Gio.Settings.sync()
PY
    fi

    # Give the GNOME touchpad switch back the value it had before the installer turned it on.
    if [ -s "$STATE_USER/send-events-before" ] && command -v gsettings >/dev/null; then
        before="$(cat "$STATE_USER/send-events-before")"
        gsettings set org.gnome.desktop.peripherals.touchpad send-events "$before" &&
            echo "Set the GNOME touchpad setting back to '$before'."
    fi

    rm -f "$HOME/.local/bin/zorin-touchpad-update" "$HOME/.local/bin/zorin-touchpad-uninstall"
    rm -rf "$STATE_USER" "$CACHE_USER"
}

if [ "$(id -u)" = 0 ]; then
    echo "Running as root: only the system-wide part is removed. Run this as your normal user for the rest."
    as_root
    exit $?
fi

echo "Removing the touchpad support..."
if ! as_root; then
    echo "FAILED: could not get root rights, nothing was removed."
    notify "Touchpad removal failed" "Could not get root rights."
    exit 1
fi
user_part

notify "Touchpad support removed" "Zorin Connect restarts and the phone reconnects."
echo
echo "Done. Zorin Connect is restarting; the phone reconnects in a few seconds."
[ "$INTERACTIVE" = 1 ] && echo "You can close this window."
# Restart the daemon detached and after we have exited (it may be our parent); this also stops the helper.
setsid -f bash -c 'sleep 3; pkill -f "[z]orin-connect@zorinos.com/service/daemon.js"; pkill -f "[z]orin-touchpad-helper.py"' >/dev/null 2>&1
exit 0
