#!/usr/bin/env bash
# Flip the built-in touchpad on/off, defaulting to OFF.
#
# The ELAN pad exposes TWO X pointer nodes, "Touchpad" and a shadow "Mouse":
# both are the same physical pad and both must be switched or the surface stays
# alive. External mice and the TrackPoint are left alone.
#
# Usage: toggle-touchpad.sh [toggle|on|off]   (default: toggle)
#   toggle  flip current state; when the state can't be read, DISABLE
#   on      force enable
#   off     force disable
# The state counts as disabled ONLY when every node is readable and confirmed
# disabled, so anything ambiguous makes a toggle turn the pad off.
#
# TOUCHPAD_MATCH matches the built-in pad's node names case-insensitively --
# "ELAN0688:00 04F3:320B Touchpad" and its "... Mouse" shadow, not external mice
# or "TPPS/2 Elan TrackPoint". Override it if the hardware changes.

set -u

MATCH="${TOUCHPAD_MATCH:-ELAN0688}"

export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ] && [ -r "$HOME/.Xauthority" ]; then
  export XAUTHORITY="$HOME/.Xauthority"
fi

command -v xinput > /dev/null 2>&1 || { echo "toggle-touchpad: xinput not found" >&2; exit 1; }

touchpad_ids() {
  xinput list 2> /dev/null | grep -iE "$MATCH" | grep -oE 'id=[0-9]+' | cut -d= -f2
}

set_state() {
  local action=$1 ids id name any=0
  ids=$(touchpad_ids)
  [ -z "$ids" ] && { echo "toggle-touchpad: no device matching /$MATCH/" >&2; return 1; }
  for id in $ids; do
    name=$(xinput list --name-only "$id" 2> /dev/null)
    if xinput "$action" "$id" 2> /dev/null; then
      printf '  %sd: %s (id=%s)\n' "$action" "$name" "$id"
      any=1
    fi
  done
  [ "$any" = 1 ]
}

all_disabled() {
  local id en saw=0
  for id in $(touchpad_ids); do
    en=$(xinput list-props "$id" 2> /dev/null | awk -F: '/Device Enabled/{gsub(/[ \t]/,"",$2);print $2;exit}')
    [ -n "$en" ] && saw=1
    [ "$en" = 1 ] && return 1
  done
  [ "$saw" = 1 ]
}

case "${1:-toggle}" in
  on | enable)   set_state enable ;;
  off | disable) set_state disable ;;
  toggle)        if all_disabled; then set_state enable; else set_state disable; fi ;;
  -h | --help | help) sed -n '2,13p' "$0" ;;
  *) echo "usage: ${0##*/} [toggle|on|off]" >&2; exit 2 ;;
esac
