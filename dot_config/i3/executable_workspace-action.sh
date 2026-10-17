#!/usr/bin/env bash
# Perform workspace actions; keyboard navigation requests a Polybar peek.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
action="${1:-}"
workspace="${2:-}"

current_numbered_workspace() {
  local current

  current="$(
    i3-msg -t get_workspaces |
      jq -er '.[] | select(.focused) | .num'
  )" || return 1
  case "$current" in
    1|2|3|4|5|6|7|8|9|10) printf '%s\n' "$current" ;;
    *) return 1 ;;
  esac
}

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
  relative|cycle)
    case "$workspace" in
      -1|1) ;;
      *) exit 2 ;;
    esac

    if [ "$action" = cycle ]; then
      exec 9>"${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/i3-workspace-cycle.lock"
      flock 9 || exit 1
    fi
    current="$(current_numbered_workspace)" || exit 1

    if [ "$action" = cycle ]; then
      target=$(((current - 1 + workspace + 10) % 10 + 1))
    else
      target=$((current + workspace))
    fi
    case "$target" in
      1|2|3|4|5|6|7|8|9|10) ;;
      *) exit 0 ;;
    esac
    i3-msg "workspace --no-auto-back-and-forth number $target" >/dev/null || exit 1
    exec 9>&-
    ;;
  move-relative)
    case "$workspace" in
      -1|1) ;;
      *) exit 2 ;;
    esac

    current="$(current_numbered_workspace)" || exit 1
    target=$(((current - 1 + workspace + 10) % 10 + 1))
    "$DIR/move-to-workspace.sh" "$target" || exit $?
    ;;
  *)
    exit 2
    ;;
esac

if [ "$action" != cycle ]; then
  "$DIR/polybar-peek.sh"
fi
