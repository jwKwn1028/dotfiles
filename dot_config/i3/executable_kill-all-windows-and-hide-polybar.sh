#!/usr/bin/env bash
# Leave kill-workspace mode after closing every i3 window, then hide Polybar.

set -u

DIR="$(dirname "$(readlink -f "$0")")"

i3-msg '[all] kill; mode "default"' >/dev/null
exec "$DIR/toggle-polybar-resnap.sh" hide
