#!/usr/bin/env bash
# Briefly show Polybar after a workspace keybinding, but only if the bar was
# hidden. Repeated invocations extend one timer. No resnap is performed because
# a transient peek should not make snapped windows resize twice.

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

run_worker() {
  local trigger now after

  command -v flock > /dev/null 2>&1 || exit 0

  exec 8> "$POLYBAR_PEEK_WORKER_LOCK"
  flock -n 8 || exit 0
  exec 9> "$POLYBAR_CONTROL_LOCK"

  while [ -e "$POLYBAR_PEEK_OWNER" ]; do
    trigger=$(cat "$POLYBAR_PEEK_TRIGGER" 2> /dev/null || true)
    case "$trigger" in
      '' | *[!0-9]*)
        polybar_cancel_peek
        exit 0
        ;;
    esac

    now=$(now_ms)
    if [ $((now - trigger)) -lt "$PEEK_DURATION_MS" ]; then
      sleep 0.05
      continue
    fi

    # Serialize the final deadline check and hide against both new peeks and
    # the explicit Polybar toggle.
    if ! flock -w 2 9; then
      sleep 0.05
      continue
    fi

    if [ ! -e "$POLYBAR_PEEK_OWNER" ]; then
      flock -u 9
      exit 0
    fi

    trigger=$(cat "$POLYBAR_PEEK_TRIGGER" 2> /dev/null || true)
    now=$(now_ms)
    if [[ "$trigger" =~ ^[0-9]+$ ]] \
      && [ $((now - trigger)) -lt "$PEEK_DURATION_MS" ]; then
      flock -u 9
      continue
    fi

    if polybar_visible; then
      polybar_set_state hide 0 || true
      after=$(polybar_wait_for_state 0) || true
      snap_log "polybar peek hide 1 -> ${after:-?}"
    fi

    polybar_cancel_peek
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

if [ "${1:-}" = "--worker" ]; then
  run_worker
else
  trigger_peek
fi
