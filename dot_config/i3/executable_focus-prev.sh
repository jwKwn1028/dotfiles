#!/usr/bin/env bash
# Focus the most-recently-focused window before the current one.
# Pressing again returns to the original (2-window alt-tab toggle).
# If that lands on a different workspace, request a transient Polybar peek so
# the jump is visible, matching workspace-action.sh.
set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

focused_workspace() {
  i3-msg -t get_workspaces 2>/dev/null |
    jq -r '.[] | select(.focused) | .name' 2>/dev/null || true
}

[ -f "$SNAP_FOCUS_HISTORY" ] || exit 0
PREV=$(sed -n '2p' "$SNAP_FOCUS_HISTORY" 2>/dev/null || true)

if [[ "${PREV:-}" =~ ^[0-9]+$ ]]; then
  before=$(focused_workspace)
  i3-msg "[con_id=$PREV] focus" >/dev/null
  after=$(focused_workspace)
  if [ -n "$before" ] && [ -n "$after" ] && [ "$before" != "$after" ]; then
    "$DIR/polybar-peek.sh"
  fi
fi
