#!/usr/bin/env bash
# Toggle Ghostty's tab bar.
#
# Ghostty has no toggle_tab_bar action (toggle_window_decorations does not cover
# it) and no keybind action that runs a command, so the switch cannot live in
# Ghostty's own config. window-show-tab-bar is config-only, but SIGUSR2 makes a
# running Ghostty reload its config, includes and all -- so flipping a one-line
# include and signalling is a live toggle. Bound to Alt+Shift+T in i3.
set -euo pipefail

state="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/tabbar-state.conf"

if grep -q never "$state" 2>/dev/null; then
	printf 'window-show-tab-bar = auto\n' >"$state"
else
	printf 'window-show-tab-bar = never\n' >"$state"
fi

# Absent when no terminal is open, which is not an error worth a nonzero exit.
pkill -USR2 -x ghostty || true
