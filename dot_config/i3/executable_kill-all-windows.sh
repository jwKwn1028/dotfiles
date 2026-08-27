#!/usr/bin/env bash
# Kill-workspace mode's Shift+K: close every i3 window, then leave the mode.
#
# Polybar goes through the mode's own `close`, not an unconditional hide: a bar
# that was up on purpose stays up. Nothing is left to navigate to after a global
# kill, so this exit restores like Return and Escape, not like the number keys.

set -u

DIR="$(dirname "$(readlink -f "$0")")"

i3-msg '[all] kill; mode "default"' >/dev/null
exec "$DIR/kill-workspace-mode.sh" close
