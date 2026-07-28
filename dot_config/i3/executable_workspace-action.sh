#!/usr/bin/env bash
# Perform a numbered workspace action and then request a transient Polybar peek.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
action="${1:-}"
workspace="${2:-}"

case "$action" in
  switch)
    case "$workspace" in
      1|2|3|4|5|6|7|8|9|10) ;;
      *) exit 2 ;;
    esac
    i3-msg "workspace number $workspace" >/dev/null || exit 1
    ;;
  move)
    case "$workspace" in
      1|2|3|4|5|6|7|8|9|10) ;;
      *) exit 2 ;;
    esac
    "$DIR/move-to-workspace.sh" "$workspace" || exit $?
    ;;
  prev|next)
    [ -z "$workspace" ] || exit 2
    i3-msg "workspace $action" >/dev/null || exit 1
    ;;
  relative)
    case "$workspace" in
      -1|1) ;;
      *) exit 2 ;;
    esac

    current="$(
      i3-msg -t get_workspaces |
        jq -er '.[] | select(.focused) | .num'
    )" || exit 1
    case "$current" in
      1|2|3|4|5|6|7|8|9|10) ;;
      *) exit 1 ;;
    esac

    target=$((current + workspace))
    case "$target" in
      1|2|3|4|5|6|7|8|9|10) ;;
      *) exit 0 ;;
    esac
    i3-msg "workspace number $target" >/dev/null || exit 1
    ;;
  *)
    exit 2
    ;;
esac

"$DIR/polybar-peek.sh"
