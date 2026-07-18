#!/usr/bin/env bash

set -u

LAPTOP_OUTPUT="${I3_LAPTOP_OUTPUT:-eDP}"
workspace="${1:-}"

external_output_is_active() {
    command -v xrandr >/dev/null 2>&1 || return 1

    xrandr --query | awk -v laptop="$LAPTOP_OUTPUT" '
        $2 == "connected" &&
        $1 != laptop &&
        $3 ~ /^[0-9]+x[0-9]+\+/ {
            found = 1
        }
        END {
            exit !found
        }
    '
}

case "$workspace" in
    1|2|3|4|5|6)
        ;;
    7|8|9|10)
        external_output_is_active || exit 0
        ;;
    *)
        exit 2
        ;;
esac

i3-msg "move container to workspace number $workspace; workspace number $workspace" >/dev/null
