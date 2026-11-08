#!/usr/bin/env bash
# Toggle title bars on existing windows; snap-watcher.sh applies the saved
# choice to new ones, since i3 cannot change default_border at runtime.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

mkdir -p "$SNAP_RUNTIME_DIR" 2>/dev/null

# Keep "pixel 1" in sync with default_border in ~/.config/i3/config.
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

i3-msg "[all] border $NEW" >/dev/null
