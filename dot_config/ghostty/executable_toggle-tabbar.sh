#!/usr/bin/env bash
# Toggle Ghostty's tab bar (Alt+Shift+T in i3). Ghostty has no toggle action and
# window-show-tab-bar is config-only, but SIGUSR2 reloads config and includes, so
# flipping a one-line include is a live toggle.
set -euo pipefail

state="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/tabbar-state.conf"

if grep -q never "$state" 2>/dev/null; then
	printf 'window-show-tab-bar = auto\n' >"$state"
else
	printf 'window-show-tab-bar = never\n' >"$state"
fi

# Absent when no terminal is open; not an error worth a nonzero exit.
pkill -USR2 -x ghostty || true
