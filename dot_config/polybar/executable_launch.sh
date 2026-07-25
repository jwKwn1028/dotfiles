#!/usr/bin/env bash
# Launch polybar on the primary monitor only.
# Toggle visibility from i3: bindsym $mod+Shift+b exec polybar-msg cmd toggle

# Serialize i3 reloads and visibility-fallback launches. If another launcher is
# already active, wait for it and reuse the Polybar process it started instead
# of racing through killall and creating duplicate bars.
POLYBAR_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
POLYBAR_LAUNCH_LOCK="$POLYBAR_RUNTIME_DIR/polybar-launch.lock"
mkdir -p "$POLYBAR_RUNTIME_DIR" 2>/dev/null || exit 1
exec 9>"$POLYBAR_LAUNCH_LOCK"
if ! flock -n 9; then
    flock -w 5 9 || exit 1
    pgrep -x polybar >/dev/null && exit 0
fi

killall -q --wait polybar 2>/dev/null

PRIMARY=$(xrandr --query | awk '/ connected primary/ {print $1; exit}')
[ -z "$PRIMARY" ] && PRIMARY=$(xrandr --query | awk '/ connected/ {print $1; exit}')

LOG=/tmp/polybar-$PRIMARY.log
printf '\n===== %s =====\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
MONITOR=$PRIMARY setsid -f polybar --reload main >>"$LOG" 2>&1

# Start hidden — toggle with $mod+Shift+b.
for _ in $(seq 1 25); do
    polybar-msg cmd hide >/dev/null 2>&1 && break
    sleep 0.1
done
