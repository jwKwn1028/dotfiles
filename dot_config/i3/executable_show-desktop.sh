#!/usr/bin/env bash
# Toggle "show desktop": jump to a dedicated empty workspace and back.
CURR=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused) | .name')
if [ "$CURR" = "_desktop" ]; then
  i3-msg "workspace back_and_forth" >/dev/null
else
  i3-msg "workspace _desktop" >/dev/null
fi
