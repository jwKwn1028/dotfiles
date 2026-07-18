#!/usr/bin/env bash
# Toggle polybar visibility, wait for the change to be reflected in the X
# server, keep the bar above existing windows, then re-fit snapped windows.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

if command -v flock >/dev/null 2>&1; then
  exec 9>"$SNAP_RUNTIME_DIR/i3-polybar-toggle.lock"
  flock -w 2 9 || {
    snap_log "polybar toggle skipped: lock busy"
    exit 0
  }
fi

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
    window_viewable "$win" && { echo 1; return; }
  done
  echo 0
}

raise_polybar() {
  local win
  for win in $(polybar_windows); do
    window_viewable "$win" || continue
    xdotool windowraise "$win" >/dev/null 2>&1 || true
  done
}

set_polybar_state() {
  local cmd="$1"
  local wanted="$2"

  polybar-msg cmd "$cmd" >/dev/null 2>&1 && return 0

  if [ "$wanted" = 1 ] && [ -x "$HOME/.config/polybar/launch.sh" ]; then
    snap_log "polybar IPC unavailable; relaunching"
    "$HOME/.config/polybar/launch.sh" >/dev/null 2>&1
    polybar-msg cmd show >/dev/null 2>&1 && return 0
  fi

  return 1
}

before=$(polybar_visible)
if [ "$before" = 1 ]; then
  wanted=0
  cmd=hide
else
  wanted=1
  cmd=show
fi

set_polybar_state "$cmd" "$wanted" || true

# Poll for the requested state. Exits as soon as the state is visible in X.
for _ in $(seq 1 80); do
  after=$(polybar_visible)
  [ "$after" = "$wanted" ] && break
  sleep 0.025
done

if [ "${after:-$before}" = 1 ]; then
  # The polybar log shows wm-restack is ignored with override-redirect=false.
  # Raising here makes the keybinding deterministic even when i3 keeps an old
  # workspace stack where existing windows still cover the bar area.
  raise_polybar
fi

snap_log "polybar $cmd $before -> ${after:-?}"
"$DIR/resnap.sh"

[ "${after:-$before}" = 1 ] && raise_polybar
