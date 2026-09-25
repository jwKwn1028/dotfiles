#!/usr/bin/env bash
# Restore every saved i3 workspace layout, then the windows that filled it.
#
# "workspace N output ..." only applies when i3 creates a workspace, so
# external-assigned workspaces are forced over before the layouts are rebuilt.

set -euo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

STATE_DIR="${I3_RESURRECT_STATE_DIR:-$HOME/.config/i3/resurrect}"
META_DIR="${I3_RESURRECT_META_DIR:-$HOME/.config/i3/resurrect-meta}"
LAYOUT_DELAY="${I3_RESURRECT_LAYOUT_DELAY:-0.25}"
KILL_WAIT_ATTEMPTS="${I3_RESURRECT_KILL_WAIT_ATTEMPTS:-40}"
KILL_POLL_INTERVAL="${I3_RESURRECT_KILL_POLL_INTERVAL:-0.25}"
PLACEHOLDER_WAIT_ATTEMPTS="${I3_RESURRECT_WAIT_ATTEMPTS:-48}"
PLACEHOLDER_POLL_INTERVAL="${I3_RESURRECT_POLL_INTERVAL:-0.25}"
WORKSPACES_FILE="$META_DIR/workspaces.txt"
FOCUSED_FILE="$META_DIR/focused-workspace.txt"
LABROUTE_FILE="$META_DIR/labroute.txt"
GHOSTTY_SESSIONS_FILE="$META_DIR/ghostty-sessions.json"
REMOTE_HELPERS="${I3_RESURRECT_REMOTE_HELPERS:-$HOME/.zsh/rc.d/50-remote.zsh}"
LABROUTE_TIMEOUT="${I3_RESURRECT_LABROUTE_TIMEOUT:-45}"
LAPTOP_OUTPUT="${I3_LAPTOP_OUTPUT:-eDP}"
EXTERNAL_WORKSPACES="${I3_RESURRECT_EXTERNAL_WORKSPACES:-3 4 5 6 7 8 9 10}"
POLYBAR_WAS_VISIBLE=0
LABROUTE_ERROR=""

notify() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send "i3-resurrect" "$1"
    fi
}

find_i3_resurrect() {
    if [ -n "${I3_RESURRECT:-}" ]; then
        printf '%s\n' "$I3_RESURRECT"
    elif command -v i3-resurrect >/dev/null 2>&1; then
        command -v i3-resurrect
    elif [ -x "$HOME/.local/bin/i3-resurrect" ]; then
        printf '%s\n' "$HOME/.local/bin/i3-resurrect"
    else
        printf 'i3-resurrect not found\n' >&2
        exit 127
    fi
}

workspace_file_id() {
    printf '%s' "$1" | tr -d '/\\:*"<>|'
}

programs_file_for_workspace() {
    local workspace="$1"
    local workspace_id

    workspace_id="$(workspace_file_id "$workspace")"
    printf '%s/workspace_%s_programs.json\n' "$STATE_DIR" "$workspace_id"
}

saved_program_count() {
    local programs_file="$1"

    if [ ! -s "$programs_file" ]; then
        printf '0\n'
        return 0
    fi

    jq 'length' "$programs_file"
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
        ids="$(window_ids)"
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

    ids="$(window_ids 2>/dev/null || true)"
    printf 'Timed out waiting for existing window(s) to close before restore.\n' >&2
    [ -z "$ids" ] || printf 'Remaining container ids:\n%s\n' "$ids" >&2
    return 1
}

placeholder_count() {
    local workspace="$1"

    i3-msg -t get_tree | jq --arg workspace "$workspace" '
        ([.. | objects | select(.type? == "workspace" and .name? == $workspace)][0] // {})
        | [.. | objects | select(((.swallows? // []) | length) > 0)]
        | length
    '
}

wait_for_placeholders() {
    local workspace="$1"
    local attempts="$PLACEHOLDER_WAIT_ATTEMPTS"
    local count

    while [ "$attempts" -gt 0 ]; do
        count="$(placeholder_count "$workspace" 2>/dev/null || true)"
        if [ "$count" = "0" ]; then
            return 0
        fi
        if [ -z "$count" ]; then
            return 1
        fi

        sleep "$PLACEHOLDER_POLL_INTERVAL"
        attempts=$((attempts - 1))
    done

    printf 'Timed out waiting for %s placeholder(s) on workspace "%s".\n' "$count" "$workspace" >&2
    return 1
}

# Brings the saved lab route up before windows reattach; never turns it off.
restore_labroute() {
    local output
    local status=0

    [ "$(head -n 1 "$LABROUTE_FILE" 2>/dev/null)" = on ] || return 0

    output="$(
        timeout "$LABROUTE_TIMEOUT" zsh -fc 'source "$1" && labroute on' \
            zsh "$REMOTE_HELPERS" 2>&1
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

# Saved sessions no restored window reattaches: other splits, unpaired windows.
unattached_sessions() {
    local workspace index kind name
    local -a found=()

    [ -s "$GHOSTTY_SESSIONS_FILE" ] || return 0
    while IFS=$'\t' read -r workspace index kind name; do
        grep -Fqx -- "$workspace" "$WORKSPACES_FILE" || continue
        if [ "$index" = 0 ] && grep -Fq -- \
            "I3_RESURRECT_REMOTE_SESSION=$kind:$name " \
            "$(programs_file_for_workspace "$workspace")" 2>/dev/null; then
            continue
        fi
        case "$kind" in
            tmux) found+=("hpc $name") ;;
            zmx) found+=("hpcz $name") ;;
        esac
    done < <(
        jq -r '.[] | .workspace as $workspace | (.sessions // []) | to_entries[] |
            [$workspace, .key, .value.kind, .value.name] | map(tostring) | @tsv' \
            "$GHOSTTY_SESSIONS_FILE" 2>/dev/null
    )

    [ "${#found[@]}" -gt 0 ] || return 0
    printf '%s\n' "${found[@]}" | awk '!seen[$0]++' | paste -sd ',' - | sed 's/,/, /g'
}

if [ "${1:-}" = "--check" ]; then
    command -v i3-msg >/dev/null
    command -v jq >/dev/null
    find_i3_resurrect >/dev/null
    test -s "$WORKSPACES_FILE"
    exit 0
fi

I3_RESURRECT="$(find_i3_resurrect)"
trap restore_polybar_after_restore EXIT

if [ ! -s "$WORKSPACES_FILE" ]; then
    notify "No saved workspace list found."
    printf 'No saved workspace list found: %s\n' "$WORKSPACES_FILE" >&2
    exit 1
fi

hide_polybar_for_restore

if ! kill_existing_windows; then
    notify "Restore aborted; existing windows are still open."
    exit 1
fi

failed=0

if ! restore_labroute; then
    failed=1
fi

EXTERNAL_OUTPUT="$(active_external_output || true)"

while IFS= read -r workspace; do
    [ -n "$workspace" ] || continue
    programs_file="$(programs_file_for_workspace "$workspace")"
    programs_to_restore="$(saved_program_count "$programs_file")"

    i3-msg "workspace \"$workspace\"" >/dev/null
    if [ -n "$EXTERNAL_OUTPUT" ] && workspace_wants_external "$workspace"; then
        i3-msg "move workspace to output \"$EXTERNAL_OUTPUT\"" >/dev/null || true
    fi
    if ! "$I3_RESURRECT" restore -w "$workspace" -d "$STATE_DIR" --layout-only; then
        failed=1
        continue
    fi

    sleep "$LAYOUT_DELAY"

    if ! "$I3_RESURRECT" restore -w "$workspace" -d "$STATE_DIR" --programs-only; then
        failed=1
        continue
    fi

    if [ "$programs_to_restore" -gt 0 ] && ! wait_for_placeholders "$workspace"; then
        failed=1
    fi
done < "$WORKSPACES_FILE"

if [ -s "$FOCUSED_FILE" ]; then
    focused_workspace="$(head -n 1 "$FOCUSED_FILE")"
    if [ -n "$focused_workspace" ]; then
        i3-msg "workspace \"$focused_workspace\"" >/dev/null
    fi
fi

if [ "$failed" -eq 0 ]; then
    summary="Restore complete."
else
    summary="Restore finished with errors."
fi
if [ -n "$LABROUTE_ERROR" ]; then
    summary="$summary"$'\n'"Lab route not restored: $LABROUTE_ERROR"
fi
reattach="$(unattached_sessions || true)"
if [ -n "$reattach" ]; then
    summary="$summary"$'\n'"Reattach by hand: $reattach"
fi
notify "$summary"

exit "$failed"
