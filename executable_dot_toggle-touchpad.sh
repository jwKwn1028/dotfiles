#!/usr/bin/env bash
# Compatibility entry point for the old ~/.toggle-touchpad.sh path. Keep all
# device matching, XFCE synchronization, and persistent state in one utility.

set -u

TOUCHPAD_BIN="${TOUCHPAD_BIN:-$HOME/.local/bin/touchpad}"

case "${1:-toggle}" in
  toggle) action=toggle ;;
  on|enable) action=enable ;;
  off|disable) action=disable ;;
  -h|--help|help)
    printf 'usage: %s [toggle|on|off]\n' "${0##*/}"
    exit 0
    ;;
  *)
    printf 'usage: %s [toggle|on|off]\n' "${0##*/}" >&2
    exit 2
    ;;
esac

[ -x "$TOUCHPAD_BIN" ] || {
  printf '%s: canonical touchpad utility is unavailable: %s\n' \
    "${0##*/}" "$TOUCHPAD_BIN" >&2
  exit 1
}

exec "$TOUCHPAD_BIN" "$action"
