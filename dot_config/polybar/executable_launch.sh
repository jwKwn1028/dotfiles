#!/usr/bin/env bash
# Launch polybar on the primary monitor only.
# Toggle visibility from i3: bindsym $mod+Shift+b exec polybar-msg cmd toggle

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
