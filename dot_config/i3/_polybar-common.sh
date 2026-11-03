#!/usr/bin/env bash
# Shared Polybar visibility, IPC, and transient-peek helpers. Caller must set DIR
# to this configuration directory before sourcing.

. "$DIR/_snap-common.sh"

POLYBAR_CONTROL_LOCK="$SNAP_RUNTIME_DIR/i3-polybar-toggle.lock"
POLYBAR_PEEK_OWNER="$SNAP_RUNTIME_DIR/i3-polybar-peek.owner"
POLYBAR_PEEK_TRIGGER="$SNAP_RUNTIME_DIR/i3-polybar-peek.trigger"
POLYBAR_PEEK_HOLD="$SNAP_RUNTIME_DIR/i3-polybar-peek.hold"
POLYBAR_PEEK_WORKER_LOCK="$SNAP_RUNTIME_DIR/i3-polybar-peek-worker.lock"
POLYBAR_SETTLE_MS="${I3_POLYBAR_SETTLE_MS:-200}"
I3_SYSTEM_PYTHON="${I3_SYSTEM_PYTHON:-/usr/bin/python3}"
export POLYBAR_CONTROL_LOCK POLYBAR_PEEK_OWNER POLYBAR_PEEK_TRIGGER
export POLYBAR_PEEK_HOLD POLYBAR_PEEK_WORKER_LOCK

[ -d "$SNAP_RUNTIME_DIR" ] || mkdir -p "$SNAP_RUNTIME_DIR" 2>/dev/null || true

now_ms() {
  local now=${EPOCHREALTIME//[!0-9]/}
  [ -n "$now" ] || { date +%s%3N; return; }
  printf '%s\n' "${now:0:-3}"
}

# Bar window ids, looked up again whenever visibility is set: bars can be relaunched.
POLYBAR_WINDOW_IDS=
POLYBAR_WINDOWS_KNOWN=0

polybar_find_windows() {
  [ "$POLYBAR_WINDOWS_KNOWN" = 1 ] && return 0
  POLYBAR_WINDOW_IDS=$(xdotool search --class '^[Pp]olybar$' 2>/dev/null || true)
  POLYBAR_WINDOWS_KNOWN=1
}

polybar_windows() {
  polybar_find_windows
  [ -z "$POLYBAR_WINDOW_IDS" ] || printf '%s\n' "$POLYBAR_WINDOW_IDS"
}

polybar_window_viewable() {
  local info
  info=$(xwininfo -id "$1" 2>/dev/null) || return 1
  [[ "$info" == *"IsViewable"* ]]
}

polybar_visible() {
  local win
  polybar_find_windows
  for win in $POLYBAR_WINDOW_IDS; do
    polybar_window_viewable "$win" && return 0
  done
  return 1
}

polybar_visible_value() {
  if polybar_visible; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

polybar_raise() {
  local win
  polybar_find_windows
  for win in $POLYBAR_WINDOW_IDS; do
    polybar_window_viewable "$win" || continue
    xdotool windowraise "$win" >/dev/null 2>&1 || true
  done
}

# Drop any bar i3 still manages as a dock once the bar should be hidden: i3
# unmaps a fullscreened output's dock itself, so polybar's own hide emits no
# UnmapNotify and it no-ops every later hide until reload.
polybar_withdraw_orphan_docks() {
  local -a orphans=()
  local win info

  polybar_find_windows
  for win in $POLYBAR_WINDOW_IDS; do
    # Only the Parent line: -tree also names the root.
    info=$(xwininfo -id "$win" -tree 2>/dev/null |
      sed -n 's/^ *Parent window id: *//p') || continue
    [ -z "$info" ] && continue
    [[ "$info" == *"(the root window)"* ]] && continue
    orphans+=("$win")
  done

  [ "${#orphans[@]}" -gt 0 ] || return 0
  [ -x "$I3_SYSTEM_PYTHON" ] || return 0

  "$I3_SYSTEM_PYTHON" - "${orphans[@]}" <<'PY' 2>/dev/null || return 1
import sys

from Xlib import X, display, protocol

d = display.Display()
root = d.screen().root
for wid in (int(arg) for arg in sys.argv[1:]):
    window = d.create_resource_object("window", wid)
    window.unmap()
    root.send_event(
        protocol.event.UnmapNotify(event=root, window=window, from_configure=False),
        event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask,
    )
d.flush()
PY

  snap_log "polybar withdrew ${#orphans[@]} dock(s) i3 still held"
}

polybar_set_state() {
  local cmd="$1"
  local wanted="$2"

  POLYBAR_WINDOWS_KNOWN=0
  polybar_find_windows
  if polybar-msg cmd "$cmd" >/dev/null 2>&1; then
    # Let the hide land: until polybar unmaps, the bar still looks reparented.
    if [ "$wanted" = 0 ]; then
      polybar_wait_for_state 0 "$POLYBAR_SETTLE_MS" >/dev/null
      polybar_withdraw_orphan_docks
    fi
    return 0
  fi

  if [ "$wanted" = 1 ] && [ -x "$HOME/.config/polybar/launch.sh" ]; then
    snap_log "polybar IPC unavailable; relaunching"
    "$HOME/.config/polybar/launch.sh" >/dev/null 2>&1
    POLYBAR_WINDOWS_KNOWN=0
    polybar_find_windows
    polybar-msg cmd show >/dev/null 2>&1 && return 0
  fi

  return 1
}

polybar_wait_for_state() {
  local wanted="$1"
  local budget_ms="${2:-800}"
  local deadline current

  polybar_find_windows
  deadline=$(( $(now_ms) + budget_ms ))
  while :; do
    current=$(polybar_visible_value)
    [ "$current" = "$wanted" ] && break
    [ "$(now_ms)" -ge "$deadline" ] && break
    sleep 0.025
  done

  printf '%s\n' "$current"
  [ "$current" = "$wanted" ]
}

polybar_cancel_peek() {
  rm -f "$POLYBAR_PEEK_OWNER" "$POLYBAR_PEEK_TRIGGER" "$POLYBAR_PEEK_HOLD"
}

polybar_show_persistent() {
  local peek_was_active=0

  if command -v flock >/dev/null 2>&1; then
    exec 8>"$POLYBAR_CONTROL_LOCK"
    if flock -w 2 8; then
      [ -e "$POLYBAR_PEEK_OWNER" ] && peek_was_active=1
      polybar_cancel_peek
      flock -u 8
    fi
    exec 8>&-
  fi

  if ! polybar_visible; then
    "$DIR/toggle-polybar-resnap.sh"
  elif [ "$peek_was_active" = 1 ]; then
    "$DIR/resnap.sh"
    polybar_raise
  fi
}
