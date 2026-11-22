#!/bin/sh
case $0 in
  */*) exec "${0%/*}/workspace-action.sh" desktop ;;
esac
exec ./workspace-action.sh desktop
