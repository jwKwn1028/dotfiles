#!/usr/bin/env bash
# Show polybar if it is hidden, then enter the kill-workspace mode.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

polybar_show_persistent

exec i3-msg 'mode "kill workspace"' >/dev/null
