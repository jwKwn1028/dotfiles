#!/usr/bin/env bash

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

RESTORE_HIDDEN="$SNAP_RUNTIME_DIR/i3-window-mode.restore-hidden"

case "${1:-}" in
  open)
    if polybar_visible && [ ! -e "$POLYBAR_PEEK_OWNER" ]; then
      rm -f "$RESTORE_HIDDEN"
    else
      : >"$RESTORE_HIDDEN"
    fi
    polybar_show_persistent
    ;;
  close)
    if [ -e "$RESTORE_HIDDEN" ]; then
      rm -f "$RESTORE_HIDDEN"
      if polybar_visible; then
        "$DIR/toggle-polybar-resnap.sh"
      fi
    fi
    ;;
  *)
    printf 'usage: %s open|close\n' "${0##*/}" >&2
    exit 2
    ;;
esac
