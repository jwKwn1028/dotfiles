#!/usr/bin/env bash
# Polybar visibility for the Super+X kill-workspace mode. Same contract as
# window-mode.sh, split by intent: aborting leaves no trace, acting leaves the
# result on screen.
#
# `close` runs on every exit but the number keys -- Return, Escape, and the
# global kill in kill-all-windows.sh. A bar this mode showed hides again, one
# that was already up stays up; an unconditional hide would make
# Super+X-then-Escape a way to lose a bar you meant to keep. The number keys
# get no `close` on purpose: after a kill the point is to see the workspace
# come up empty, so whatever the bar is doing, it keeps doing it.
#
# The marker cannot go stale even though most exits never clear it: `open`
# rewrites it from the live bar state on every entry, and nothing but this
# mode's own Return and Escape ever reads it.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

# Its own marker, so an interleaved bar-nav or window-mode session cannot
# consume this one.
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
