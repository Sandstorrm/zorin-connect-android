#!/bin/bash
# Adds "Update touchpad support" and "Remove touchpad support" buttons to the Run Command list of every paired device
# (no root needed) and installs the launchers to ~/.local/bin (zorin-touchpad-update, zorin-touchpad-uninstall).
# Run again to refresh. uninstall.sh removes everything again.
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin/zorin-touchpad-update"
install -D -m 0755 "$SRC/update-from-github.sh" "$BIN"
BIN_UNINSTALL="$HOME/.local/bin/zorin-touchpad-uninstall"
install -D -m 0755 "$SRC/uninstall.sh" "$BIN_UNINSTALL"

BIN="$BIN" BIN_UNINSTALL="$BIN_UNINSTALL" python3 - <<'PY'
import os
from gi.repository import Gio, GLib

ROOT = Gio.Settings.new('org.gnome.Shell.Extensions.ZorinConnect')
for dev in ROOT.get_strv('devices'):
    s = Gio.Settings.new_with_path(
        'org.gnome.Shell.Extensions.ZorinConnect.Plugin.RunCommand',
        f'/org/gnome/shell/extensions/zorin-connect/device/{dev}/plugin/runcommand/')
    entries = {}
    current = s.get_value('command-list')
    for i in range(current.n_children()):
        item = current.get_child_value(i)
        entries[item.get_child_value(0).get_string()] = item.get_child_value(1).get_variant()
    entries['zorin-connect-touchpad-update'] = GLib.Variant('a{ss}', {
        'name': 'Update touchpad support (GitHub)',
        'command': os.environ['BIN'],
    })
    entries['zorin-connect-touchpad-uninstall'] = GLib.Variant('a{ss}', {
        'name': 'Remove touchpad support',
        'command': os.environ['BIN_UNINSTALL'],
    })
    s.set_value('command-list', GLib.Variant('a{sv}', entries))
    Gio.Settings.sync()
    print(f'registered for device {dev}')
PY
