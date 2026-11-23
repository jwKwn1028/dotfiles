#!/usr/bin/env bash
# Bring a saved lab route up in the background; remote windows wait on the lock.
set -uo pipefail

helpers="${I3_RESURRECT_REMOTE_HELPERS:-$HOME/.zsh/rc.d/50-remote.zsh}"
limit="${I3_RESURRECT_LABROUTE_TIMEOUT:-45}"
lock="${XDG_RUNTIME_DIR:-/tmp}/i3-resurrect-labroute.lock"
mode="${TAILSCALE_REMOTE_MODE_FILE:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tailscale-remote-proxy-required}"

exec 3>>"$lock" && flock -n 3 || exit 0
# Block direct SSH now; labroute on marks this late.
: >>"$mode" 2>/dev/null

(
    status=0
    output="$(timeout --kill-after=2 "$limit" zsh -fc 'source "$1" && labroute on' zsh "$helpers" 2>&1 3>&-)" ||
        status=$?
    [ "$status" -ne 0 ] || exit 0
    if [ "$status" -eq 124 ]; then
        reason="labroute on timed out after ${limit}s"
    else
        reason="$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)"
    fi
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "i3-resurrect" "Lab route not restored: ${reason:-labroute on failed}" 3>&-
    fi
) </dev/null >/dev/null 2>&1 &
