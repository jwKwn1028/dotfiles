#!/usr/bin/env bash
# Toggle i3 window title bars (decorations) for every window across all
# workspaces/monitors, plus the default for future windows.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

mkdir -p "$SNAP_RUNTIME_DIR" 2>/dev/null

# NOTE: keep "pixel 1" in sync with default_border in ~/.config/i3/config
CURRENT="off"
if [ -f "$SNAP_TITLES_STATE" ]; then
  CURRENT="$(cat "$SNAP_TITLES_STATE")"
fi

if [ "$CURRENT" = "off" ]; then
  NEW="normal"
  echo on  > "$SNAP_TITLES_STATE"
else
  NEW="pixel 1"
  echo off > "$SNAP_TITLES_STATE"
fi

snap_log "titles -> $NEW"

# `default_border` and `for_window` are both config-only (not runtime
# commands), so we can't change the default for future windows from a
# script. Instead snap-watcher.sh reads this state file on each window::new
# event and applies the matching border to the newly-created window.

# Apply to every existing window by con_id (covers all workspaces, all
# outputs, floating + tiling, regardless of class).
i3-msg -t get_tree \
  | jq -r '.. | objects | select(.window != null) | .id' \
  | while read -r id; do
      i3-msg "[con_id=$id] border $NEW" >/dev/null
    done
