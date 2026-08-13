#!/usr/bin/env bash
# Shared Polybar visibility, IPC, and transient-peek state helpers.
# The caller must set DIR to this configuration directory before sourcing.
# The paths defined here are deliberately consumed by the scripts that source it.
#
# polybar_wait_state prints the last observed state, succeeding only if the bar
# reached the requested one before the deadline. That budget is wall clock and
# short on purpose: polybar applies a visibility command on receipt, so a state
# that has not landed within a fraction of a second is unreachable, not slow --
# i3 unmaps a fullscreened output's dock and polybar cannot override it
# ("Ignoring restack of i3 window (not needed when `override-redirect =
# false`)"). The caller holds POLYBAR_CONTROL_LOCK across the wait while every
# other entry point gives up on that lock after two seconds, so a longer budget
# only drops the user's next keypresses and peeks.
#
# polybar_show_persistent shows the bar and keeps it up for a binding mode,
# promoting a transient peek.

. "$DIR/_snap-common.sh"

POLYBAR_CONTROL_LOCK="$SNAP_RUNTIME_DIR/i3-polybar-toggle.lock"
POLYBAR_PEEK_OWNER="$SNAP_RUNTIME_DIR/i3-polybar-peek.owner"
POLYBAR_PEEK_TRIGGER="$SNAP_RUNTIME_DIR/i3-polybar-peek.trigger"
POLYBAR_PEEK_HOLD="$SNAP_RUNTIME_DIR/i3-polybar-peek.hold"
POLYBAR_PEEK_WORKER_LOCK="$SNAP_RUNTIME_DIR/i3-polybar-peek-worker.lock"
POLYBAR_SETTLE_MS="${I3_POLYBAR_SETTLE_MS:-200}"
export POLYBAR_CONTROL_LOCK POLYBAR_PEEK_OWNER POLYBAR_PEEK_TRIGGER
export POLYBAR_PEEK_HOLD POLYBAR_PEEK_WORKER_LOCK

mkdir -p "$SNAP_RUNTIME_DIR" 2>/dev/null || true

now_ms() {
  date +%s%3N
}

polybar_windows() {
  xdotool search --class '^[Pp]olybar$' 2>/dev/null || true
}

polybar_window_viewable() {
  local info
  info=$(xwininfo -id "$1" 2>/dev/null) || return 1
  [[ "$info" == *"IsViewable"* ]]
}

polybar_visible() {
  local win
  for win in $(polybar_windows); do
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
  for win in $(polybar_windows); do
    polybar_window_viewable "$win" || continue
    xdotool windowraise "$win" >/dev/null 2>&1 || true
  done
}

# Drop any bar i3 still manages as a dock once the bar is meant to be hidden.
#
# i3 unmaps a fullscreened output's dock itself, so polybar's hide finds the
# window already unmapped, no UnmapNotify is emitted, and i3 maps the dock back
# when fullscreen ends -- while polybar, believing it hidden, no-ops every later
# hide until i3 is reloaded. ICCCM's synthetic UnmapNotify is the withdraw i3
# never saw; sent while the bar is hidden, nothing flashes back and polybar
# re-maps normally on the next show. Reparented means i3 holds it, so an
# ordinary hide never reaches python at all.
polybar_withdraw_orphan_docks() {
  local -a orphans=()
  local win info

  for win in $(polybar_windows); do
    # Only the Parent line: -tree also names the root as every window's root.
    info=$(xwininfo -id "$win" -tree 2>/dev/null |
      sed -n 's/^ *Parent window id: *//p') || continue
    [ -z "$info" ] && continue
    [[ "$info" == *"(the root window)"* ]] && continue
    orphans+=("$win")
  done

  [ "${#orphans[@]}" -gt 0 ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0

  python3 - "${orphans[@]}" <<'PY' 2>/dev/null || return 1
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

  if polybar-msg cmd "$cmd" >/dev/null 2>&1; then
    # Let the hide land first: until polybar unmaps, a bar it is about to
    # release still looks reparented.
    if [ "$wanted" = 0 ]; then
      polybar_wait_for_state 0 "$POLYBAR_SETTLE_MS" >/dev/null
      polybar_withdraw_orphan_docks
    fi
    return 0
  fi

  if [ "$wanted" = 1 ] && [ -x "$HOME/.config/polybar/launch.sh" ]; then
    snap_log "polybar IPC unavailable; relaunching"
    "$HOME/.config/polybar/launch.sh" >/dev/null 2>&1
    polybar-msg cmd show >/dev/null 2>&1 && return 0
  fi

  return 1
}

polybar_wait_for_state() {
  local wanted="$1"
  local budget_ms="${2:-800}"
  local deadline current

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
