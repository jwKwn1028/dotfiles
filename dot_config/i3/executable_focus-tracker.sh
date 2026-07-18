#!/usr/bin/env bash
# Subscribe to i3 window-focus events and persist last-2 con_ids to
# $XDG_RUNTIME_DIR/i3-focus-history (line 1: current, line 2: previous).
# Runs as a long-lived background process started from i3 autostart.

set -u

DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

mkdir -p "$SNAP_RUNTIME_DIR" 2>/dev/null || exit 0

LOCK="$SNAP_RUNTIME_DIR/i3-focus-tracker.lock"
exec 200>"$LOCK"
if ! flock -w 5 200; then
  snap_log "focus tracker lock contended for >5s; exiting"
  exit 0
fi

write_history() {
  local curr="$1" prev="${2:-}" tmp

  tmp="$SNAP_FOCUS_HISTORY.$$"
  printf '%s\n%s\n' "$curr" "$prev" > "$tmp" && mv "$tmp" "$SNAP_FOCUS_HISTORY"
}

seed_history() {
  local live old_curr old_prev

  live=$(i3-msg -t get_tree 2>/dev/null \
    | jq -r '[.. | objects | select(.focused? == true and .window? != null)][0].id // empty' 2>/dev/null)
  [[ "$live" =~ ^[0-9]+$ ]] || return 1

  old_curr=$(sed -n '1p' "$SNAP_FOCUS_HISTORY" 2>/dev/null || true)
  old_prev=$(sed -n '2p' "$SNAP_FOCUS_HISTORY" 2>/dev/null || true)

  CURR="$live"
  if [[ "$old_curr" =~ ^[0-9]+$ && "$old_curr" != "$CURR" ]]; then
    PREV="$old_curr"
  elif [[ "$old_prev" =~ ^[0-9]+$ ]]; then
    PREV="$old_prev"
  else
    PREV=""
  fi

  write_history "$CURR" "$PREV"
}

CURR=""
PREV=""
snap_log "focus tracker starting (pid $$)"

while true; do
  seed_history || true

  while IFS= read -r line; do
    change=$(jq -r '.change // empty' <<<"$line" 2>/dev/null) || continue
    [ "$change" = "focus" ] || continue

    NEW=$(jq -r '.container.id // empty' <<<"$line" 2>/dev/null)
    [[ "$NEW" =~ ^[0-9]+$ ]] || continue
    [ "$NEW" = "${CURR:-}" ] && continue

    PREV="${CURR:-}"
    CURR="$NEW"
    write_history "$CURR" "$PREV"
  done < <(i3-msg -t subscribe -m '["window"]' 2>/dev/null)

  snap_log "focus tracker subscription ended, reconnecting in 1s"
  sleep 1
done
