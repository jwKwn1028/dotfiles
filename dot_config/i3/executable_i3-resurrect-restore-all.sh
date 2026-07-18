#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="${I3_RESURRECT_STATE_DIR:-$HOME/.config/i3/resurrect}"
META_DIR="${I3_RESURRECT_META_DIR:-$HOME/.config/i3/resurrect-meta}"
LAYOUT_DELAY="${I3_RESURRECT_LAYOUT_DELAY:-0.25}"
KILL_WAIT_ATTEMPTS="${I3_RESURRECT_KILL_WAIT_ATTEMPTS:-40}"
KILL_POLL_INTERVAL="${I3_RESURRECT_KILL_POLL_INTERVAL:-0.25}"
PLACEHOLDER_WAIT_ATTEMPTS="${I3_RESURRECT_WAIT_ATTEMPTS:-48}"
PLACEHOLDER_POLL_INTERVAL="${I3_RESURRECT_POLL_INTERVAL:-0.25}"
WORKSPACES_FILE="$META_DIR/workspaces.txt"
FOCUSED_FILE="$META_DIR/focused-workspace.txt"
LAPTOP_OUTPUT="${I3_LAPTOP_OUTPUT:-eDP}"
EXTERNAL_WORKSPACES="${I3_RESURRECT_EXTERNAL_WORKSPACES:-7 8 9 10}"
POLYBAR_WAS_VISIBLE=0

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

polybar_windows() {
    command -v xdotool >/dev/null 2>&1 || return 0
    xdotool search --class '^[Pp]olybar$' 2>/dev/null || true
}

window_viewable() {
    command -v xwininfo >/dev/null 2>&1 || return 1
    xwininfo -id "$1" 2>/dev/null | grep -q 'IsViewable'
}

polybar_visible() {
    local win

    for win in $(polybar_windows); do
        window_viewable "$win" && return 0
    done
    return 1
}

wait_for_polybar_state() {
    local wanted="$1"
    local attempts=80

    while [ "$attempts" -gt 0 ]; do
        if [ "$wanted" = 1 ]; then
            polybar_visible && return 0
        else
            polybar_visible || return 0
        fi
        sleep 0.025
        attempts=$((attempts - 1))
    done

    return 0
}

set_polybar_visibility() {
    local wanted="$1"
    local cmd

    command -v polybar-msg >/dev/null 2>&1 || return 0
    if [ "$wanted" = 1 ]; then
        cmd=show
    else
        cmd=hide
    fi

    polybar-msg cmd "$cmd" >/dev/null 2>&1 || return 0
    wait_for_polybar_state "$wanted"
}

hide_polybar_for_restore() {
    if polybar_visible; then
        POLYBAR_WAS_VISIBLE=1
        set_polybar_visibility 0 || true
    fi
}

restore_polybar_after_restore() {
    if [ "$POLYBAR_WAS_VISIBLE" = 1 ]; then
        set_polybar_visibility 1 || true
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

# "workspace N output ..." directives in the i3 config only apply when i3
# creates a workspace, so a workspace saved on the laptop output stays there
# on restore. Force external-assigned workspaces over before rebuilding them.
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
    notify "Restore complete."
else
    notify "Restore finished with errors."
fi

exit "$failed"
