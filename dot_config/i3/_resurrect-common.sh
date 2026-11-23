#!/usr/bin/env bash

RESURRECT_PYTHON="${I3_SYSTEM_PYTHON:-/usr/bin/python3}"
RESURRECT_HELPER="$DIR/i3-resurrect-state.py"
[ -r "$RESURRECT_HELPER" ] || RESURRECT_HELPER="$DIR/executable_i3-resurrect-state.py"

resurrect_state() {
    "$RESURRECT_PYTHON" "$RESURRECT_HELPER" "$@"
}

resurrect_lock() {
    local runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    local display_key
    display_key="$(printf '%s' "${DISPLAY:-default}" | sha256sum | cut -c1-16)"
    mkdir -p "$runtime"
    if [ -n "${I3_RESURRECT_PARENT_LOCK:-}" ] &&
        [ "$I3_RESURRECT_PARENT_LOCK" = "$(readlink -m "$runtime/i3-resurrect-$display_key.lock")" ] &&
        [ "$(readlink -f "/proc/$$/fd/9")" = "$I3_RESURRECT_PARENT_LOCK" ]; then
        flock -n 9
        return $?
    fi
    exec 9>"$runtime/i3-resurrect-$display_key.lock"
    if ! flock -n 9; then
        printf 'Another i3 save or restore is already running.\n' >&2
        notify 'Another save or restore is already running.'
        return 1
    fi
}

# shellcheck disable=SC2034
resurrect_paths() {
    WORKSPACES_FILE="$META_DIR/workspaces.txt"
    FOCUSED_FILE="$META_DIR/focused-workspace.txt"
    ZATHURA_PAGES_FILE="$META_DIR/zathura-pages.json"
    ZEN_PAGES_FILE="$META_DIR/zen-pages.json"
    GHOSTTY_SESSIONS_FILE="$META_DIR/ghostty-sessions.json"
    LABROUTE_FILE="$META_DIR/labroute.txt"
}

workspace_file_id() {
    printf '%s' "$1" | tr -d '/\\:*"<>|'
}

resurrect_dependencies() {
    local command
    for command in i3-msg jq flock sha256sum; do
        command -v "$command" >/dev/null || { printf '%s\n' "$command"; return 1; }
    done
    [ -x "$RESURRECT_PYTHON" ] || { printf '%s\n' "$RESURRECT_PYTHON"; return 1; }
    [ -r "$RESURRECT_HELPER" ] || { printf '%s\n' "$RESURRECT_HELPER"; return 1; }
}

resurrect_fail() {
    printf '%s\n' "$1" >&2
    [ "${CHECK:-0}" = 1 ] || notify "$1"
    exit 1
}

resurrect_group_helper() {
    local helper="$DIR/workspace-groups.py"
    [ -r "$helper" ] || helper="$DIR/executable_workspace-groups.py"
    printf '%s\n' "${I3_RESURRECT_GROUP_HELPER:-$helper}"
}

# With nc, requests skip Python's startup.
resurrect_controller() {
    [ -z "${I3_RESURRECT_CONTROLLER:-}" ] && [ -z "${I3_RESURRECT_GROUP_HELPER:-}" ] || return 0
    command -v nc >/dev/null 2>&1 || return 0
    I3_RESURRECT_CONTROLLER="$("$RESURRECT_PYTHON" "$(resurrect_group_helper)" path)/controller.sock" ||
        I3_RESURRECT_CONTROLLER=""
}

resurrect_group() {
    local reply
    if [ -n "${I3_RESURRECT_GROUP_HELPER:-}" ] || [ -z "${I3_RESURRECT_CONTROLLER:-}" ] ||
        ! command -v nc >/dev/null 2>&1; then
        "$RESURRECT_PYTHON" "$(resurrect_group_helper)" request
        return
    fi
    reply="$({ tr -d '\n'; echo; } | nc -U -w 15 "$I3_RESURRECT_CONTROLLER" 2>/dev/null |
        jq -r 'if .ok then "ok\t" + (.result | tojson)
               else "error\t" + (.error // "Workspace action failed") end' 2>/dev/null)"
    case "$reply" in
        ok$'\t'*) printf '%s\n' "${reply#*$'\t'}" ;;
        error$'\t'*) printf '%s\n' "${reply#*$'\t'}" >&2; return 1 ;;
        *) printf 'Workspace controller unavailable: %s\n' "$I3_RESURRECT_CONTROLLER" >&2; return 1 ;;
    esac
}

resurrect_selected_group() {
    if [ -n "${I3_RESURRECT_GROUP:-}" ]; then
        printf '%s\n' "$I3_RESURRECT_GROUP"
    else
        printf '%s\n' '{"action":"status"}' | resurrect_group | jq -er '.selected'
    fi
}
