#!/bin/bash
# Optional: re-applies the touchpad support automatically after Zorin Connect package updates.
# Stages the files in /usr/local/share/zorin-connect-touchpad and adds an apt post-invoke hook
# (/etc/apt/apt.conf.d/99zorin-connect-touchpad). Remove both to undo.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run with sudo" >&2; exit 1; }
SRC="$(cd "$(dirname "$0")" && pwd)"
STAGE=/usr/local/share/zorin-connect-touchpad
install -d "$STAGE"
install -m 0755 "$SRC/zorin-touchpad-helper.py" "$SRC/apply.sh" "$STAGE/"
install -m 0644 "$SRC/touchpad.js" "$SRC/patch_mousepad.py" "$STAGE/"
cat > /etc/apt/apt.conf.d/99zorin-connect-touchpad <<'APT'
DPkg::Post-Invoke { "[ -x /usr/local/share/zorin-connect-touchpad/apply.sh ] && /usr/local/share/zorin-connect-touchpad/apply.sh || true"; };
APT
echo "update hook installed"
