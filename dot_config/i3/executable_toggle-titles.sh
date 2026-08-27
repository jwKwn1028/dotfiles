#!/usr/bin/env bash
# Toggle i3 title bars on every window, plus the default for future windows.
#
# `default_border` and `for_window` are config-only, so snap-watcher.sh reads
# this state file per window event instead.

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

i3-msg -t get_tree \
  | jq -r '.. | objects | select(.window != null) | .id' \
  | while read -r id; do
      i3-msg "[con_id=$id] border $NEW" >/dev/null
    done
