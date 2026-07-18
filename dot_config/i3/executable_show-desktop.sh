#!/usr/bin/env bash
# Toggle "show desktop": switch to/from a dedicated empty workspace.
# First press: jump to _desktop. Second press: go back via i3 back_and_forth.
CURR=$(i3-msg -t get_workspaces | jq -r '.[] | select(.focused) | .name')
if [ "$CURR" = "_desktop" ]; then
  i3-msg "workspace back_and_forth" >/dev/null
else
  i3-msg "workspace _desktop" >/dev/null
fi
