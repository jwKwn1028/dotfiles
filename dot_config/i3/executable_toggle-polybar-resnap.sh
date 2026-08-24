#!/usr/bin/env bash
# Toggle polybar (or explicitly show/hide it), wait for the change to reach X,
# raise the bar, then re-fit snapped windows.
#
# An explicit visibility request owns the final state, so cancelling transient
# ownership stops a peek's delayed worker from applying a second, stale hide.
# Polybar cannot restack itself without override-redirect, so raising here is
# what keeps the binding deterministic when i3's workspace stack covers the bar.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

requested="${1:-toggle}"
case "$requested" in
  toggle | show | hide) ;;
  *)
    printf 'Usage: %s [toggle|show|hide]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

if command -v flock >/dev/null 2>&1; then
  exec 9>"$POLYBAR_CONTROL_LOCK"
  flock -w 2 9 || {
    snap_log "polybar toggle skipped: lock busy"
    exit 0
  }
fi

if [ -e "$POLYBAR_PEEK_OWNER" ]; then
  polybar_cancel_peek
  snap_log "polybar peek cancelled by explicit visibility request"
fi

before=$(polybar_visible_value)
case "$requested" in
  toggle)
    if [ "$before" = 1 ]; then
      wanted=0
      cmd=hide
    else
      wanted=1
      cmd=show
    fi
    ;;
  show)
    wanted=1
    cmd=show
    ;;
  hide)
    wanted=0
    cmd=hide
    ;;
esac

if [ "$before" = "$wanted" ]; then
  after="$before"
else
  polybar_set_state "$cmd" "$wanted" || true
  after=$(polybar_wait_for_state "$wanted") || true
fi

if [ "${after:-$before}" = 1 ]; then
  polybar_raise
fi

snap_log "polybar $cmd $before -> ${after:-?}"
"$DIR/resnap.sh"

if [ "${after:-$before}" = 1 ]; then
  polybar_raise
fi

exit 0
