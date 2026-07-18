#!/usr/bin/env bash
# Show polybar if it is hidden, then enter the kill-workspace mode.

set -u

DIR="$(dirname "$(readlink -f "$0")")"

polybar_windows() {
  xdotool search --class '^[Pp]olybar$' 2>/dev/null || true
}

window_viewable() {
  local info
  info=$(xwininfo -id "$1" 2>/dev/null) || return 1
  [[ "$info" == *"IsViewable"* ]]
}

polybar_visible() {
  local win
  for win in $(polybar_windows); do
    window_viewable "$win" && return 0
  done
  return 1
}

if ! polybar_visible; then
  "$DIR/toggle-polybar-resnap.sh"
fi

exec i3-msg 'mode "kill workspace"' >/dev/null
