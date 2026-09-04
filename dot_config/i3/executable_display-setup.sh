#!/usr/bin/env bash
# Apply the monitor layout for the connected outputs, then recreate the
# per-monitor Polybars.

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

# Keep dunst 1.9's numeric monitor index in sync.
DUNST_START="${I3_DUNST_START:-$DIR/dunst-start.sh}"
if [ -x "$DUNST_START" ]; then
    "$DUNST_START" --sync || true
fi

"$DIR/wallpaper.sh"

POLYBAR_LAUNCHER="${I3_POLYBAR_LAUNCHER:-$DIR/../polybar/launch.sh}"
if [ -x "$POLYBAR_LAUNCHER" ]; then
    "$POLYBAR_LAUNCHER"
fi

# Confirm the completed setup once launch.sh has the bars back. The stamp lives
# in XDG_RUNTIME_DIR, so its absence marks a login's first parse.
TOAST_STAMP="${XDG_RUNTIME_DIR:-/tmp}/i3-reload-toast"
TOAST_TEXT="${I3_DISPLAY_TOAST:-}"
if [ "${I3_RELOAD_TOAST:-0}" = 1 ]; then
    if [ -z "$TOAST_TEXT" ]; then
        if [ -e "$TOAST_STAMP" ]; then
            TOAST_TEXT="i3 reloaded"
        else
            TOAST_TEXT="Welcome"
        fi
    fi
    touch "$TOAST_STAMP"
fi

if [ -n "$TOAST_TEXT" ] && command -v rofi >/dev/null 2>&1; then
    # rofi 1.7.5 ignores a `timeout` block in -e mode, so time it out here.
    rofi -e "$TOAST_TEXT" -theme reload-toast &
    toast_pid=$!
    sleep 1
    kill "$toast_pid" 2>/dev/null || true
    wait "$toast_pid" 2>/dev/null || true
fi
