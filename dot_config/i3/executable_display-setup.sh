#!/usr/bin/env bash
# Apply the monitor layout for the connected outputs, then recreate the
# per-monitor Polybar instances. The leading sleep lets xfsettingsd and hotplug
# detection settle. Super+Shift+P reruns this to pick up a hotplugged output.

DIR="$(dirname "$(readlink -f "$0")")"
LAPTOP_OUTPUT="${I3_LAPTOP_OUTPUT:-eDP}"

is_connected() {
    xrandr --query | awk -v output="$1" '$1 == output && $2 == "connected" { found = 1 } END { exit !found }'
}

connected_external_output() {
    xrandr --query | awk -v laptop="$LAPTOP_OUTPUT" '
        $2 == "connected" && $1 != laptop {
            print $1
            exit
        }
    '
}

apply_two_monitor_layout() {
    local external_output="$1"

    xrandr \
        --output "$external_output" --auto --pos 0x0 --rotate normal \
        --output "$LAPTOP_OUTPUT" --primary --auto --right-of "$external_output" --rotate normal
}

apply_laptop_only_layout() {
    xrandr \
        --output "$LAPTOP_OUTPUT" --primary --auto --pos 0x0 --rotate normal
}

sleep "${I3_DISPLAY_SETUP_DELAY:-1}"

if ! command -v xrandr >/dev/null 2>&1 || ! xrandr --query >/dev/null 2>&1; then
    exit 0
fi

for _ in $(seq 1 20); do
    is_connected "$LAPTOP_OUTPUT" && break
    sleep 0.25
done

EXTERNAL_OUTPUT="$(connected_external_output)"

if [ -n "$EXTERNAL_OUTPUT" ]; then
    apply_two_monitor_layout "$EXTERNAL_OUTPUT"
else
    apply_laptop_only_layout
fi

sleep 0.2

"$DIR/wallpaper.sh"

POLYBAR_LAUNCHER="${I3_POLYBAR_LAUNCHER:-$DIR/../polybar/launch.sh}"
if [ -x "$POLYBAR_LAUNCHER" ]; then
    "$POLYBAR_LAUNCHER"
fi

# Confirm i3 is up, after launch.sh has blocked until the bars are back. Only
# i3's exec_always sets I3_RELOAD_TOAST, and i3 4.23 reruns exec_always on
# $mod+Shift+r but not $mod+Shift+c; Super+Shift+P leaves it unset. The stamp
# sits in XDG_RUNTIME_DIR, which logind unmounts with the session, so its
# absence marks a login's first parse.
TOAST_STAMP="${XDG_RUNTIME_DIR:-/tmp}/i3-reload-toast"
if [ "${I3_RELOAD_TOAST:-0}" = 1 ]; then
    if [ -e "$TOAST_STAMP" ]; then
        TOAST_TEXT="i3 reloaded"
    else
        TOAST_TEXT="Welcome"
    fi
    if command -v rofi >/dev/null 2>&1; then
        # rofi 1.7.5 ignores a `timeout` block in -e mode, so time it out here.
        rofi -e "$TOAST_TEXT" -theme reload-toast &
        toast_pid=$!
        sleep 1
        kill "$toast_pid" 2>/dev/null
    fi
    touch "$TOAST_STAMP"
fi
