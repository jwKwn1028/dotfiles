#!/usr/bin/env bash
# Keyboard cursor over Polybar's own modules: Super+I, then h/l to move, j/k to
# adjust, Return to click, Shift+Return to right-click.
#
# Polybar never takes keyboard focus, so the cursor lives in the i3 mode that
# calls this script, and the highlight is a hidden twin module swapped in over
# IPC (see config.ini). The mode is sticky: only a stop that opens a window
# leaves it, so toggles can be nudged repeatedly.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

STATE="$SNAP_RUNTIME_DIR/i3-polybar-nav.idx"
# Present if the bar was not already staying visible when the mode opened, so
# leaving can put it back and never strand a hidden bar on screen.
RESTORE_HIDDEN="$SNAP_RUNTIME_DIR/i3-polybar-nav.restore-hidden"

# Cursor stops, left to right. Each has a `<module>-sel` twin in config.ini.
modules=(date pulseaudio battery network bluetooth powermenu)

# Return. Mirrors each module's click-left handler. date_toggle drives both
# halves of the pair: the action is module state, and the plain half is the
# hidden one while the cursor sits on it.
click_left=(
  "date_toggle"
  "pactl set-sink-mute @DEFAULT_SINK@ toggle"
  "xfce4-power-manager-settings"
  "nm-connection-editor"
  "blueman-manager"
  "power_menu"
)
# 1 = opens a window, which takes the keyboard, so the cursor closes first.
click_left_opens=(0 0 1 1 1 1)

# Shift+Return. Only pulseaudio has a click-right handler in the bar.
click_right=("" "pavucontrol" "" "" "" "")
click_right_opens=(0 1 0 0 0 0)

# j/k, standing in for a scroll wheel; empty means no scroll handler. Volume
# steps by 1 rather than the wheel's 5 -- parking the cursor on the module is
# the fine adjustment. Brightness keeps the coarse 5.
scroll_down=("" "pactl set-sink-volume @DEFAULT_SINK@ -1%" "brightnessctl -q set 5%-" "" "" "")
scroll_up=("" "pactl set-sink-volume @DEFAULT_SINK@ +1%" "brightnessctl -q set +5%" "" "" "")

# The bar's power menu is built for the mouse; rofi gives the same actions to
# the keyboard.
power_menu() {
  local choice
  choice=$(printf 'lock\nreboot\nshut down\nexit i3\n' |
    rofi -dmenu -i -p 'power') || return 0
  case "$choice" in
    lock) i3lock ;;
    reboot) i3-nagbar -t warning -m 'Reboot?' -B 'Yes' 'systemctl reboot' ;;
    'shut down') "$HOME/.config/polybar/scripts/confirm-poweroff.sh" ;;
    'exit i3') i3-nagbar -t warning -m 'Exit i3?' -B 'Yes' 'i3-msg exit' ;;
  esac
}

ipc() {
  polybar-msg action "#$1.$2" >/dev/null 2>&1 || true
}

date_toggle() {
  ipc date toggle
  ipc date-sel toggle
}

# Swap module <-> twin. Every bar receives the action, so they stay in step.
select_module() {
  ipc "${modules[$1]}" module_hide
  ipc "${modules[$1]}-sel" module_show
}

deselect_module() {
  ipc "${modules[$1]}-sel" module_hide
  ipc "${modules[$1]}" module_show
}

current_index() {
  local idx
  idx=$(cat "$STATE" 2>/dev/null) || idx=0
  case "$idx" in
    ''|*[!0-9]*) idx=0 ;;
  esac
  [ "$idx" -lt "${#modules[@]}" ] || idx=0
  printf '%s\n' "$idx"
}

move() {
  local old new
  old=$(current_index)
  new=$(( (old + $1 + ${#modules[@]}) % ${#modules[@]} ))
  printf '%s\n' "$new" >"$STATE"
  deselect_module "$old"
  select_module "$new"
}

# Click the selected module; an empty action is a no-op, not an error.
activate() {
  local idx cmd opens
  idx=$(current_index)
  if [ "$1" = right ]; then
    cmd="${click_right[$idx]}"
    opens="${click_right_opens[$idx]}"
  else
    cmd="${click_left[$idx]}"
    opens="${click_left_opens[$idx]}"
  fi
  [ -n "$cmd" ] || return 0

  if [ "$opens" = 1 ]; then
    close
    i3-msg 'mode "default"' >/dev/null 2>&1 || true
  fi
  eval "$cmd"
}

scroll() {
  local idx cmd
  idx=$(current_index)
  if [ "$1" = down ]; then
    cmd="${scroll_down[$idx]}"
  else
    cmd="${scroll_up[$idx]}"
  fi
  [ -n "$cmd" ] && eval "$cmd"
  return 0
}

# Put every pair back to its plain module, skipping the stop named in $1. The
# skip matters: hiding and showing one module twice in quick succession makes
# polybar collapse the pair and keep the plain half.
reset_pairs() {
  local i
  for i in "${!modules[@]}"; do
    [ "$i" = "${1:-}" ] || deselect_module "$i"
  done
}

close() {
  rm -f "$STATE"
  # Every twin, not just the selected one: a polybar restart mid-mode can leave
  # a pair out of step with the index file.
  reset_pairs

  if [ -e "$RESTORE_HIDDEN" ]; then
    rm -f "$RESTORE_HIDDEN"
    # Re-check: the bar may already have been hidden during the mode, and this
    # toggle would put it back up.
    if polybar_visible; then
      "$DIR/toggle-polybar-resnap.sh"
    fi
  fi
  return 0
}

case "${1:-}" in
  open)
    # A bar up only for a transient peek counts as hidden: it was on its way
    # out, and polybar_show_persistent is about to make it stay.
    if polybar_visible && [ ! -e "$POLYBAR_PEEK_OWNER" ]; then
      rm -f "$RESTORE_HIDDEN"
    else
      : >"$RESTORE_HIDDEN"
    fi
    polybar_show_persistent
    printf '0\n' >"$STATE"
    reset_pairs 0
    select_module 0
    ;;
  prev) move -1 ;;
  next) move 1 ;;
  down) scroll down ;;
  up) scroll up ;;
  click) activate left ;;
  click-right) activate right ;;
  close) close ;;
  *)
    printf 'usage: %s open|prev|next|down|up|click|click-right|close\n' \
      "${0##*/}" >&2
    exit 2
    ;;
esac
