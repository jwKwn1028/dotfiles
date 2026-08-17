#!/usr/bin/env bash
# One synchronized Polybar per active monitor; visibility is broadcast over IPC
# so every monitor toggles at once.
#
# The launcher lock serializes reloads and fallback launches, so a second
# launcher reuses the running one's bars instead of racing killall into
# duplicates. Long-lived children get 9>&- or they inherit the lock, and every
# later reload then waits five seconds, sees Polybar up, and skips the rebuild.
# Kills escalate to SIGKILL: a Polybar wedged on a dead i3 IPC socket never
# answers SIGTERM, and an unbounded `--wait` would hold the lock forever.
#
# X11 permits one tray owner, so icons stay on the laptop panel (primary if
# there is no internal one) -- an external can be unplugged mid-session. Dock
# order is arrival order, hence the wait for nm-applet before blueman-tray,
# keeping Wi-Fi left of Bluetooth for bar mode's h/l. Applets also own invisible
# 10x10 helper windows, so size identifies a real icon.
#
# Bars start hidden; the initial hide keeps broadcasting briefly after the first
# IPC endpoint so a slow secondary cannot miss it. Tray icons are foreign client
# windows Polybar's cursor-click never reaches, so tray-cursor.py paints them.

POLYBAR_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
POLYBAR_LAUNCH_LOCK="$POLYBAR_RUNTIME_DIR/polybar-launch.lock"
POLYBAR_LOG_DIR="${POLYBAR_LOG_DIR:-/tmp}"
mkdir -p "$POLYBAR_RUNTIME_DIR" 2>/dev/null || exit 1
exec 9>"$POLYBAR_LAUNCH_LOCK"
if ! flock -n 9; then
    flock -w 5 9 || exit 1
    pgrep -x polybar >/dev/null && exit 0
fi

RESTART_BLUEMAN_TRAY=0
if pgrep -x blueman-tray >/dev/null 2>&1; then
    RESTART_BLUEMAN_TRAY=1
    pkill -x blueman-tray >/dev/null 2>&1 || true
fi

timeout 5 killall -q --wait polybar 2>/dev/null || killall -q -9 polybar 2>/dev/null

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

icon_docked() {
    local win info
    for win in $(xdotool search --class "$1" 2>/dev/null); do
        info=$(xwininfo -id "$win" 2>/dev/null) || continue
        case "$info" in *IsViewable*) ;; *) continue ;; esac
        awk '$1 == "Width:" { w = $2 } $1 == "Height:" { h = $2 }
             END { exit !(w > 10 && w <= 64 && h > 10 && h <= 64) }' <<<"$info" &&
            return 0
    done
    return 1
}

launch_bar() {
    local monitor="$1"
    local bar="$2"
    local log="$POLYBAR_LOG_DIR/polybar-$monitor.log"

    printf '\n===== %s =====\n' "$STAMP" >>"$log"
    MONITOR="$monitor" setsid -f polybar --reload "$bar" >>"$log" 2>&1 9>&-
}

TRAY_OUTPUT="$PRIMARY"
for monitor in "${ACTIVE_OUTPUTS[@]}"; do
    case "$monitor" in
        eDP*|LVDS*)
            TRAY_OUTPUT="$monitor"
            break
            ;;
    esac
done

for monitor in "${ACTIVE_OUTPUTS[@]}"; do
    if [ "$monitor" = "$TRAY_OUTPUT" ]; then
        launch_bar "$monitor" tray
    elif [ "$monitor" = "$PRIMARY" ]; then
        launch_bar "$monitor" main
    else
        launch_bar "$monitor" external
    fi
done

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

pgrep -f 'polybar/scripts/tray-cursor.py' >/dev/null 2>&1 ||
    setsid -f "$HOME/.config/polybar/scripts/tray-cursor.py" >/dev/null 2>&1 9>&-

if [ "$RESTART_BLUEMAN_TRAY" = 1 ]; then
    for _ in $(seq 1 30); do
        icon_docked '^Nm-applet$' && break
        sleep 0.1
    done
    setsid -f blueman-tray >/dev/null 2>&1 9>&-
fi
