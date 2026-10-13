#!/bin/bash
#
# The executable inside the launcher app bundle (see build-app.sh).
#
# It asks whether to mirror only or to mirror and record, picks a device when
# more than one is attached, then hands the whole session to the CLI. Quitting
# the app forwards a Ctrl-C, so a recording always gets its index written.
#
# Environment overrides, used by the tests and handy for scripting:
#   IOSCPY_LAUNCHER_MODE=play|record   skip the first dialog
#   IOSCPY_LAUNCHER_UDID=<udid>        skip the device picker
#   IOSCPY_LAUNCHER_MOVIES=<dir>       where recordings go (default ~/Movies)
#   IOSCPY_LAUNCHER_QUIET=1            no dialogs, log lines only

# An app launched from Finder inherits a bare PATH, so add the places the CLI and
# its libimobiledevice helpers are normally installed.
export PATH="$HOME/.cargo/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

TITLE="ioscpy"
QUIET="${IOSCPY_LAUNCHER_QUIET:-0}"
RECORD_DIR="${IOSCPY_LAUNCHER_MOVIES:-$HOME/Movies}"
LOG_DIR="$HOME/Library/Logs/ioscpy"
# `pgrep -x` matches the mirror's process name exactly, so a shell or this script
# is never mistaken for a running mirror just because the path appears in its
# command line.
IOSCPY_NAME="ioscpy"

mkdir -p "$RECORD_DIR" "$LOG_DIR"

# Escape a string so it can go inside an AppleScript "quoted" literal.
as_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'; }

notify() { # notify <message>
    if [ "$QUIET" = "1" ]; then
        printf 'ioscpy: %s\n' "$1"
        return
    fi
    osascript -e "display dialog \"$(as_escape "$1")\" buttons {\"OK\"} default button 1 with title \"$TITLE\" with icon note" >/dev/null 2>&1
}

ioscpy_bin="$(command -v ioscpy)"
if [ -z "$ioscpy_bin" ]; then
    notify "ioscpy was not found in PATH. Install it first (brew install ioscpy, or cargo install --path host)."
    exit 1
fi

# 1. What to do -----------------------------------------------------------------
mode="${IOSCPY_LAUNCHER_MODE:-}"
if [ "$mode" != "play" ] && [ "$mode" != "record" ]; then
    choice=$(osascript <<'AS' 2>/dev/null
button returned of (display dialog "Mirror only, or mirror and record?" buttons {"Cancel", "Mirror only", "Mirror + Record"} default button "Mirror + Record" cancel button "Cancel" with title "ioscpy" with icon note)
AS
    ) || exit 0
    case "$choice" in
        "Mirror only") mode="play" ;;
        "Mirror + Record") mode="record" ;;
        *) exit 0 ;;
    esac
fi

# 2. Which device ---------------------------------------------------------------
udid="${IOSCPY_LAUNCHER_UDID:-}"
if [ -z "$udid" ]; then
    # `ioscpy --list` prints one line per device, starting with the UDID.
    devices="$(ioscpy --list 2>/dev/null | grep -E '^[0-9A-Fa-f-]{25,}[[:space:]]')"
    if [ -z "$devices" ]; then
        notify "No iPhone detected. Connect it with a cable, unlock it and trust this Mac, then try again."
        exit 1
    fi
    if [ "$(printf '%s\n' "$devices" | wc -l | tr -d ' ')" = "1" ]; then
        udid="$(printf '%s\n' "$devices" | awk '{print $1}')"
    else
        items=""
        while IFS= read -r line; do
            [ -n "$items" ] && items="$items, "
            items="$items\"$(as_escape "$line")\""
        done <<< "$devices"
        chosen=$(osascript <<AS 2>/dev/null
set theItems to {$items}
set theChoice to choose from list theItems with prompt "Choose the device to mirror (it needs the ioscpy package installed):" with title "$TITLE" OK button name "Connect" cancel button name "Cancel"
if theChoice is false then error number -128
return item 1 of theChoice
AS
        ) || exit 0
        udid="$(printf '%s' "$chosen" | awk '{print $1}')"
    fi
fi

# 3. Step aside for a session that is already running ---------------------------
if pgrep -x "$IOSCPY_NAME" >/dev/null 2>&1; then
    if [ "$QUIET" = "1" ]; then
        pkill -INT -x "$IOSCPY_NAME" 2>/dev/null
    else
        answer=$(osascript <<'AS' 2>/dev/null
button returned of (display dialog "ioscpy is already running. Close it and start a new session? Any recording in progress is finalized first." buttons {"Cancel", "Close and continue"} default button "Close and continue" cancel button "Cancel" with title "ioscpy" with icon caution)
AS
        ) || exit 0
        [ "$answer" = "Close and continue" ] || exit 0
        # SIGINT is what Ctrl-C sends: the recording in progress is finalized.
        pkill -INT -x "$IOSCPY_NAME" 2>/dev/null
    fi
    for _ in $(seq 1 10); do
        pgrep -x "$IOSCPY_NAME" >/dev/null 2>&1 || break
        sleep 0.3
    done
    if pgrep -x "$IOSCPY_NAME" >/dev/null 2>&1; then
        notify "The previous ioscpy did not exit. Close its window and try again."
        exit 1
    fi
fi

# 4. Run it ---------------------------------------------------------------------
stamp="$(date +%Y-%m-%d-%H%M%S)"
log="$LOG_DIR/launcher-$stamp.log"
args=("--device" "$udid")
recording=""
if [ "$mode" = "record" ]; then
    recording="$RECORD_DIR/ioscpy-$stamp.mp4"
    args+=("--record" "$recording")
fi

# Forward a Quit (SIGTERM) as Ctrl-C, so the recording is finalized either way.
# Job control puts the mirror in its own process group, so the signal lands even
# when this script was itself started as a background job.
set -m
child=0
forward_int() {
    [ "$child" = "0" ] && return
    kill -INT -- "-$child" 2>/dev/null || kill -INT "$child" 2>/dev/null
}
trap forward_int INT TERM

"$ioscpy_bin" "${args[@]}" >>"$log" 2>&1 &
child=$!
while kill -0 "$child" 2>/dev/null; do
    wait "$child"
done
child=0

# 5. Say where the file went ----------------------------------------------------
if [ "$mode" = "record" ]; then
    saved="$(ls -1 "$RECORD_DIR/ioscpy-$stamp"*.mp4 2>/dev/null | head -1)"
    if [ -z "$saved" ]; then
        notify "Nothing was recorded. The log is at $log"
        exit 0
    fi
    if [ "$QUIET" = "1" ]; then
        printf 'ioscpy: recording saved: %s\n' "$saved"
        exit 0
    fi
    answer=$(osascript <<AS 2>/dev/null
button returned of (display dialog "Recording saved:\n$(as_escape "$saved")" buttons {"OK", "Show in Finder"} default button "OK" with title "$TITLE" with icon note)
AS
    ) || answer="OK"
    [ "$answer" = "Show in Finder" ] && open -R "$saved"
fi

exit 0
