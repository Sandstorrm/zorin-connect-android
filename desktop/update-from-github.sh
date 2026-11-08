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

# The phone that started us (typed by the app, or set by the daemon for Run Command).
PHONE_ID="${ZC_PHONE_ID:-$ZORIN_CONNECT_DEVICE_ID}"

mkdir -p "$DIR"
START_LINE="$(( $(wc -l < "$LOG" 2>/dev/null || echo 0) + 1 ))"
if [ -t 1 ]; then
    INTERACTIVE=1
    exec > >(tee -a "$LOG") 2>&1
else
    INTERACTIVE=0
    exec >>"$LOG" 2>&1
fi
echo "=== $(date) ==="

diagnostics() {
    echo "--- system"
    grep -E '^(PRETTY_NAME|VERSION)=' /etc/os-release
    echo "kernel: $(uname -r)  session: ${XDG_SESSION_TYPE:-?}  user: $USER"
    echo "gnome-shell: $(gnome-shell --version 2>&1 | head -1)"
    echo "zorin-connect: $(dpkg-query -W -f='${Version}' gnome-shell-extension-zorin-connect 2>&1 | head -1)"
    echo "curl: $(command -v curl || echo missing)  tar: $(command -v tar || echo missing)  python3: $(python3 --version 2>&1)"
    python3 -c 'import evdev; print("python3-evdev: ok")' 2>&1 | tail -1
    echo "uinput: $(ls -l /dev/uinput 2>&1)"
    echo "sudo -n: $(sudo -n true 2>&1 && echo ok)  phone id: ${PHONE_ID:-none}"
    echo "---"
}
diagnostics

notify() { notify-send -a "Zorin Connect" -i input-touchpad "$1" "$2" 2>/dev/null || true; }

# Send this run's log to the phone (it lands in the app's received files / Downloads).
send_log() {
    [ -n "$PHONE_ID" ] || return 0
    command -v gdbus >/dev/null || return 0
    sleep 0.5   # let tee flush
    local out="$DIR/touchpad-install-failure-$(hostname)-$(date +%H%M%S).log"
    tail -n +"$START_LINE" "$LOG" > "$out"
    gdbus call --session --dest org.gnome.Shell.Extensions.ZorinConnect \
        --object-path "/org/gnome/Shell/Extensions/ZorinConnect/Device/${PHONE_ID//[^[:alnum:]_]/_}" \
        --method org.gtk.Actions.Activate shareFile "[<('$out', false)>]" "{}" >/dev/null 2>&1 &&
        echo "Sent the log to your phone: $out"
}

# Zorin OS 17 and earlier (GNOME 43) have a Zorin Connect too old for the touchpad support.
unsupported() {
    local msg="The touchpad driver needs Zorin OS 18 (GNOME 46 or newer). This computer runs an older Zorin OS (GNOME ${GNOME_MAJOR:-?}). Update Zorin OS first, then try again."
    echo
    echo "UNSUPPORTED: $msg"
    notify "Update Zorin OS first" "$msg"
    if [ -n "$PHONE_ID" ] && command -v gdbus >/dev/null; then
        gdbus call --session --dest org.gnome.Shell.Extensions.ZorinConnect \
            --object-path "/org/gnome/Shell/Extensions/ZorinConnect/Device/${PHONE_ID//[^[:alnum:]_]/_}" \
            --method org.gtk.Actions.Activate shareText "[<'$msg'>]" "{}" >/dev/null 2>&1
    fi
    if [ "$INTERACTIVE" = 1 ]; then
        read -r -p "Open the Zorin OS upgrader now? [y/N] " answer </dev/tty
        case "$answer" in
            [yY]*) gtk-launch com.zorin.desktop.upgrader || zorin-os-upgrader ;;
        esac
    fi
    exit 2
}

fail() {
    echo "FAILED: $1"
    notify "Touchpad install failed" "$1 (log: $LOG)"
    send_log
    exit 1
}

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

GNOME_MAJOR="${ZC_GNOME_MAJOR:-$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)}"
if [ -n "$GNOME_MAJOR" ] && [ "$GNOME_MAJOR" -lt 46 ]; then
    unsupported
fi

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
fi
case $? in
    0) ;;
    2) unsupported ;;
    *) fail "the installer failed or was cancelled" ;;
esac

# GNOME can switch all touchpads off (Settings > Mouse & Touchpad); that also silences the phone's
# virtual touchpad. Turn it back on, and remember the old value so uninstall.sh can restore it.
if command -v gsettings >/dev/null; then
    TP_SCHEMA=org.gnome.desktop.peripherals.touchpad
    if [ "$(gsettings get $TP_SCHEMA send-events 2>/dev/null)" = "'disabled'" ]; then
        STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zorin-connect-touchpad"
        mkdir -p "$STATE_DIR" && echo disabled > "$STATE_DIR/send-events-before"
        gsettings set $TP_SCHEMA send-events enabled &&
            echo "The touchpad was switched off in the GNOME settings, which also disables the phone touchpad. Switched it on."
    fi
fi

# Add the Run Command button and the launcher to ~/.local/bin (as the normal user).
bash "$SRC/desktop/register-run-command.sh" || echo "note: could not register the Run Command button"

notify "Touchpad support installed" "Version $REV. Zorin Connect restarts and the phone reconnects."
echo
echo "Done ($REV). Zorin Connect is restarting; the phone reconnects in a few seconds."
[ "$INTERACTIVE" = 1 ] && echo "You can close this window."
# Restart the daemon detached and after we have exited (it may be our parent).
setsid -f bash -c 'sleep 3; pkill -f "[z]orin-connect@zorinos.com/service/daemon.js"' >/dev/null 2>&1
exit 0
