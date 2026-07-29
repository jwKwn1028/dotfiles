#!/usr/bin/env bash
# Launch one synchronized Polybar instance on every active monitor.
# Visibility commands are broadcast through Polybar IPC, so i3's explicit
# toggle and transient peek behavior affect every monitor together.

# Serialize i3 reloads and visibility-fallback launches. If another launcher is
# already active, wait for it and reuse the Polybar processes it started instead
# of racing through killall and creating duplicate bars.
POLYBAR_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
POLYBAR_LAUNCH_LOCK="$POLYBAR_RUNTIME_DIR/polybar-launch.lock"
POLYBAR_LOG_DIR="${POLYBAR_LOG_DIR:-/tmp}"
mkdir -p "$POLYBAR_RUNTIME_DIR" 2>/dev/null || exit 1
exec 9>"$POLYBAR_LAUNCH_LOCK"
if ! flock -n 9; then
    flock -w 5 9 || exit 1
    pgrep -x polybar >/dev/null && exit 0
fi

killall -q --wait polybar 2>/dev/null

XRANDR_OUTPUT=$(xrandr --query 2>/dev/null) || exit 0
mapfile -t ACTIVE_OUTPUTS < <(
    awk '
        $2 == "connected" {
            for (field = 3; field <= NF; field++) {
                if ($field ~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+/) {
                    print $1
                    break
                }
            }
        }
    ' <<<"$XRANDR_OUTPUT"
)
[ "${#ACTIVE_OUTPUTS[@]}" -gt 0 ] || exit 0

PRIMARY=$(
    awk '
        $2 == "connected" && $3 == "primary" {
            for (field = 4; field <= NF; field++) {
                if ($field ~ /^[0-9]+x[0-9]+[+-][0-9]+[+-][0-9]+/) {
                    print $1
                    exit
                }
            }
        }
    ' <<<"$XRANDR_OUTPUT"
)
[ -n "$PRIMARY" ] || PRIMARY="${ACTIVE_OUTPUTS[0]}"

mkdir -p "$POLYBAR_LOG_DIR" 2>/dev/null || exit 1
STAMP=$(date '+%Y-%m-%d %H:%M:%S')

launch_bar() {
    local monitor="$1"
    local bar="$2"
    local log="$POLYBAR_LOG_DIR/polybar-$monitor.log"

    printf '\n===== %s =====\n' "$STAMP" >>"$log"
    # Do not let the detached Polybar child inherit the launcher lock. If it
    # keeps fd 9 open, every later reload waits five seconds and then reuses the
    # stale monitor set instead of rebuilding it.
    MONITOR="$monitor" setsid -f polybar --reload "$bar" >>"$log" 2>&1 9>&-
}

# The primary bar owns the singleton X11 system tray. Secondary bars inherit
# the same layout and modules except for that tray.
launch_bar "$PRIMARY" main
for monitor in "${ACTIVE_OUTPUTS[@]}"; do
    [ "$monitor" = "$PRIMARY" ] && continue
    launch_bar "$monitor" external
done

# Start every instance hidden. Keep broadcasting briefly after the first IPC
# endpoint appears so a slower secondary process cannot miss the initial hide.
EXPECTED_BARS="${#ACTIVE_OUTPUTS[@]}"
READY_PASSES=0
for _ in $(seq 1 25); do
    polybar-msg cmd hide >/dev/null 2>&1 || true
    RUNNING_BARS=$(pgrep -xc polybar 2>/dev/null || true)
    if [ "${RUNNING_BARS:-0}" -ge "$EXPECTED_BARS" ]; then
        READY_PASSES=$((READY_PASSES + 1))
        [ "$READY_PASSES" -ge 2 ] && break
    else
        READY_PASSES=0
    fi
    sleep 0.1
done
polybar-msg cmd hide >/dev/null 2>&1 || true
