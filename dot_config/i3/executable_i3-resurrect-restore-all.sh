#!/usr/bin/env bash
# Restore a snapshot into one captured workspace group.

set -euo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"
. "$DIR/_resurrect-common.sh"

STATE_DIR="${I3_RESURRECT_STATE_DIR:-$HOME/.config/i3/resurrect}"
META_DIR="${I3_RESURRECT_META_DIR:-$HOME/.config/i3/resurrect-meta}"
LAYOUT_DELAY="${I3_RESURRECT_LAYOUT_DELAY:-0.25}"
PLACEHOLDER_WAIT_ATTEMPTS="${I3_RESURRECT_WAIT_ATTEMPTS:-48}"
PLACEHOLDER_POLL_INTERVAL="${I3_RESURRECT_POLL_INTERVAL:-0.25}"
resurrect_paths
REMOTE_HELPERS="${I3_RESURRECT_REMOTE_HELPERS:-$HOME/.zsh/rc.d/50-remote.zsh}"
LABROUTE_TIMEOUT="${I3_RESURRECT_LABROUTE_TIMEOUT:-45}"
POLYBAR_WAS_VISIBLE=0
RESTORE_OPERATION=""
RESTORE_LEASE=0
LABROUTE_ERROR=""

notify() {
    [ "${I3_RESURRECT_QUIET:-0}" != 1 ] || return 0
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
        return 1
    fi
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

cleanup_restore() {
    if [ "$RESTORE_LEASE" = 1 ]; then
        jq -n --arg token "$RESTORE_OPERATION" '{action:"restore-end", token:$token}' | resurrect_group >/dev/null || true
    fi
    restore_polybar_after_restore
    [ -z "$RESTORE_STATE_DIR" ] || rm -rf -- "$RESTORE_STATE_DIR"
}

restore_active() {
    jq -n --arg token "$RESTORE_OPERATION" '{action:"restore-status",token:$token}' | resurrect_group >/dev/null 2>&1
}

wait_for_workspace() {
    local workspace="$1"
    local attempts="$PLACEHOLDER_WAIT_ATTEMPTS"
    local reason="workspace was not checked"

    while [ "$attempts" -gt 0 ]; do
        restore_active || { printf "Restore cancelled.\n"; return 1; }
        if reason="$(i3-msg -t get_tree | resurrect_state ready "$RESTORE_STATE_DIR" "$META_DIR" "$workspace" 2>&1)"; then
            if reason="$(jq -n --arg token "$RESTORE_OPERATION" --arg workspace "$workspace" \
                '{action:"restore-ready",token:$token,workspace:$workspace}' | resurrect_group 2>&1)"; then
                return 0
            fi
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

CHECK=0
PREVIOUS=()
for argument in "$@"; do
    case "$argument" in
        --check) CHECK=1 ;;
        --previous) PREVIOUS=(--previous) ;;
        --group=*) I3_RESURRECT_GROUP="${argument#--group=}" ;;
        *) printf 'Usage: %s [--check] [--previous] [--group=A]\n' "$0" >&2; exit 2 ;;
    esac
done
missing="$(resurrect_dependencies)" || resurrect_fail "Restore unavailable: $missing not found."
I3_RESURRECT="$(find_i3_resurrect)" || resurrect_fail 'Restore unavailable: i3-resurrect not found.'
if ! [[ "$PLACEHOLDER_WAIT_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
    resurrect_fail 'Restore wait attempts must be positive integers.'
fi
for interval in "$PLACEHOLDER_POLL_INTERVAL" "$LAYOUT_DELAY" "$LABROUTE_TIMEOUT"; do
    if ! [[ "$interval" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        resurrect_fail 'Restore delays must be nonnegative numbers of seconds.'
    fi
done
if [[ "$LABROUTE_TIMEOUT" =~ ^0+([.]0+)?$ ]]; then
    resurrect_fail 'The lab route timeout must be greater than zero.'
fi

DESTINATION_GROUP="$(resurrect_selected_group)" || resurrect_fail "Cannot determine the destination group."
RESTORE_OPERATION="$("$RESURRECT_PYTHON" -c 'import uuid; print(uuid.uuid4().hex)')"
umask 077
if [ "$CHECK" = 0 ]; then
    resurrect_lock || exit 1
fi
PROFILE_META_DIR="${I3_RESURRECT_REPORT_DIR:-$META_DIR}"
if ! resolved="$(resurrect_state resolve "$STATE_DIR" "$META_DIR" "${PREVIOUS[@]}" 2>&1)"; then
    resurrect_fail 'Restore aborted; invalid snapshot manifest.'$'\n'"$resolved"
fi
STATE_DIR="$(jq -r '.[0]' <<< "$resolved")"
META_DIR="$(jq -r '.[1]' <<< "$resolved")"
resurrect_paths
if ! detail="$(resurrect_state validate "$STATE_DIR" "$META_DIR" 2>&1)" ||
    ! detail="$(resurrect_state occupied "$STATE_DIR" "$META_DIR" 2>&1 >/dev/null)"; then
    resurrect_fail 'Restore aborted; snapshot validation failed. Existing windows are unchanged.'$'\n'"$detail"
fi
if [ "$(cat "$LABROUTE_FILE" 2>/dev/null)" = on ]; then
    for command in timeout zsh; do
        command -v "$command" >/dev/null ||
            resurrect_fail "Restore unavailable: $command not found for the lab route."
    done
    [ -r "$REMOTE_HELPERS" ] || resurrect_fail "Restore unavailable: cannot read $REMOTE_HELPERS."
fi
RESTORE_STATE_DIR=""
trap cleanup_restore EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
RESTORE_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/i3-resurrect-restore.XXXXXXXX")"
if ! RESTORE_PLAN="$(i3-msg -t get_tree | resurrect_state prepare-restore \
    "$STATE_DIR" "$META_DIR" "$RESTORE_STATE_DIR" --group "$DESTINATION_GROUP" --operation "$RESTORE_OPERATION" 2>"$RESTORE_STATE_DIR/plan-error")"; then
    resurrect_fail 'Restore aborted; could not plan workspace placement. Existing windows are unchanged.'$'\n'"$(cat "$RESTORE_STATE_DIR/plan-error")"
fi
MERGE_WORKSPACES="$(jq '[.[] | select(.merging) | .workspace]' <<< "$RESTORE_PLAN")"
UNLAID_WORKSPACES="$(jq '[.[] | select(.layout == false) | .workspace]' <<< "$RESTORE_PLAN")"
if [ "$CHECK" = 1 ]; then
    printf 'Destination group %s: %s\n' "$DESTINATION_GROUP" "$RESTORE_PLAN"
    exit 0
fi
# Routing must succeed before changing the desktop, not just before launching.
if ! restore_labroute; then
    notify "Restore aborted; existing windows are unchanged."$'\n'"Lab route not restored: $LABROUTE_ERROR"
    exit 1
fi
owner="$("$RESURRECT_PYTHON" -c 'import sys; from pathlib import Path; text=Path("/proc/"+sys.argv[1]+"/stat").read_text(); print(text[text.rfind(")")+2:].split()[19])' "$$")"
jq -n --arg token "$RESTORE_OPERATION" --arg group "$DESTINATION_GROUP" --argjson pid "$$" --arg start "$owner" \
    --arg session "${I3_RESURRECT_SESSION_TOKEN:-}" \
    '{action:"restore-begin",token:$token,group:$group,owner:[$pid,$start]} +
     (if $session == "" then {} else {session:$session} end)' | resurrect_group >/dev/null
RESTORE_LEASE=1
hide_polybar_for_restore

failed=0
results='[]'
record_result() {
    local workspace="$1" status="$2" detail="${3:-}"
    local source_workspace
    source_workspace="$(jq -r --arg workspace "$workspace" \
        '.[] | select(.workspace == $workspace) | .source_workspace' <<< "$RESTORE_PLAN")"
    results="$(jq --arg workspace "$workspace" --arg status "$status" --arg detail "$detail" \
        --arg source "$source_workspace" \
        '. + [{source_workspace: $source, workspace: $workspace, status: $status, detail: $detail}]' <<< "$results")"
    if [ "$status" != ready ]; then
        failed=1
        printf 'Workspace "%s": %s\n' "$workspace" "$detail" >&2
    fi
}

while IFS= read -r workspace || [ -n "$workspace" ]; do
    if ! restore_active; then
        record_result "$workspace" failed 'restore cancelled'
        break
    fi
    merging="$(jq -r --arg workspace "$workspace" '.[] | select(.workspace == $workspace) | .merging' <<< "$RESTORE_PLAN")"
    if [ "$merging" = false ] && ! i3-msg -t get_tree | jq -e --arg workspace "$workspace" '
        [.. | objects | select(.type? == "workspace" and .name == $workspace)
         | .. | objects | select(.window? != null)] | length == 0
    ' >/dev/null; then
        record_result "$workspace" failed 'destination became occupied or i3 is unavailable'
        continue
    fi
    layout="$RESTORE_STATE_DIR/workspace_$(workspace_file_id "$workspace")_layout.json"
    programs="$RESTORE_STATE_DIR/workspace_$(workspace_file_id "$workspace")_programs.json"
    if ! jq -e 'length > 0' "$programs" >/dev/null; then
        record_result "$workspace" failed 'no launchable programs were saved'
        continue
    fi
    if ! detail="$(jq -n --arg token "$RESTORE_OPERATION" --arg workspace "$workspace" --arg path "$layout" \
        '{action:"restore-layout",token:$token,workspace:$workspace,path:$path}' | resurrect_group 2>&1)"; then
        record_result "$workspace" failed "layout restore failed: $detail"
        continue
    fi
    sleep "$LAYOUT_DELAY"
    launch_error=""
    while IFS= read -r entry; do
        if ! detail="$(jq -n --arg token "$RESTORE_OPERATION" --arg workspace "$workspace" --argjson entry "$entry" \
            '{action:"restore-launch",token:$token,workspace:$workspace,entry:$entry}' | resurrect_group 2>&1)"; then
            launch_error="${launch_error:-program launch failed: $detail}"
        fi
    done < <(jq -c '.[]' "$programs")
    if [ -n "$launch_error" ]; then
        record_result "$workspace" failed "$launch_error"
        continue
    fi
    if detail="$(wait_for_workspace "$workspace")"; then
        record_result "$workspace" ready
    else
        record_result "$workspace" failed "$detail"
    fi
done < <(jq -r '.[].workspace' <<< "$RESTORE_PLAN")

# Recheck all successful workspaces: windows may close or move during later restores.
while IFS= read -r workspace || [ -n "$workspace" ]; do
    if ! detail="$(i3-msg -t get_tree | resurrect_state ready "$RESTORE_STATE_DIR" "$META_DIR" "$workspace" 2>&1)" ||
        ! detail="$(jq -n --arg token "$RESTORE_OPERATION" --arg workspace "$workspace" \
            '{action:"restore-ready",token:$token,workspace:$workspace}' | resurrect_group 2>&1)"; then
        results="$(jq --arg workspace "$workspace" --arg detail "$detail" \
            'map(if .workspace == $workspace then .status = "failed" | .detail = $detail else . end)' <<< "$results")"
        failed=1
    fi
done < <(jq -r '.[] | select(.status == "ready") | .workspace' <<< "$results")

if restore_active && [ -s "$FOCUSED_FILE" ]; then
    focused_workspace="$(jq -r --arg source "$(head -n 1 "$FOCUSED_FILE")" \
        '.[] | select(.source_workspace == $source) | .workspace' <<< "$RESTORE_PLAN")"
    if [ -n "$focused_workspace" ] && ! jq -n --arg token "$RESTORE_OPERATION" --arg workspace "$focused_workspace" \
        '{action:"restore-focus",token:$token,workspace:$workspace}' | resurrect_group >/dev/null; then
        failed=1
        results="$(jq '. + [{workspace: "(focus)", status: "failed", detail: "could not restore focus"}]' <<< "$results")"
    fi
fi

if [ "$failed" -eq 0 ]; then
    summary='Restore complete.'
else
    summary='Restore finished with errors.'$'\n'"$(jq -r '.[] | select(.status != "ready") | "Workspace \(.workspace): \(.detail)"' <<< "$results")"
fi
placement="$(jq -r 'map("\(.source_workspace)→\(.workspace)") | join(", ")' <<< "$RESTORE_PLAN")"
if [ -n "$placement" ]; then
    summary="$summary"$'\n'"Group $DESTINATION_GROUP workspaces: $placement"
fi
if [ "$MERGE_WORKSPACES" != '[]' ]; then
    summary="$summary"$'\n'"Opened alongside existing windows: $(jq -r 'join(", ")' <<< "$MERGE_WORKSPACES")"
fi
if [ "$UNLAID_WORKSPACES" != '[]' ]; then
    summary="$summary"$'\n'"Opened without the saved layout: $(jq -r 'join(", ")' <<< "$UNLAID_WORKSPACES")"
fi
completed="$(jq '[.[] | select(.status == "ready") | .source_workspace]' <<< "$results")"
reattach="$(resurrect_state sessions "$STATE_DIR" "$META_DIR" "$completed")"
if [ -n "$reattach" ]; then
    summary="$summary"$'\n'"$reattach"
fi
# Reports stay outside immutable generations; URLs and paths remain local.
report="$(mktemp "$PROFILE_META_DIR/.restore-report.XXXXXXXX")"
jq -n --arg snapshot "$STATE_DIR" --argjson workspaces "$results" --arg sessions "$reattach" \
    --argjson mapping "$RESTORE_PLAN" \
    '{snapshot: $snapshot, mapping: $mapping, workspaces: $workspaces, sessions: $sessions}' > "$report"
mv -- "$report" "$PROFILE_META_DIR/last-restore.json"
notify "$summary"
exit "$failed"
