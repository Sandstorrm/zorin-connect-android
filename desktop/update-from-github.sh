#!/bin/bash
# One-button update of the computer side of the touchpad support, straight from GitHub.
# Meant to be started from the phone's "Run command" list (see register-run-command.sh).
# Fetches only desktop/ from the repo, runs install.sh with root rights and restarts the daemon.
# NOTE: this runs code from the repo as root, so only point it at a repo you control.
REPO="${ZC_TOUCHPAD_REPO:-https://github.com/Sandstorrm/zorin-connect-android.git}"
BRANCH="${ZC_TOUCHPAD_BRANCH:-master}"
DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zorin-connect-touchpad"
SRC="$DIR/repo"
LOG="$DIR/update.log"
BIN="$HOME/.local/bin/zorin-touchpad-update"

mkdir -p "$DIR" "$(dirname "$BIN")"
exec >>"$LOG" 2>&1
echo "=== $(date) ==="

notify() { notify-send -a "Zorin Connect" -i input-touchpad "$1" "$2" 2>/dev/null || true; }
fail() { echo "FAILED: $1"; notify "Touchpad update failed" "$1 (log: $LOG)"; exit 1; }

fetch() {
    if [ -d "$SRC/.git" ]; then
        git -C "$SRC" fetch --depth 1 origin "$BRANCH" && git -C "$SRC" reset --hard FETCH_HEAD
    else
        rm -rf "$SRC"
        git clone --depth 1 --branch "$BRANCH" --filter=blob:none --sparse "$REPO" "$SRC" &&
            git -C "$SRC" sparse-checkout set desktop
    fi
}
fetch || fail "could not fetch $REPO"
REV="$(git -C "$SRC" rev-parse --short HEAD)"
echo "fetched $REV"
[ -f "$SRC/desktop/install.sh" ] || fail "desktop/install.sh missing in $REV"

# Passwordless sudo if configured, otherwise the graphical polkit prompt.
if sudo -n true 2>/dev/null; then
    sudo -n bash "$SRC/desktop/install.sh"
else
    pkexec bash "$SRC/desktop/install.sh"
fi || fail "installer failed or was cancelled"

# Refresh this launcher too (new inode, so the running copy is unaffected).
install -m 0755 "$SRC/desktop/update-from-github.sh" "$BIN.new" && mv -f "$BIN.new" "$BIN"

notify "Touchpad support updated" "Now at $REV. Zorin Connect restarts and the phone reconnects."
echo "done $REV"
# The daemon started us, so restart it detached and after we have exited.
setsid -f bash -c 'sleep 3; pkill -f "[z]orin-connect@zorinos.com/service/daemon.js"' >/dev/null 2>&1
