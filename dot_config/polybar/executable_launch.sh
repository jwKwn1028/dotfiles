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

# Redock Blueman after nm-applet when the tray is recreated, preserving the
# visible Wi-Fi, Bluetooth order across monitor hotplug and manual relaunches.
RESTART_BLUEMAN_TRAY=0
if pgrep -x blueman-tray >/dev/null 2>&1; then
    RESTART_BLUEMAN_TRAY=1
    pkill -x blueman-tray >/dev/null 2>&1 || true
fi

# A wedged Polybar (its i3 IPC socket died with the previous i3) never acts on
# SIGTERM, and an unbounded `--wait` would then hold the launcher lock forever,
# so every later relaunch -- including the one that adds a hotplugged monitor's
# bar -- exits without doing anything. Escalate to SIGKILL instead of waiting.
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

# True once an applet's tray icon is embedded and mapped. The applet also owns
# invisible 10x10 helper windows, so size is what tells the icon apart.
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
    # Do not let the detached Polybar child inherit the launcher lock. If it
    # keeps fd 9 open, every later reload waits five seconds and then reuses the
    # stale monitor set instead of rebuilding it.
    MONITOR="$monitor" setsid -f polybar --reload "$bar" >>"$log" 2>&1 9>&-
}

# X11 permits only one tray owner, so the icons live on the laptop panel and
# stay there: an external output plugged in mid-session must not carry them off
# to a screen that goes away when it is unplugged. Fall back to the primary
# output on a machine with no internal panel.
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

if [ "$RESTART_BLUEMAN_TRAY" = 1 ]; then
    # Dock order is arrival order, and the applets re-dock on their own schedule
    # once they notice the new tray owner. Wait for nm-applet's icon so Wi-Fi
    # lands left of Bluetooth -- the order bar mode's H/L walks the two stops in.
    for _ in $(seq 1 30); do
        icon_docked '^Nm-applet$' && break
        sleep 0.1
    done
    # 9>&- for the same reason the bars get it: blueman-tray outlives this
    # script, and an inherited lock fd would make every later launch wait five
    # seconds, find Polybar already running, and exit without doing anything.
    setsid -f blueman-tray >/dev/null 2>&1 9>&-
fi
