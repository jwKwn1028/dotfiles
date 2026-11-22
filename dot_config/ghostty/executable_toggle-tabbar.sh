#!/usr/bin/env bash
# Toggle the tab-bar include and reload Ghostty with SIGUSR2 (Alt+Shift+T).
set -euo pipefail

state="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/tabbar-state.conf"

if grep -q never "$state" 2>/dev/null; then
	printf 'window-show-tab-bar = auto\n' >"$state"
else
	printf 'window-show-tab-bar = never\n' >"$state"
fi

# Absent when no terminal is open; not an error worth a nonzero exit.
pkill -USR2 -x ghostty || true

# The reload clears tmux mode; restore it.
sleep 0.3
if [[ $(tmux list-clients -F '#{client_flags}' 2>/dev/null) == *focused* &&
	$(xprop -id "$(xdotool getactivewindow 2>/dev/null)" WM_CLASS 2>/dev/null) == *com.mitchellh.ghostty* ]]; then
	"$HOME/.local/bin/ghostty-tmux-mode" on
fi
