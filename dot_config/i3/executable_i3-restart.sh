#!/bin/sh
# Validate the candidate config before replacing the running i3 instance.

set -u

config=${I3_RESTART_CONFIG:-$HOME/.config/i3/config}

report_failure() {
    title=$1
    detail=$2

    printf '%s: %s\n' "$title" "$detail" >&2
    if command -v notify-send >/dev/null 2>&1 &&
        notify-send -u critical "$title" "$detail"; then
        return
    fi
    if command -v i3-nagbar >/dev/null 2>&1; then
        i3-nagbar -t error -m "$title: $detail" >/dev/null 2>&1 &
    fi
}

if check_output=$(i3 -C -c "$config" 2>&1); then
    :
else
    [ -z "$check_output" ] || printf '%s\n' "$check_output" >&2
    report_failure "i3 restart blocked" \
        "Config validation failed; run i3 -C -c ~/.config/i3/config for details."
    exit 1
fi

if restart_output=$(i3-msg restart 2>&1); then
    exit 0
fi

[ -z "$restart_output" ] || printf '%s\n' "$restart_output" >&2
report_failure "i3 restart failed" "The validated config was not activated."
exit 1
