#!/usr/bin/env bash

TOAST_WRAP="${I3_TOAST_WRAP:-27}"

wrap_toast() {
    local -a words=()
    local word line="" out=""

    read -r -a words <<<"$1"
    for word in ${words[@]+"${words[@]}"}; do
        while [ "${#word}" -gt "$TOAST_WRAP" ]; do
            [ -n "$line" ] && { out="$out$line"$'\n'; line=""; }
            out="$out${word:0:TOAST_WRAP}"$'\n'
            word="${word:TOAST_WRAP}"
        done
        [ -n "$word" ] || continue

        if [ -z "$line" ]; then
            line="$word"
        elif [ "$((${#line} + 1 + ${#word}))" -le "$TOAST_WRAP" ]; then
            line="$line $word"
        else
            out="$out$line"$'\n'
            line="$word"
        fi
    done

    printf '%s%s' "$out" "$line"
}

show_toast() {
    [ -n "${1:-}" ] || return 0
    command -v rofi >/dev/null 2>&1 || return 0

    rofi -e "$(wrap_toast "$1")" -theme reload-toast \
        -m "${I3_TOAST_MONITOR:-primary}" &
    local toast_pid=$!
    sleep "${I3_TOAST_SECONDS:-1}"
    kill "$toast_pid" 2>/dev/null || true
    wait "$toast_pid" 2>/dev/null || true
}
