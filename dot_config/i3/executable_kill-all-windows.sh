#!/usr/bin/env bash
# Kill-workspace mode's Shift+K: close every i3 window, then leave the mode.
#
# Polybar goes through the mode's own `close` rather than an unconditional
# hide. The two agree whenever the bar was hidden before Super+X -- the common
# case, and the one the old unconditional hide was written for -- and differ
# only when the bar was already up on purpose, where hiding it would destroy a
# state the user chose. Nothing is left to navigate to after a global kill, so
# this exit restores like Return and Escape rather than leaving the bar up the
# way the number keys do.

set -u

DIR="$(dirname "$(readlink -f "$0")")"

i3-msg '[all] kill; mode "default"' >/dev/null
exec "$DIR/kill-workspace-mode.sh" close
