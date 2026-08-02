#!/usr/bin/env bash
# Shared Polybar visibility, IPC, and transient-peek state helpers.
# The caller must set DIR to this configuration directory before sourcing.

. "$DIR/_snap-common.sh"

# These paths are intentionally consumed by scripts that source this file.
POLYBAR_CONTROL_LOCK="$SNAP_RUNTIME_DIR/i3-polybar-toggle.lock"
POLYBAR_PEEK_OWNER="$SNAP_RUNTIME_DIR/i3-polybar-peek.owner"
POLYBAR_PEEK_TRIGGER="$SNAP_RUNTIME_DIR/i3-polybar-peek.trigger"
POLYBAR_PEEK_HOLD="$SNAP_RUNTIME_DIR/i3-polybar-peek.hold"
POLYBAR_PEEK_WORKER_LOCK="$SNAP_RUNTIME_DIR/i3-polybar-peek-worker.lock"
export POLYBAR_CONTROL_LOCK POLYBAR_PEEK_OWNER POLYBAR_PEEK_TRIGGER
export POLYBAR_PEEK_HOLD POLYBAR_PEEK_WORKER_LOCK

mkdir -p "$SNAP_RUNTIME_DIR" 2>/dev/null || true

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

polybar_set_state() {
  local cmd="$1"
  local wanted="$2"

  polybar-msg cmd "$cmd" >/dev/null 2>&1 && return 0

  if [ "$wanted" = 1 ] && [ -x "$HOME/.config/polybar/launch.sh" ]; then
    snap_log "polybar IPC unavailable; relaunching"
    "$HOME/.config/polybar/launch.sh" >/dev/null 2>&1
    polybar-msg cmd show >/dev/null 2>&1 && return 0
  fi

  return 1
}

# Print the last observed state. Return success if it reached the requested
# state before the timeout and failure otherwise.
polybar_wait_for_state() {
  local wanted="$1"
  local attempts="${2:-80}"
  local current

  while [ "$attempts" -gt 0 ]; do
    current=$(polybar_visible_value)
    if [ "$current" = "$wanted" ]; then
      printf '%s\n' "$current"
      return 0
    fi
    sleep 0.025
    attempts=$((attempts - 1))
  done

  polybar_visible_value
  return 1
}

polybar_cancel_peek() {
  rm -f "$POLYBAR_PEEK_OWNER" "$POLYBAR_PEEK_TRIGGER" "$POLYBAR_PEEK_HOLD"
}

# Show the bar and keep it up for a binding mode, promoting a transient peek.
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
    # A peek just became persistent, so refit snapped windows once.
    "$DIR/resnap.sh"
    polybar_raise
  fi
}
