#!/usr/bin/env bash
# Toggle polybar visibility, wait for the change to be reflected in the X
# server, keep the bar above existing windows, then re-fit snapped windows.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

if command -v flock >/dev/null 2>&1; then
  exec 9>"$POLYBAR_CONTROL_LOCK"
  flock -w 2 9 || {
    snap_log "polybar toggle skipped: lock busy"
    exit 0
  }
fi

# An explicit toggle owns the final state. Cancelling the transient ownership
# prevents its delayed worker from applying a second, stale hide.
if [ -e "$POLYBAR_PEEK_OWNER" ]; then
  polybar_cancel_peek
  snap_log "polybar peek cancelled by explicit toggle"
fi

before=$(polybar_visible_value)
if [ "$before" = 1 ]; then
  wanted=0
  cmd=hide
else
  wanted=1
  cmd=show
fi

polybar_set_state "$cmd" "$wanted" || true
after=$(polybar_wait_for_state "$wanted") || true

if [ "${after:-$before}" = 1 ]; then
  # The polybar log shows wm-restack is ignored with override-redirect=false.
  # Raising here makes the keybinding deterministic even when i3 keeps an old
  # workspace stack where existing windows still cover the bar area.
  polybar_raise
fi

snap_log "polybar $cmd $before -> ${after:-?}"
"$DIR/resnap.sh"

if [ "${after:-$before}" = 1 ]; then
  polybar_raise
fi

exit 0
