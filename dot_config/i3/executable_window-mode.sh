#!/usr/bin/env bash
# Polybar visibility for the Super+R window mode. Same contract as bar-nav.sh and
# kill-workspace-mode.sh: a bar already up stays up on exit, one that was hidden
# -- or up only for a transient peek -- hides again.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

# Its own marker, so an interleaved bar-nav session cannot consume this one.
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
