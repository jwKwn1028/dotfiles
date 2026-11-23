#!/usr/bin/env bash

set -euo pipefail

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"
. "$DIR/_resurrect-common.sh"

STATE_DIR="${I3_RESURRECT_STATE_DIR:-$HOME/.config/i3/resurrect}"
META_DIR="${I3_RESURRECT_META_DIR:-$HOME/.config/i3/resurrect-meta}"
PLACEHOLDER_WAIT_ATTEMPTS="${I3_RESURRECT_WAIT_ATTEMPTS:-120}"
PLACEHOLDER_POLL_INTERVAL="${I3_RESURRECT_POLL_INTERVAL:-0.25}"
resurrect_paths
REMOTE_HELPERS="${I3_RESURRECT_REMOTE_HELPERS:-$HOME/.zsh/rc.d/50-remote.zsh}"
LABROUTE_TIMEOUT="${I3_RESURRECT_LABROUTE_TIMEOUT:-45}"
TMUX_RESTORE="${I3_RESURRECT_TMUX_RESTORE-$HOME/.local/bin/tmux-restore-if-empty}"
LABROUTE_RESTORE="${I3_RESURRECT_LABROUTE_RESTORE:-$DIR/labroute-restore.sh}"
[ -r "$LABROUTE_RESTORE" ] || LABROUTE_RESTORE="$DIR/executable_labroute-restore.sh"
POLYBAR_WAS_VISIBLE=0
RESTORE_OPERATION=""
RESTORE_LEASE=0

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

# The session toggles the bar once for all groups.
hide_polybar_for_restore() {
    [ -z "${I3_RESURRECT_SESSION_TOKEN:-}" ] && polybar_visible || return 0
    POLYBAR_WAS_VISIBLE=1
    polybar_hide_for_restore
}

restore_polybar_after_restore() {
    [ "$POLYBAR_WAS_VISIBLE" = 0 ] || polybar_show_after_restore
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

workspace_ready() {
    local tree="$1" workspace="$2"
    detail="$(resurrect_state ready "$RESTORE_STATE_DIR" "$META_DIR" "$workspace" <<< "$tree" 2>&1)" &&
        detail="$(jq -n --arg token "$RESTORE_OPERATION" --arg workspace "$workspace" \
            '{action:"restore-ready",token:$token,workspace:$workspace}' | resurrect_group 2>&1)"
}

wait_for_launched() {
    local attempts="$PLACEHOLDER_WAIT_ATTEMPTS" tree workspace
    local -a waiting
    while [ "${#launched[@]}" -gt 0 ]; do
        if ! restore_active; then
            for workspace in "${launched[@]}"; do outcome["$workspace"]=failed; reason["$workspace"]='restore cancelled'; done
            return
        fi
        tree="$(i3-msg -t get_tree)" || tree=""
        waiting=()
        for workspace in "${launched[@]}"; do
            if workspace_ready "$tree" "$workspace"; then
                outcome["$workspace"]=ready
            else
                reason["$workspace"]="$detail"
                waiting+=("$workspace")
            fi
        done
        launched=("${waiting[@]}")
        attempts=$((attempts - 1))
        if [ "${#launched[@]}" -gt 0 ] && [ "$attempts" -le 0 ]; then
            for workspace in "${launched[@]}"; do outcome["$workspace"]=failed; done
            return
        fi
        [ "${#launched[@]}" -eq 0 ] || sleep "$PLACEHOLDER_POLL_INTERVAL"
    done
}

start_labroute() {
    [ "$(head -n 1 "$LABROUTE_FILE" 2>/dev/null)" = on ] || return 0
    I3_RESURRECT_REMOTE_HELPERS="$REMOTE_HELPERS" I3_RESURRECT_LABROUTE_TIMEOUT="$LABROUTE_TIMEOUT" \
        bash "$LABROUTE_RESTORE" 9>&- || true
}

# ta shares this helper's lock.
start_tmux_restore() {
    [ -x "$TMUX_RESTORE" ] || return 0
    jq -se '[.[][] | .command | arrays | .[] | strings
             | select(startswith("--initial-command=env I3_RESURRECT_LOCAL_TMUX="))] | length > 0' \
        "$RESTORE_STATE_DIR"/workspace_*_programs.json >/dev/null 2>&1 || return 0
    # Do not pass the i3 restore lock to tmux.
    setsid "$TMUX_RESTORE" </dev/null >/dev/null 2>&1 9>&- &
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
resurrect_controller
I3_RESURRECT="$(find_i3_resurrect)" || resurrect_fail 'Restore unavailable: i3-resurrect not found.'
if ! [[ "$PLACEHOLDER_WAIT_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
    resurrect_fail 'Restore wait attempts must be positive integers.'
fi
for interval in "$PLACEHOLDER_POLL_INTERVAL" "$LABROUTE_TIMEOUT"; do
    if ! [[ "$interval" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        resurrect_fail 'Restore delays must be nonnegative numbers of seconds.'
    fi
done
if [[ "$LABROUTE_TIMEOUT" =~ ^0+([.]0+)?$ ]]; then
    resurrect_fail 'The lab route timeout must be greater than zero.'
fi

DESTINATION_GROUP="$(resurrect_selected_group)" || resurrect_fail "Cannot determine the destination group."
RESTORE_OPERATION="$(tr -d '-' </proc/sys/kernel/random/uuid)"
umask 077
if [ "$CHECK" = 0 ]; then
    resurrect_lock || exit 1
fi
PROFILE_META_DIR="${I3_RESURRECT_REPORT_DIR:-$META_DIR}"
# The session already resolved and validated these generations.
if [ "${I3_RESURRECT_VALIDATED:-0}" != 1 ]; then
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
fi
if [ "$(cat "$LABROUTE_FILE" 2>/dev/null)" = on ]; then
    for command in timeout zsh; do
        command -v "$command" >/dev/null ||
            resurrect_fail "Restore unavailable: $command not found for the lab route."
    done
    [ -r "$REMOTE_HELPERS" ] || resurrect_fail "Restore unavailable: cannot read $REMOTE_HELPERS."
    [ -r "$LABROUTE_RESTORE" ] || resurrect_fail "Restore unavailable: cannot read $LABROUTE_RESTORE."
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
# The session coordinator handles all-groups restores.
if [ -z "${I3_RESURRECT_SESSION_TOKEN:-}" ]; then
    start_labroute
    start_tmux_restore
fi
stat="$(</proc/$$/stat)"
read -ra stat <<< "${stat##*) }"
owner="${stat[19]}"
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
    if [ "$status" != ready ] && [ "$status" != launched ]; then
        failed=1
        printf 'Workspace "%s": %s\n' "$workspace" "$detail" >&2
    fi
}

declare -A outcome=() reason=()
planned=()
launched=()
while IFS= read -r workspace || [ -n "$workspace" ]; do
    if ! restore_active; then
        planned+=("$workspace")
        outcome["$workspace"]=failed
        reason["$workspace"]='restore cancelled'
        break
    fi
    planned+=("$workspace")
    outcome["$workspace"]=failed
    merging="$(jq -r --arg workspace "$workspace" '.[] | select(.workspace == $workspace) | .merging' <<< "$RESTORE_PLAN")"
    if [ "$merging" = false ] && ! i3-msg -t get_tree | jq -e --arg workspace "$workspace" '
        [.. | objects | select(.type? == "workspace" and .name == $workspace)
         | .. | objects | select(.window? != null)] | length == 0
    ' >/dev/null; then
        reason["$workspace"]='destination became occupied or i3 is unavailable'
        continue
    fi
    layout="$RESTORE_STATE_DIR/workspace_$(workspace_file_id "$workspace")_layout.json"
    programs="$RESTORE_STATE_DIR/workspace_$(workspace_file_id "$workspace")_programs.json"
    if ! jq -e 'length > 0' "$programs" >/dev/null; then
        reason["$workspace"]='no launchable programs were saved'
        continue
    fi
    if ! detail="$(jq -n --arg token "$RESTORE_OPERATION" --arg workspace "$workspace" --arg path "$layout" \
        '{action:"restore-layout",token:$token,workspace:$workspace,path:$path}' | resurrect_group 2>&1)"; then
        reason["$workspace"]="layout restore failed: $detail"
        continue
    fi
    # Placeholders are ready when the controller replies.
    launch_error=""
    while IFS= read -r entry; do
        if ! detail="$(jq -n --arg token "$RESTORE_OPERATION" --arg workspace "$workspace" --argjson entry "$entry" \
            '{action:"restore-launch",token:$token,workspace:$workspace,entry:$entry}' | resurrect_group 2>&1)"; then
            launch_error="${launch_error:-program launch failed: $detail}"
        fi
    done < <(jq -c '.[]' "$programs")
    if [ -n "$launch_error" ]; then
        reason["$workspace"]="$launch_error"
        continue
    fi
    outcome["$workspace"]=launched
    launched+=("$workspace")
done < <(jq -r '.[].workspace' <<< "$RESTORE_PLAN")
# The parent waits for all groups.
[ -n "${I3_RESURRECT_SESSION_TOKEN:-}" ] || wait_for_launched
for workspace in "${planned[@]}"; do
    record_result "$workspace" "${outcome[$workspace]}" "${reason[$workspace]:-}"
done

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
    summary='Restore finished with errors.'$'\n'"$(jq -r '.[] | select(.status != "ready" and .status != "launched") | "Workspace \(.workspace): \(.detail)"' <<< "$results")"
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
completed="$(jq '[.[] | select(.status == "ready" or .status == "launched") | .source_workspace]' <<< "$results")"
reattach="$(resurrect_state sessions "$STATE_DIR" "$META_DIR" "$completed")"
if [ -n "$reattach" ]; then
    summary="$summary"$'\n'"$reattach"
fi
report="$(mktemp "$PROFILE_META_DIR/.restore-report.XXXXXXXX")"
jq -n --arg snapshot "$STATE_DIR" --argjson workspaces "$results" --arg sessions "$reattach" \
    --argjson mapping "$RESTORE_PLAN" \
    '{snapshot: $snapshot, mapping: $mapping, workspaces: $workspaces, sessions: $sessions}' > "$report"
mv -- "$report" "$PROFILE_META_DIR/last-restore.json"
notify "$summary"
exit "$failed"
