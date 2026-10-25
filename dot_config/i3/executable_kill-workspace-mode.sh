#!/usr/bin/env bash
# Polybar visibility for the Super+X kill-workspace mode. `close` runs on every
# exit but the number keys, which leave the emptied workspace on screen.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

# Its own marker: an interleaved bar-nav or window-mode must not consume it.
RESTORE_HIDDEN="$SNAP_RUNTIME_DIR/i3-kill-workspace.restore-hidden"

case "${1:-}" in
  open)
    /usr/bin/python3 "${I3_GROUP_HELPER:-$DIR/workspace-groups.py}" kill-begin || exit 1
    if polybar_visible && [ ! -e "$POLYBAR_PEEK_OWNER" ]; then
      rm -f "$RESTORE_HIDDEN"
    else
      : >"$RESTORE_HIDDEN"
    fi
    polybar_show_persistent
    exec i3-msg 'mode "kill workspace (K: group, A: all)"' >/dev/null
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
