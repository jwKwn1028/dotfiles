#!/usr/bin/env bash
# Briefly show Polybar after a workspace keybinding, or hold it open for a
# standalone Super-key gesture, but only if the bar was hidden. No resnap is
# performed because a transient peek should not resize snapped windows twice.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_polybar-common.sh"

PEEK_DURATION_MS="${I3_POLYBAR_PEEK_MS:-250}"
case "$PEEK_DURATION_MS" in
  '' | *[!0-9]*) PEEK_DURATION_MS=250 ;;
esac
[ "$PEEK_DURATION_MS" -gt 0 ] || PEEK_DURATION_MS=250

now_ms() {
  date +%s%3N
}

write_trigger() {
  local tmp="$POLYBAR_PEEK_TRIGGER.$$"
  printf '%s\n' "$(now_ms)" > "$tmp"
  mv -f "$tmp" "$POLYBAR_PEEK_TRIGGER"
}

write_hold() {
  local holder_pid="$1"
  local tmp="$POLYBAR_PEEK_HOLD.$$"
  printf '%s\n' "$holder_pid" > "$tmp"
  mv -f "$tmp" "$POLYBAR_PEEK_HOLD"
}

hold_pid() {
  cat "$POLYBAR_PEEK_HOLD" 2>/dev/null || true
}

hold_is_live() {
  local holder_pid
  holder_pid=$(hold_pid)
  [[ "$holder_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$holder_pid" 2>/dev/null
}

# The caller must hold POLYBAR_CONTROL_LOCK.
hide_owned_peek() {
  local after

  if polybar_visible; then
    polybar_set_state hide 0 || true
    after=$(polybar_wait_for_state 0) || true
    snap_log "polybar peek hide 1 -> ${after:-?}"
  fi
  polybar_cancel_peek
}

run_worker() {
  local trigger now

  command -v flock > /dev/null 2>&1 || exit 0

  exec 8> "$POLYBAR_PEEK_WORKER_LOCK"
  flock -n 8 || exit 0
  exec 9> "$POLYBAR_CONTROL_LOCK"

  while [ -e "$POLYBAR_PEEK_OWNER" ]; do
    if [ -e "$POLYBAR_PEEK_HOLD" ]; then
      if hold_is_live; then
        sleep 0.05
        continue
      fi
    else
      trigger=$(cat "$POLYBAR_PEEK_TRIGGER" 2> /dev/null || true)
      if [[ "$trigger" =~ ^[0-9]+$ ]]; then
        now=$(now_ms)
        if [ $((now - trigger)) -lt "$PEEK_DURATION_MS" ]; then
          sleep 0.05
          continue
        fi
      fi
    fi

    # Serialize the final state/deadline check and hide against new peeks,
    # standalone-Super holds, and the explicit Polybar toggle.
    if ! flock -w 2 9; then
      sleep 0.05
      continue
    fi

    if [ ! -e "$POLYBAR_PEEK_OWNER" ]; then
      flock -u 9
      exit 0
    fi

    if [ -e "$POLYBAR_PEEK_HOLD" ] && hold_is_live; then
      flock -u 9
      continue
    fi

    if [ ! -e "$POLYBAR_PEEK_HOLD" ]; then
      trigger=$(cat "$POLYBAR_PEEK_TRIGGER" 2> /dev/null || true)
      now=$(now_ms)
      if [[ "$trigger" =~ ^[0-9]+$ ]] \
        && [ $((now - trigger)) -lt "$PEEK_DURATION_MS" ]; then
        flock -u 9
        continue
      fi
    fi

    hide_owned_peek
    flock -u 9
    exit 0
  done
}

start_worker() {
  if command -v setsid > /dev/null 2>&1; then
    setsid -f "$DIR/polybar-peek.sh" --worker < /dev/null > /dev/null 2>&1
  else
    nohup "$DIR/polybar-peek.sh" --worker < /dev/null > /dev/null 2>&1 &
  fi
}

trigger_peek() {
  local after requested=0 should_start=0

  command -v flock > /dev/null 2>&1 || {
    snap_log "polybar peek skipped: flock unavailable"
    return 0
  }

  exec 9> "$POLYBAR_CONTROL_LOCK"
  flock -w 2 9 || {
    snap_log "polybar peek skipped: control lock busy"
    return 0
  }

  if [ -e "$POLYBAR_PEEK_OWNER" ]; then
    if polybar_visible; then
      rm -f "$POLYBAR_PEEK_HOLD"
      write_trigger
      polybar_raise
      should_start=1
    else
      # The bar was changed outside this helper; discard stale ownership and
      # treat this keypress as a fresh hidden-state peek.
      polybar_cancel_peek
    fi
  fi

  if [ "$should_start" = 0 ]; then
    if polybar_visible; then
      # It was already visible and therefore is not ours to hide.
      flock -u 9
      exec 9>&-
      return 0
    fi

    if polybar_set_state show 1; then
      requested=1
    fi
    after=$(polybar_wait_for_state 1) || true

    if [ "$requested" = 1 ] || [ "$after" = 1 ]; then
      : > "$POLYBAR_PEEK_OWNER"
      rm -f "$POLYBAR_PEEK_HOLD"
      write_trigger
      should_start=1
      [ "$after" = 1 ] && polybar_raise
      snap_log "polybar peek show 0 -> ${after:-?}"
    fi
  fi

  flock -u 9
  exec 9>&-

  if [ "$should_start" = 1 ]; then
    start_worker
  fi

  return 0
}

start_hold() {
  local holder_pid="$1"
  local after requested=0 should_start=0

  [[ "$holder_pid" =~ ^[1-9][0-9]*$ ]] || return 2
  command -v flock >/dev/null 2>&1 || return 0

  exec 9>"$POLYBAR_CONTROL_LOCK"
  flock -w 2 9 || return 0

  if [ -e "$POLYBAR_PEEK_OWNER" ]; then
    if polybar_visible; then
      rm -f "$POLYBAR_PEEK_TRIGGER"
      write_hold "$holder_pid"
      polybar_raise
      should_start=1
    else
      polybar_cancel_peek
    fi
  fi

  if [ "$should_start" = 0 ]; then
    if polybar_visible; then
      flock -u 9
      exec 9>&-
      return 0
    fi

    if polybar_set_state show 1; then
      requested=1
    fi
    after=$(polybar_wait_for_state 1) || true

    if [ "$requested" = 1 ] || [ "$after" = 1 ]; then
      : > "$POLYBAR_PEEK_OWNER"
      rm -f "$POLYBAR_PEEK_TRIGGER"
      write_hold "$holder_pid"
      should_start=1
      [ "$after" = 1 ] && polybar_raise
      snap_log "polybar Super hold show 0 -> ${after:-?}"
    fi
  fi

  flock -u 9
  exec 9>&-
  [ "$should_start" = 1 ] && start_worker
  return 0
}

end_hold() {
  local holder_pid="$1"
  local current

  [[ "$holder_pid" =~ ^[1-9][0-9]*$ ]] || return 2
  command -v flock >/dev/null 2>&1 || return 0

  exec 9>"$POLYBAR_CONTROL_LOCK"
  flock -w 2 9 || return 0

  current=$(hold_pid)
  if [ "$current" = "$holder_pid" ]; then
    hide_owned_peek
  fi

  flock -u 9
  exec 9>&-
}

cancel_hold() {
  local holder_pid="$1"
  local current should_start=0

  [[ "$holder_pid" =~ ^[1-9][0-9]*$ ]] || return 2
  command -v flock >/dev/null 2>&1 || return 0

  exec 9>"$POLYBAR_CONTROL_LOCK"
  flock -w 2 9 || return 0

  current=$(hold_pid)
  if [ "$current" = "$holder_pid" ]; then
    if [ -e "$POLYBAR_PEEK_OWNER" ] && polybar_visible; then
      rm -f "$POLYBAR_PEEK_HOLD"
      write_trigger
      should_start=1
    else
      polybar_cancel_peek
    fi
  fi

  flock -u 9
  exec 9>&-
  [ "$should_start" = 1 ] && start_worker
}

case "${1:-}" in
  "")
    trigger_peek
    ;;
  --worker)
    run_worker
    ;;
  --hold-start)
    start_hold "${2:-}"
    ;;
  --hold-end)
    end_hold "${2:-}"
    ;;
  --hold-cancel)
    cancel_hold "${2:-}"
    ;;
  *)
    exit 2
    ;;
esac
