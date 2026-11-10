#!/usr/bin/env bash
set -euo pipefail

TERMINAL_CLASS=com.mitchellh.ghostty.scratchpad
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
DISPLAY_TAG="${DISPLAY:-default}"
DISPLAY_TAG="${DISPLAY_TAG//[^[:alnum:]_.-]/_}"
mkdir -p "$RUNTIME_DIR"
exec 9>"$RUNTIME_DIR/i3-scratch-terminal-$DISPLAY_TAG.lock"
flock -n 9 || exit 0

terminal_state() {
    i3-msg -t get_tree | jq -r --arg class "$TERMINAL_CLASS" '
        def terminal($workspace):
            (if .type? == "workspace" then .name else $workspace end) as $workspace |
            if .window? != null and .window_properties.class? == $class then
                [.id, $workspace] | @tsv
            else
                (.nodes[]?, .floating_nodes[]?) | terminal($workspace)
            end;
        first(terminal(""))'
}

wait_terminal_size() {
    local attempt geometry previous="" stable=0
    for ((attempt = 0; attempt < 20; attempt++)); do
        geometry="$(i3-msg -t get_tree | jq -r --argjson id "$terminal_id" '
            first(.. | objects | select(.id? == $id) |
                select(.rect.width > 0 and .rect.height > 0) |
                [.rect.width, .rect.height] | @tsv) // empty')"
        if [ -n "$geometry" ]; then
            if [ "$geometry" = "$previous" ]; then
                stable=$((stable + 1))
                [ "$stable" -lt 3 ] || return 0
            else
                stable=0
            fi
            previous="$geometry"
        fi
        sleep 0.05
    done
    [ -n "$previous" ]
}

state="$(terminal_state)"
created=false
if [ -z "$state" ]; then
    created=true
    ghostty --class="$TERMINAL_CLASS" --gtk-single-instance=false \
        --env=ZSH_BANNER_DISABLE=1 --working-directory=home \
        </dev/null >/dev/null 2>&1 9>&- &
    terminal_pid=$!
    trap 'kill "$terminal_pid" 2>/dev/null || true; wait "$terminal_pid" 2>/dev/null || true' EXIT
    problem='did not open within 5 seconds'
    for ((attempt = 0; attempt < 100; attempt++)); do
        state="$(terminal_state)"
        [ -z "$state" ] || break
        if ! kill -0 "$terminal_pid" 2>/dev/null; then
            state="$(terminal_state)"
            problem='exited before its window appeared'
            break
        fi
        sleep 0.05
    done
    if [ -z "$state" ]; then
        printf 'scratch-terminal: Ghostty %s\n' "$problem" >&2
        exit 1
    fi
    trap - EXIT
fi

IFS=$'\t' read -r terminal_id workspace <<< "$state"
visible="$(i3-msg -t get_workspaces | jq --arg workspace "$workspace" '
    any(.[]; .name == $workspace and .visible)')"
if [ "$created" = false ] && [ "$visible" = true ]; then
    i3-msg "[con_id=$terminal_id] move scratchpad" >/dev/null
    exit 0
fi

if [ "$created" = true ]; then
    i3-msg "[con_id=$terminal_id] move scratchpad" >/dev/null
    wait_terminal_size
fi

i3-msg "[con_id=$terminal_id] move scratchpad; \
    [con_id=$terminal_id] scratchpad show; \
    [con_id=$terminal_id] floating enable, move position center, focus" >/dev/null
