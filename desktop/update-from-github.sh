#!/bin/bash
# Installs or updates the computer side of the touchpad support, straight from GitHub.
#   - typed into a terminal by the app ("Install drivers"): bash <(curl -fsSL <raw url of this file>)
#   - or started from the phone's "Run command" list (registered by register-run-command.sh)
# Downloads only desktop/ (curl + tar, no git needed), runs install.sh with root rights,
# registers the Run Command button and restarts the daemon.
# NOTE: this runs code from the repo as root, so only point it at a repo you control.
REPO="${ZC_TOUCHPAD_REPO:-Sandstorrm/zorin-connect-android}"   # GitHub owner/name
BRANCH="${ZC_TOUCHPAD_BRANCH:-master}"
DIR="${XDG_CACHE_HOME:-$HOME/.cache}/zorin-connect-touchpad"
SRC="$DIR/repo"
LOG="$DIR/update.log"

mkdir -p "$DIR"
if [ -t 1 ]; then
    INTERACTIVE=1
    exec > >(tee -a "$LOG") 2>&1
else
    INTERACTIVE=0
    exec >>"$LOG" 2>&1
fi
echo "=== $(date) ==="

notify() { notify-send -a "Zorin Connect" -i input-touchpad "$1" "$2" 2>/dev/null || true; }
fail() { echo "FAILED: $1"; notify "Touchpad install failed" "$1 (log: $LOG)"; exit 1; }

fetch() {
    local tmp
    tmp="$(mktemp -d)" || return 1
    if curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/$BRANCH" |
        tar -xz -C "$tmp" --strip-components=1 --wildcards '*/desktop' &&
        [ -f "$tmp/desktop/install.sh" ]; then
        rm -rf "$SRC"
        mkdir -p "$SRC"
        mv "$tmp/desktop" "$SRC/desktop"
        rm -rf "$tmp"
        return 0
    fi
    rm -rf "$tmp"
    return 1
}

command -v curl >/dev/null || fail "curl is not installed"
echo "Downloading $REPO ($BRANCH)..."
fetch || fail "could not download $REPO"
REV="$(curl -fsSL -H 'Accept: application/vnd.github.sha' "https://api.github.com/repos/$REPO/commits/$BRANCH" 2>/dev/null | cut -c1-7)"
REV="${REV:-latest}"
echo "Downloaded $REV"

echo "Installing (this needs root; enter your sudo password if asked)..."
if sudo -n true 2>/dev/null; then
    sudo -n bash "$SRC/desktop/install.sh"
elif [ "$INTERACTIVE" = 1 ]; then
    sudo bash "$SRC/desktop/install.sh"
else
    pkexec bash "$SRC/desktop/install.sh"
fi || fail "the installer failed or was cancelled"

# Add the Run Command button and the launcher to ~/.local/bin (as the normal user).
bash "$SRC/desktop/register-run-command.sh" || echo "note: could not register the Run Command button"

notify "Touchpad support installed" "Version $REV. Zorin Connect restarts and the phone reconnects."
echo
echo "Done ($REV). Zorin Connect is restarting; the phone reconnects in a few seconds."
[ "$INTERACTIVE" = 1 ] && echo "You can close this window."
# Restart the daemon detached and after we have exited (it may be our parent).
setsid -f bash -c 'sleep 3; pkill -f "[z]orin-connect@zorinos.com/service/daemon.js"' >/dev/null 2>&1
exit 0
