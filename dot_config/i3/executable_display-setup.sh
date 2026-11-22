#!/usr/bin/env bash

DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=_toast-common.sh
. "$DIR/_toast-common.sh"
PREFERRED_LAPTOP_OUTPUT="${I3_LAPTOP_OUTPUT:-eDP}"
lid_files=(/proc/acpi/button/lid/*/state)
LID_STATE="${I3_LID_STATE:-${lid_files[0]}}"

lid_closed() {
    local _label state=""
    [ -r "$LID_STATE" ] && read -r _label state <"$LID_STATE"
    [ "$state" = closed ]
}

connected_laptop_output() {
    xrandr --query | awk -v preferred="$PREFERRED_LAPTOP_OUTPUT" '
        $2 != "connected" { next }
        $1 == preferred { print $1; exact = 1; exit }
        internal == "" && $1 ~ /^(eDP|LVDS)/ { internal = $1 }
        END { if (!exact && internal != "") print internal }
    '
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

apply_external_only_layout() {
    local external_output="$1"

    xrandr \
        --output "$external_output" --primary --auto --pos 0x0 --rotate normal \
        --output "$LAPTOP_OUTPUT" --off
}

apply_laptop_only_layout() {
    xrandr \
        --output "$LAPTOP_OUTPUT" --primary --auto --pos 0x0 --rotate normal
}

sleep "${I3_DISPLAY_SETUP_DELAY:-1}"

if ! command -v xrandr >/dev/null 2>&1 || ! xrandr --query >/dev/null 2>&1; then
    exit 0
fi

LAPTOP_OUTPUT=""
for _ in $(seq 1 20); do
    LAPTOP_OUTPUT="$(connected_laptop_output)"
    [ -n "$LAPTOP_OUTPUT" ] && break
    sleep 0.25
done

if [ -n "$LAPTOP_OUTPUT" ]; then
    EXTERNAL_OUTPUT="$(connected_external_output)"

    if [ -n "$EXTERNAL_OUTPUT" ] && lid_closed; then
        apply_external_only_layout "$EXTERNAL_OUTPUT"
    elif [ -n "$EXTERNAL_OUTPUT" ]; then
        apply_two_monitor_layout "$EXTERNAL_OUTPUT"
    else
        apply_laptop_only_layout
    fi
fi

sleep 0.2

GROUP_ACTION="$DIR/workspace-action.sh"
if [ -x "$GROUP_ACTION" ]; then
    "$GROUP_ACTION" reconcile --quiet || true
fi

DUNST_START="${I3_DUNST_START:-$DIR/dunst-start.sh}"
if [ -x "$DUNST_START" ]; then
    "$DUNST_START" --sync || true
fi

"$DIR/wallpaper.sh" &

POLYBAR_LAUNCHER="${I3_POLYBAR_LAUNCHER:-$DIR/../polybar/launch.sh}"
if [ -x "$POLYBAR_LAUNCHER" ]; then
    "$POLYBAR_LAUNCHER"
fi

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

show_toast "$TOAST_TEXT"
