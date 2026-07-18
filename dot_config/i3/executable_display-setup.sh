#!/usr/bin/env bash

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

# Give Xfce's settings daemon and hotplug detection a moment to settle during login.
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

"$(dirname "$(readlink -f "$0")")/wallpaper.sh"
