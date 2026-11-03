#!/bin/sh
case $0 in
  */*) exec "${0%/*}/workspace-action.sh" previous-window ;;
esac
exec ./workspace-action.sh previous-window
