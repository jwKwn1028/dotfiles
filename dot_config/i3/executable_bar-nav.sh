#!/usr/bin/env bash
# Keyboard cursor over Polybar's own modules: Super+I, then h/l to move, j/k to
# adjust the selected module, Return to click it, Shift+Return to right-click.
#
# Polybar's window is an X11 dock and never takes keyboard focus, so the cursor
# cannot live in the bar itself; it lives in the i3 "bar" binding mode, which
# calls this script. The highlight is not drawn here either: a module's colors
# are fixed once the bar starts, so each navigable module has a hidden twin in
# config.ini that differs only by the selection background, and the cursor swaps
# the twin in for the original over IPC.
#
# The mode is sticky on purpose. Only a stop that puts a window on screen leaves
# it; toggles stay so the value can be nudged and re-nudged.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

STATE="$SNAP_RUNTIME_DIR/i3-polybar-nav.idx"

# Cursor stops, left to right, named after the polybar modules they select.
# Every one has a `<module>-sel` twin in ~/.config/polybar/config.ini.
modules=(date pulseaudio battery powermenu)

# Return. Mirrors each module's click-left handler.
click_left=(
  "polybar-msg action '#date.toggle'"
  "pactl set-sink-mute @DEFAULT_SINK@ toggle"
  "xfce4-power-manager-settings"
  "power_menu"
)
# Stops that open a window hand the keyboard to it, so they close the cursor
# first. The rest are in-place toggles and keep the mode.
click_left_opens=(0 0 1 1)

# Shift+Return. Only pulseaudio has a click-right handler in the bar.
click_right=("" "pavucontrol" "" "")
click_right_opens=(0 1 0 0)

# j/k, standing in for a scroll wheel over the module. Empty means the module
# has no scroll handler. Volume steps by 1 point rather than the 5 the wheel and
# the XF86Audio keys use: the cursor is already parked on the module here, so
# this is the fine adjustment. Brightness keeps the coarse 5.
scroll_down=("" "pactl set-sink-volume @DEFAULT_SINK@ -1%" "brightnessctl -q set 5%-" "")
scroll_up=("" "pactl set-sink-volume @DEFAULT_SINK@ +1%" "brightnessctl -q set +5%" "")

# The bar's power icon opens a menu built for the mouse. Reach the same actions
# from the keyboard through rofi, which is already this profile's launcher.
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

# Swap module <-> twin. Both bars receive the action, so they stay in step.
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

# Click the selected module. An empty action means it has no handler for that
# button, which is a no-op rather than an error.
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

close() {
  local i
  rm -f "$STATE"
  # Reset every twin, not just the selected one: a polybar restart mid-mode can
  # leave the pair out of step with the index file.
  for i in "${!modules[@]}"; do
    deselect_module "$i"
  done
}

case "${1:-}" in
  open)
    polybar_show_persistent
    printf '0\n' >"$STATE"
    for i in "${!modules[@]}"; do
      deselect_module "$i"
    done
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
