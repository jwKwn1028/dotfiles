#!/usr/bin/env bash
# Kill-workspace mode's Shift+K (group) / Shift+A (all groups): close windows, then exit.

set -u

DIR="$(dirname "$(readlink -f "$0")")"

action=kill-group
[ "${1:-}" != all ] || action=kill-all-groups
/usr/bin/python3 "${I3_GROUP_HELPER:-$DIR/workspace-groups.py}" "$action"
i3-msg 'mode "default"' >/dev/null
exec "$DIR/kill-workspace-mode.sh" close
