#!/usr/bin/env bash
# Show polybar if it is hidden, then enter the kill-workspace mode.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

# Kill-workspace mode needs the bar to remain visible, even if it happens to be
# in the middle of a transient workspace peek.
peek_was_active=0
if command -v flock >/dev/null 2>&1; then
  exec 8>"$POLYBAR_CONTROL_LOCK"
  if flock -w 2 8; then
    [ -e "$POLYBAR_PEEK_OWNER" ] && peek_was_active=1
    polybar_cancel_peek
    flock -u 8
  fi
  exec 8>&-
fi

if ! polybar_visible; then
  "$DIR/toggle-polybar-resnap.sh"
elif [ "$peek_was_active" = 1 ]; then
  # A temporary overlay just became persistent for this mode, so bring
  # snapped windows into the normal visible-bar geometry once.
  "$DIR/resnap.sh"
  polybar_raise
fi

exec i3-msg 'mode "kill workspace"' >/dev/null
