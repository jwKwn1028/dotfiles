#!/usr/bin/env bash
# Toggle one floating Ghostty window without ending its shell.
set -euo pipefail

TERMINAL_CLASS=com.mitchellh.ghostty.scratchpad
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
DISPLAY_TAG="${DISPLAY:-default}"
DISPLAY_TAG="${DISPLAY_TAG//[^[:alnum:]_.-]/_}"
mkdir -p "$RUNTIME_DIR"
exec 9>"$RUNTIME_DIR/i3-scratch-terminal-$DISPLAY_TAG.lock"
# Prevent duplicate launches during startup.
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

state="$(terminal_state)"
created=false
if [ -z "$state" ]; then
    created=true
    # A separate instance keeps these options local to this window.
    ghostty --class="$TERMINAL_CLASS" --gtk-single-instance=false \
        --env=ZSH_BANNER_DISABLE=1 --working-directory=home \
        </dev/null >/dev/null 2>&1 9>&- &
    terminal_pid=$!
    # Stop a pending launch if startup fails or i3 IPC disappears.
    trap 'kill "$terminal_pid" 2>/dev/null || true; wait "$terminal_pid" 2>/dev/null || true' EXIT
    for ((attempt = 0; attempt < 100; attempt++)); do
        state="$(terminal_state)"
        [ -z "$state" ] || break
        kill -0 "$terminal_pid" 2>/dev/null || break
        sleep 0.05
    done
    if [ -z "$state" ]; then
        printf 'scratch-terminal: Ghostty did not open within 5 seconds\n' >&2
        exit 1
    fi
    trap - EXIT
fi

IFS=$'\t' read -r terminal_id workspace <<< "$state"
if [ "$created" = true ]; then
    i3-msg "[con_id=$terminal_id] focus" >/dev/null
    exit 0
fi

visible="$(i3-msg -t get_workspaces | jq --arg workspace "$workspace" '
    any(.[]; .name == $workspace and .visible)')"
if [ "$visible" = true ]; then
    i3-msg "[con_id=$terminal_id] move scratchpad" >/dev/null
else
    # Keep its floating size and position when showing it here.
    i3-msg "[con_id=$terminal_id] move scratchpad; \
        [con_id=$terminal_id] scratchpad show; \
        [con_id=$terminal_id] focus" >/dev/null
fi
