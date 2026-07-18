#!/usr/bin/env bash
# Focus the most-recently-focused window before the current one.
# Pressing again returns to the original (2-window alt-tab toggle).
set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

[ -f "$SNAP_FOCUS_HISTORY" ] || exit 0
PREV=$(sed -n '2p' "$SNAP_FOCUS_HISTORY" 2>/dev/null || true)

if [[ "${PREV:-}" =~ ^[0-9]+$ ]]; then
  i3-msg "[con_id=$PREV] focus" >/dev/null
fi
