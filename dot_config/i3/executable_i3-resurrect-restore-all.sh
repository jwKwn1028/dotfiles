#!/usr/bin/env bash
# Restore every saved i3 workspace layout, then the windows that filled it.
#
# "workspace N output ..." only applies when i3 creates a workspace, so
# external-assigned workspaces are forced over before the layouts are rebuilt.

set -euo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"
. "$DIR/_resurrect-common.sh"

STATE_DIR="${I3_RESURRECT_STATE_DIR:-$HOME/.config/i3/resurrect}"
META_DIR="${I3_RESURRECT_META_DIR:-$HOME/.config/i3/resurrect-meta}"
LAYOUT_DELAY="${I3_RESURRECT_LAYOUT_DELAY:-0.25}"
KILL_WAIT_ATTEMPTS="${I3_RESURRECT_KILL_WAIT_ATTEMPTS:-40}"
KILL_POLL_INTERVAL="${I3_RESURRECT_KILL_POLL_INTERVAL:-0.25}"
PLACEHOLDER_WAIT_ATTEMPTS="${I3_RESURRECT_WAIT_ATTEMPTS:-48}"
PLACEHOLDER_POLL_INTERVAL="${I3_RESURRECT_POLL_INTERVAL:-0.25}"
resurrect_paths
REMOTE_HELPERS="${I3_RESURRECT_REMOTE_HELPERS:-$HOME/.zsh/rc.d/50-remote.zsh}"
LABROUTE_TIMEOUT="${I3_RESURRECT_LABROUTE_TIMEOUT:-45}"
LAPTOP_OUTPUT="${I3_LAPTOP_OUTPUT:-eDP}"
EXTERNAL_WORKSPACES="${I3_RESURRECT_EXTERNAL_WORKSPACES:-3 4 5 6 7 8 9 10}"
POLYBAR_WAS_VISIBLE=0
LABROUTE_ERROR=""

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "i3-resurrect" "$1" || true
    fi
}

find_i3_resurrect() {
    if [ -n "${I3_RESURRECT:-}" ]; then
        command -v "$I3_RESURRECT"
    elif command -v i3-resurrect >/dev/null 2>&1; then
        command -v i3-resurrect
    elif [ -x "$HOME/.local/bin/i3-resurrect" ]; then
        printf '%s\n' "$HOME/.local/bin/i3-resurrect"
    else
        printf 'i3-resurrect not found\n' >&2
        exit 127
    fi
}

window_ids() {
    i3-msg -t get_tree | jq -r '.. | objects | select(.window? != null) | .id'
}

active_external_output() {
    i3-msg -t get_outputs | jq -r --arg laptop "$LAPTOP_OUTPUT" '
        [.[] | select(.active and .name != $laptop)][0].name // empty
    '
}

workspace_wants_external() {
    local workspace="$1"
    local candidate

    for candidate in $EXTERNAL_WORKSPACES; do
        if [ "$workspace" = "$candidate" ]; then
            return 0
        fi
    done
    return 1
}

hide_polybar_for_restore() {
    if polybar_visible; then
        POLYBAR_WAS_VISIBLE=1
        polybar_set_state hide 0 || true
        polybar_wait_for_state 0 2000 >/dev/null || true
    fi
}

restore_polybar_after_restore() {
    if [ "$POLYBAR_WAS_VISIBLE" = 1 ]; then
        polybar_set_state show 1 || true
        if polybar_wait_for_state 1 2000 >/dev/null; then
            polybar_raise
        fi
    fi
    return 0
}

kill_existing_windows() {
    local attempts="$KILL_WAIT_ATTEMPTS"
    local ids
    local id

    while [ "$attempts" -gt 0 ]; do
        ids="$(window_ids)" || return 1
        if [ -z "$ids" ]; then
            return 0
        fi

        while IFS= read -r id; do
            [ -n "$id" ] || continue
            i3-msg "[con_id=$id] kill" >/dev/null || true
        done <<< "$ids"

        sleep "$KILL_POLL_INTERVAL"
        attempts=$((attempts - 1))
    done

    ids="$(window_ids)" || return 1
    [ -n "$ids" ] || return 0
    printf 'Timed out waiting for existing window(s) to close before restore.\n' >&2
    [ -z "$ids" ] || printf 'Remaining container ids:\n%s\n' "$ids" >&2
    return 1
}

wait_for_workspace() {
    local workspace="$1"
    local attempts="$PLACEHOLDER_WAIT_ATTEMPTS"
    local reason="workspace was not checked"

    while [ "$attempts" -gt 0 ]; do
        if reason="$(i3-msg -t get_tree | resurrect_state ready "$STATE_DIR" "$META_DIR" "$workspace" 2>&1)"; then
            return 0
        fi
        sleep "$PLACEHOLDER_POLL_INTERVAL"
        attempts=$((attempts - 1))
    done
    printf 'Workspace "%s": %s\n' "$workspace" "$reason"
    return 1
}

# Brings the saved lab route up before windows reattach; never turns it off.
restore_labroute() {
    local output
    local status=0

    [ "$(head -n 1 "$LABROUTE_FILE" 2>/dev/null)" = on ] || return 0

    output="$(
        timeout --kill-after=2 "$LABROUTE_TIMEOUT" zsh -fc 'source "$1" && labroute on' \
            zsh "$REMOTE_HELPERS" 9>&- 2>&1
    )" || status="$?"
    [ "$status" -ne 0 ] || return 0

    if [ "$status" -eq 124 ]; then
        LABROUTE_ERROR="labroute on timed out after ${LABROUTE_TIMEOUT}s"
    else
        LABROUTE_ERROR="$(printf '%s\n' "$output" | sed '/^[[:space:]]*$/d' | tail -n 1)"
        LABROUTE_ERROR="${LABROUTE_ERROR:-labroute on failed}"
    fi
    printf 'Lab route not restored: %s\n' "$LABROUTE_ERROR" >&2
    return 1
}

# Preserve i3's command grammar when workspace/output names contain quotes.
i3_string() {
    jq -Rn --arg value "$1" '$value'
}

i3_command() {
    i3-msg "$1" | jq -e 'type == "array" and length > 0 and all(.[]; .success == true)' >/dev/null
}

CHECK=0
PREVIOUS=()
for argument in "$@"; do
    case "$argument" in
        --check) CHECK=1 ;;
        --previous) PREVIOUS=(--previous) ;;
        *) printf 'Usage: %s [--check] [--previous]\n' "$0" >&2; exit 2 ;;
    esac
done
resurrect_dependencies
I3_RESURRECT="$(find_i3_resurrect)"
for attempts in "$KILL_WAIT_ATTEMPTS" "$PLACEHOLDER_WAIT_ATTEMPTS"; do
    if ! [[ "$attempts" =~ ^[1-9][0-9]*$ ]]; then
        printf 'Restore wait attempts must be positive integers.\n' >&2
        exit 1
    fi
done
for interval in "$KILL_POLL_INTERVAL" "$PLACEHOLDER_POLL_INTERVAL" "$LAYOUT_DELAY" "$LABROUTE_TIMEOUT"; do
    if ! [[ "$interval" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        printf 'Restore delays must be nonnegative numbers of seconds.\n' >&2
        exit 1
    fi
done
if [[ "$LABROUTE_TIMEOUT" =~ ^0+([.]0+)?$ ]]; then
    printf 'The lab route timeout must be greater than zero.\n' >&2
    exit 1
fi

umask 077
if [ "$CHECK" = 0 ]; then
    resurrect_lock || exit 1
fi
PROFILE_META_DIR="$META_DIR"
if ! resolved="$(resurrect_state resolve "$STATE_DIR" "$META_DIR" "${PREVIOUS[@]}")"; then
    notify 'Restore aborted; invalid snapshot manifest.'
    exit 1
fi
STATE_DIR="$(jq -r '.[0]' <<< "$resolved")"
META_DIR="$(jq -r '.[1]' <<< "$resolved")"
resurrect_paths
if ! resurrect_state validate "$STATE_DIR" "$META_DIR"; then
    notify 'Restore aborted; snapshot validation failed. Existing windows are unchanged.'
    exit 1
fi
if [ "$(cat "$LABROUTE_FILE" 2>/dev/null)" = on ]; then
    command -v timeout >/dev/null
    command -v zsh >/dev/null
    test -r "$REMOTE_HELPERS"
fi
[ "$CHECK" = 0 ] || exit 0

# Routing must succeed before replacing the desktop, not just before launching.
if ! restore_labroute; then
    notify "Restore aborted; existing windows are unchanged."$'\n'"Lab route not restored: $LABROUTE_ERROR"
    exit 1
fi

trap restore_polybar_after_restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
hide_polybar_for_restore
if ! kill_existing_windows; then
    notify 'Restore aborted; existing windows are still open or i3 is unavailable.'
    exit 1
fi

failed=0
results='[]'
record_result() {
    local workspace="$1" status="$2" detail="${3:-}"
    results="$(jq --arg workspace "$workspace" --arg status "$status" --arg detail "$detail" \
        '. + [{workspace: $workspace, status: $status, detail: $detail}]' <<< "$results")"
    if [ "$status" != ready ]; then
        failed=1
        printf 'Workspace "%s": %s\n' "$workspace" "$detail" >&2
    fi
}

EXTERNAL_OUTPUT="$(active_external_output || true)"
while IFS= read -r workspace || [ -n "$workspace" ]; do
    if ! i3_command "workspace --no-auto-back-and-forth $(i3_string "$workspace")"; then
        record_result "$workspace" failed 'could not select workspace'
        continue
    fi
    if [ -n "$EXTERNAL_OUTPUT" ] && workspace_wants_external "$workspace"; then
        if ! i3_command "move workspace to output $(i3_string "$EXTERNAL_OUTPUT")"; then
            record_result "$workspace" failed 'could not move workspace to saved output policy'
            continue
        fi
    fi
    if ! detail="$("$I3_RESURRECT" restore -w "$workspace" -d "$STATE_DIR" --layout-only 9>&- 2>&1)"; then
        record_result "$workspace" failed "layout restore failed: $detail"
        continue
    fi
    sleep "$LAYOUT_DELAY"
    if ! detail="$("$I3_RESURRECT" restore -w "$workspace" -d "$STATE_DIR" --programs-only 9>&- 2>&1)"; then
        record_result "$workspace" failed "program launch failed: $detail"
        continue
    fi
    if detail="$(wait_for_workspace "$workspace")"; then
        record_result "$workspace" ready
    else
        record_result "$workspace" failed "$detail"
    fi
done < "$WORKSPACES_FILE"

# Recheck all successful workspaces: windows may close or move during later restores.
while IFS= read -r workspace || [ -n "$workspace" ]; do
    if ! detail="$(i3-msg -t get_tree | resurrect_state ready "$STATE_DIR" "$META_DIR" "$workspace" 2>&1)"; then
        results="$(jq --arg workspace "$workspace" --arg detail "$detail" \
            'map(if .workspace == $workspace then .status = "failed" | .detail = $detail else . end)' <<< "$results")"
        failed=1
    fi
done < <(jq -r '.[] | select(.status == "ready") | .workspace' <<< "$results")

if [ -s "$FOCUSED_FILE" ]; then
    focused_workspace="$(head -n 1 "$FOCUSED_FILE")"
    if [ -n "$focused_workspace" ] && ! i3_command "workspace --no-auto-back-and-forth $(i3_string "$focused_workspace")"; then
        failed=1
        results="$(jq '. + [{workspace: "(focus)", status: "failed", detail: "could not restore focus"}]' <<< "$results")"
    fi
fi

if [ "$failed" -eq 0 ]; then
    summary='Restore complete.'
else
    summary='Restore finished with errors.'$'\n'"$(jq -r '.[] | select(.status != "ready") | "Workspace \(.workspace): \(.detail)"' <<< "$results")"
fi
completed="$(jq '[.[] | select(.status == "ready") | .workspace]' <<< "$results")"
reattach="$(resurrect_state sessions "$STATE_DIR" "$META_DIR" "$completed")"
if [ -n "$reattach" ]; then
    summary="$summary"$'\n'"$reattach"
fi
# Reports stay outside immutable generations; URLs and paths remain local.
report="$(mktemp "$PROFILE_META_DIR/.restore-report.XXXXXXXX")"
jq -n --arg snapshot "$STATE_DIR" --argjson workspaces "$results" --arg sessions "$reattach" \
    '{snapshot: $snapshot, workspaces: $workspaces, sessions: $sessions}' > "$report"
mv -- "$report" "$PROFILE_META_DIR/last-restore.json"
notify "$summary"
exit "$failed"
