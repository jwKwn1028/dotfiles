#!/usr/bin/env bash

set -u

DIR="$(dirname "$(readlink -f "$0")")"

action=kill-group
[ "${1:-}" != all ] || action=kill-all-groups
"$DIR/workspace-action.sh" "$action"
i3-msg 'mode "default"' >/dev/null
exec "$DIR/kill-workspace-mode.sh" close
