#!/usr/bin/env bash
# Polybar visibility for the Super+X kill-workspace mode. Same contract as
# window-mode.sh: aborting leaves no trace, acting leaves the result on screen.
#
# `close` runs on every exit but the number keys -- Return, Escape, and the
# global kill in kill-all-windows.sh: a bar this mode showed hides again, one
# already up stays up. The number keys skip it so the emptied workspace stays
# visible. The marker cannot go stale: `open` rewrites it from the live bar state
# on every entry, and only this mode's Return and Escape read it.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

# Its own marker, so an interleaved bar-nav or window-mode cannot consume it.
RESTORE_HIDDEN="$SNAP_RUNTIME_DIR/i3-kill-workspace.restore-hidden"

case "${1:-}" in
  open)
    if polybar_visible && [ ! -e "$POLYBAR_PEEK_OWNER" ]; then
      rm -f "$RESTORE_HIDDEN"
    else
      : >"$RESTORE_HIDDEN"
    fi
    polybar_show_persistent
    exec i3-msg 'mode "kill workspace"' >/dev/null
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
