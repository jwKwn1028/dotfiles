#!/usr/bin/env bash
# Keyboard cursor over Polybar's own modules: Super+I, then h/l to move, j/k to
# adjust, Return to click, Shift+Return to right-click.
#
# Polybar never takes keyboard focus, so the cursor lives in the i3 mode that
# calls this script, and the highlight is a hidden twin module swapped in over
# IPC (see config.ini) -- except on the tray, whose block bar-nav-marker.py
# paints. The mode is sticky: only a stop that opens a window leaves it, so
# toggles can be nudged repeatedly.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

STATE="$SNAP_RUNTIME_DIR/i3-polybar-nav.idx"
# Present if the bar was not already staying visible when the mode opened, so
# leaving can put it back and never strand a hidden bar on screen.
RESTORE_HIDDEN="$SNAP_RUNTIME_DIR/i3-polybar-nav.restore-hidden"
# "x y width height" of the block over the selected tray icon, or empty for no
# block. bar-nav-marker.py owns the window; this file is how it is aimed.
MARKER="$SNAP_RUNTIME_DIR/i3-polybar-nav.marker"

# Cursor stops, left to right.
modules=(date pulseaudio battery wifi bluetooth powermenu)
# Tray stops, by the window class of the applet that owns the icon. Polybar
# cannot give these a `-sel` twin: the tray is one module holding XEmbed windows
# it does not own, so bar-nav-marker.py paints their block instead.
tray_class=("" "" "" "Nm-applet" "Blueman-tray" "")

# Return. Mirrors each module's click-left handler. date_toggle drives both
# halves of the pair: the action is module state, and the plain half is the
# hidden one while the cursor sits on it.
click_left=(
  "date_toggle"
  "pactl set-sink-mute @DEFAULT_SINK@ toggle"
  "xfce4-power-manager-settings"
  "tray_click 1"
  "tray_click 1"
  "power_menu"
)
# 1 = opens a window, which takes the keyboard, so the cursor closes first.
click_left_opens=(0 0 1 0 0 0)

# Shift+Return. Beyond pulseaudio, the two applets have their own right-click
# menus -- nm-applet's networking toggles, blueman's send/setup entries -- which
# nothing else in this profile reaches by keyboard.
click_right=("" "pavucontrol" "" "tray_click 3" "tray_click 3" "")
click_right_opens=(0 1 0 0 0 0)

# j/k, standing in for a scroll wheel; empty means no scroll handler. Volume
# steps by 1 rather than the wheel's 5 -- parking the cursor on the module is
# the fine adjustment. Brightness keeps the coarse 5.
scroll_down=("" "pactl set-sink-volume @DEFAULT_SINK@ -1%" "brightnessctl -q set 5%-" "" "" "")
scroll_up=("" "pactl set-sink-volume @DEFAULT_SINK@ +1%" "brightnessctl -q set +5%" "" "" "")

# Return on the power stop, doing what a mouse click on the icon does: expand
# the bar's own menu. Its entries live inside the one `custom/menu` module, so no
# cursor stop can reach them and the mouse picks from here -- an i3 mode grabs
# the keyboard, not the pointer. The mode stays up so Escape can put the bar back
# the way it was, menu and all.
#
# Hand the stop back to its plain half first. The block stands for a cursor that
# can no longer move within the menu, and it would sit over the open entries as
# one unbroken wash. Moving on and back off re-selects the stop as usual.
power_menu() {
  deselect_module "$(current_index)"
  ipc powermenu open.0
}

# Collapse the power menu on both halves of the pair: whichever is on screen
# owns the open menu, and that swaps as the cursor moves on and off the stop.
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

# The window id of a class's tray icon. The applet also owns invisible 10x10
# helper windows and its own popup, so only a mapped, tray-sized one is it.
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

# "x y width height" of a mapped window, in root coordinates.
window_rect() {
  xwininfo -id "$1" 2>/dev/null |
    awk '$1 == "Absolute" && $3 == "X:" { x = $4 }
         $1 == "Absolute" && $3 == "Y:" { y = $4 }
         $1 == "Width:"  { w = $2 }
         $1 == "Height:" { h = $2 }
         /IsViewable/    { mapped = 1 }
         END { if (mapped && h != "") print x, y, w, h }' | grep .
}

# The bar holding the icon at column $1. An icon's parent is Polybar's own tray
# container rather than the bar, so match on geometry instead of the tree.
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

# Aim the block at a tray icon. It spans the bar like every other stop's block,
# rather than hugging the icon, so the two read as the same cursor.
mark_tray() {
  local win icon_x icon_w bar_y bar_h
  win=$(tray_window "$1") || return 1
  read -r icon_x _ icon_w _ <<<"$(window_rect "$win")"
  read -r _ bar_y _ bar_h <<<"$(bar_rect_at "$icon_x")"
  [ -n "${bar_h:-}" ] || return 1
  # The icon's own column, full bar height. `tray-spacing = 0` keeps that from
  # leaving a gap the block cannot reach.
  printf '%s %s %s %s\n' "$icon_x" "$bar_y" "$icon_w" "$bar_h" >"$MARKER"
}

# Return and Shift+Return on a tray stop. Polybar's click handlers cannot reach
# an icon it does not own, so this is the mouse's own gesture: move onto the
# icon and press button $1. Either menu outlives bar mode, so leave the mode and
# put the bar back.
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

# Swap module <-> twin. Every bar receives the action, so they stay in step.
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
  # The block first: bar-nav-marker.py stops when the state file goes, so
  # clearing it afterwards could leave the last block painted on the bar.
  : >"$MARKER"
  rm -f "$STATE"
  # An expanded power menu is mode state too: leaving has to put the bar back
  # exactly as Super+I found it, not strand the menu open.
  menu_close_all
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
    : >"$MARKER"
    printf '0\n' >"$STATE"
    # One painter per mode. flock makes a second Super+I reuse the running one
    # instead of stacking a second block on the bar.
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
