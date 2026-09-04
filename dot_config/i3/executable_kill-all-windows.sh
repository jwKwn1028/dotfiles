#!/usr/bin/env bash
# Kill-workspace mode's Shift+K: close every i3 window, then leave the mode.

set -u

DIR="$(dirname "$(readlink -f "$0")")"

i3-msg '[all] kill; mode "default"' >/dev/null
exec "$DIR/kill-workspace-mode.sh" close
