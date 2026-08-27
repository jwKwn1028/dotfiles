#!/usr/bin/env bash
# Keyboard cursor over Polybar's own modules: Super+B, then h/l to move, j/k to
# adjust, Return to click, Shift+Return to right-click. Sticky -- only a stop
# that opens a window leaves the mode.
#
# Polybar never takes keyboard focus, so the cursor lives in the calling i3 mode.
# The highlight is a hidden twin module swapped in over IPC (see config.ini),
# except the tray: its XEmbed windows are not polybar's, so bar-nav-marker.py
# paints a block instead, matched on geometry rather than the window tree.
#
# Runtime state: .idx cursor position; .restore-hidden, written only when the bar
# was not already persistent; .marker, "x y width height" for the tray block.
#
# The parallel arrays below are indexed by stop, left to right; empty action =
# no-op, `*_opens = 1` takes the keyboard so the mode exits first. Easy to break:
# power_menu must deselect its stop first, close() must clear .marker before .idx
# and reset every pair, and a bar up only for a transient peek counts as hidden.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

STATE="$SNAP_RUNTIME_DIR/i3-polybar-nav.idx"
RESTORE_HIDDEN="$SNAP_RUNTIME_DIR/i3-polybar-nav.restore-hidden"
MARKER="$SNAP_RUNTIME_DIR/i3-polybar-nav.marker"

modules=(date pulseaudio battery wifi bluetooth powermenu)
tray_class=("" "" "" "Nm-applet" "Blueman-tray" "")

click_left=(
  "date_toggle"
  "pactl set-sink-mute @DEFAULT_SINK@ toggle"
  "xfce4-power-manager-settings"
  "tray_click 1"
  "tray_click 1"
  "power_menu"
)
click_left_opens=(0 0 1 0 0 0)

click_right=("thunderbird -mail" "pavucontrol" "" "tray_click 3" "tray_click 3" "")
click_right_opens=(1 1 0 0 0 0)

scroll_down=("" "pactl set-sink-volume @DEFAULT_SINK@ -1%" "brightnessctl -q set 5%-" "" "" "")
scroll_up=("" "pactl set-sink-volume @DEFAULT_SINK@ +1%" "brightnessctl -q set +5%" "" "" "")

power_menu() {
  deselect_module "$(current_index)"
  ipc powermenu open.0
}

menu_close_all() {
  ipc powermenu close
  ipc powermenu-sel close
}

ipc() {
  polybar-msg action "#$1.$2" >/dev/null 2>&1 || true
}

date_toggle() {
  ipc date toggle
  ipc date-sel toggle
}

tray_window() {
  local win info width height
  for win in $(xdotool search --class "^$1$" 2>/dev/null); do
    info=$(xwininfo -id "$win" 2>/dev/null) || continue
    [[ "$info" == *"IsViewable"* ]] || continue
    width=$(awk '$1 == "Width:" { print $2 }' <<<"$info")
    height=$(awk '$1 == "Height:" { print $2 }' <<<"$info")
    if [ "${width:-0}" -le 10 ] || [ "${width:-0}" -gt 64 ]; then continue; fi
    if [ "${height:-0}" -le 10 ] || [ "${height:-0}" -gt 64 ]; then continue; fi
    printf '%s\n' "$win"
    return 0
  done
  notify-send "$1" "$1 tray icon is unavailable"
  return 1
}

window_rect() {
  xwininfo -id "$1" 2>/dev/null |
    awk '$1 == "Absolute" && $3 == "X:" { x = $4 }
         $1 == "Absolute" && $3 == "Y:" { y = $4 }
         $1 == "Width:"  { w = $2 }
         $1 == "Height:" { h = $2 }
         /IsViewable/    { mapped = 1 }
         END { if (mapped && h != "") print x, y, w, h }' | grep .
}

bar_rect_at() {
  local win rect bar_x bar_w
  for win in $(polybar_windows); do
    rect=$(window_rect "$win") || continue
    read -r bar_x _ bar_w _ <<<"$rect"
    [ "$1" -ge "$bar_x" ] && [ "$1" -lt "$((bar_x + bar_w))" ] || continue
    printf '%s\n' "$rect"
    return 0
  done
  return 1
}

mark_tray() {
  local win icon_x icon_w bar_y bar_h
  win=$(tray_window "$1") || return 1
  read -r icon_x _ icon_w _ <<<"$(window_rect "$win")"
  read -r _ bar_y _ bar_h <<<"$(bar_rect_at "$icon_x")"
  [ -n "${bar_h:-}" ] || return 1
  printf '%s %s %s %s\n' "$icon_x" "$bar_y" "$icon_w" "$bar_h" >"$MARKER"
}

tray_click() {
  local win width height
  win=$(tray_window "${tray_class[$(current_index)]}") || return 1
  read -r _ _ width height <<<"$(window_rect "$win")"
  xdotool mousemove --sync --window "$win" \
    "$((width / 2))" "$((height / 2))" >/dev/null 2>&1 &&
    xdotool click "$1" >/dev/null 2>&1
  close
  i3-msg 'mode "default"' >/dev/null 2>&1 || true
}

select_module() {
  if [ -n "${tray_class[$1]}" ]; then
    mark_tray "${tray_class[$1]}"
    return 0
  fi
  ipc "${modules[$1]}" module_hide
  ipc "${modules[$1]}-sel" module_show
}

deselect_module() {
  if [ -n "${tray_class[$1]}" ]; then
    : >"$MARKER"
    return 0
  fi
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

reset_pairs() {
  local i
  for i in "${!modules[@]}"; do
    [ "$i" = "${1:-}" ] || deselect_module "$i"
  done
}

close() {
  : >"$MARKER"
  rm -f "$STATE"
  menu_close_all
  reset_pairs

  if [ -e "$RESTORE_HIDDEN" ]; then
    rm -f "$RESTORE_HIDDEN"
    if polybar_visible; then
      "$DIR/toggle-polybar-resnap.sh"
    fi
  fi
  return 0
}

case "${1:-}" in
  open)
    if polybar_visible && [ ! -e "$POLYBAR_PEEK_OWNER" ]; then
      rm -f "$RESTORE_HIDDEN"
    else
      : >"$RESTORE_HIDDEN"
    fi
    polybar_show_persistent
    : >"$MARKER"
    printf '0\n' >"$STATE"
    setsid -f flock -n "$MARKER.lock" "$DIR/bar-nav-marker.py" \
      "$STATE" "$MARKER" >/dev/null 2>&1
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
