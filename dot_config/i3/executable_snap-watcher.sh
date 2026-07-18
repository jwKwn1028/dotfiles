#!/usr/bin/env bash
# Watches i3 window events:
#   - new:   auto-snap into the largest free region if the workspace already
#            has tile-snapped (floating, `_snap_*`) windows.
#   - close: when a snapped window dies, expand multiple remaining snapped
#            windows to fill freed quadrants (largest-region first).
#
# Survives i3 socket drops via a resubscribe loop, and a flock guards against
# duplicate instances spawned by `exec_always`.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

# ---------- single-instance ----------
# Wait up to 5s for the lock. The i3 config's `exec_always` line first pkills
# the old watcher and then spawns a new one; with `flock -n` the new instance
# would race and exit because the old hadn't released its fd yet. Waiting
# briefly lets SIGTERM finish the old process before we take over.
mkdir -p "$SNAP_RUNTIME_DIR" 2>/dev/null
LOCK="$SNAP_RUNTIME_DIR/i3-snap-watcher.lock"
exec 200>"$LOCK"
if ! flock -w 5 200; then
  snap_log "lock contended for >5s; exiting"
  exit 0
fi
snap_log "watcher starting (pid $$)"

# ---------- region helpers ----------

# expand_region <current_region> <other_quads>
# Find the largest region that (a) still contains all of current_region's
# quadrants and (b) doesn't overlap any quadrant in other_quads. Echoes the
# region name (possibly the same as current); empty if none fits.
expand_region() {
  local cur="$1" others="$2"
  local cur_quads r quads q includes_all conflict
  cur_quads=$(mark_to_quads "$cur")

  while read -r r; do
    quads=$(mark_to_quads "$r")
    includes_all=1
    for q in $cur_quads; do
      [[ " $quads " == *" $q "* ]] || { includes_all=0; break; }
    done
    (( includes_all )) || continue
    conflict=0
    for q in $quads; do
      [[ " $others " == *" $q "* ]] && { conflict=1; break; }
    done
    (( conflict )) || { echo "$r"; return; }
  done < <(regions_by_size)
}

# pick_fill_region <occupied_quads>
# For a NEW window arriving on a workspace with `occupied_quads` already
# claimed: pick the largest free region (preferring halves over quadrants).
pick_fill_region() {
  local occ="$1"
  local has_ul=0 has_ur=0 has_dl=0 has_dr=0 q
  for q in $occ; do
    case "$q" in
      ul) has_ul=1 ;; ur) has_ur=1 ;; dl) has_dl=1 ;; dr) has_dr=1 ;;
    esac
  done
  local total=$((has_ul + has_ur + has_dl + has_dr))
  (( total == 0 || total == 4 )) && return

  (( !has_ul && !has_dl )) && { echo "left";  return; }
  (( !has_ur && !has_dr )) && { echo "right"; return; }
  (( !has_ul && !has_ur )) && { echo "up";    return; }
  (( !has_dl && !has_dr )) && { echo "down";  return; }

  (( !has_ul )) && { echo "ul"; return; }
  (( !has_ur )) && { echo "ur"; return; }
  (( !has_dl )) && { echo "dl"; return; }
  (( !has_dr )) && { echo "dr"; return; }
}

# workspace_snap_entries <con_id>
# Emit "id region" lines for snapped windows on the target window's workspace.
# One canonical _snap_* mark is used per window so old duplicate marks cannot
# make the workspace look fuller than it really is.
workspace_snap_entries() {
  local win_id="$1"
  i3-msg -t get_tree | jq -r --argjson id "$win_id" '
    [.. | objects | select(.type? == "workspace") |
     select([.. | objects | .id?] | index($id))][0] // empty |
    [.. | objects | select((.window? // null) != null and (.id? // 0) != $id)] |
    .[] |
    .id as $cid |
    [(.marks // [])[] | select(startswith("_snap_")) | sub("^_snap_"; "")] as $snaps |
    select($snaps | length > 0) |
    "\($cid) \($snaps[0])"'
}

entries_to_quads() {
  local entries="$1"
  local id region occupied=""

  while read -r id region; do
    [ -z "${id:-}" ] && continue
    occupied="$occupied $(mark_to_quads "$region")"
  done <<<"$entries"

  echo "$occupied"
}

split_region_for_new() {
  local region="$1"

  case "$region" in
    full)  echo "left right" ;;
    left)  echo "ul dl" ;;
    right) echo "ur dr" ;;
    up)    echo "ul ur" ;;
    down)  echo "dl dr" ;;
  esac
}

make_room_for_new() {
  local win_id="$1" entries="$2"
  local sorted id region keep_region new_region pair

  sorted=$(printf '%s\n' "$entries" | while read -r id region; do
    [ -z "${id:-}" ] && continue
    printf '%d %s %s\n' "$(region_size "$region")" "$id" "$region"
  done | sort -k1,1nr -k2,2n)

  while read -r _ id region; do
    [ -z "${id:-}" ] && continue
    pair=$(split_region_for_new "$region")
    [ -z "$pair" ] && continue

    read -r keep_region new_region <<<"$pair"
    snap_log "auto-snap con_id=$win_id: split con_id=$id $region -> $keep_region, new -> $new_region"
    "$DIR/tile-snap.sh" "$keep_region" "$id"
    "$DIR/tile-snap.sh" "$new_region" "$win_id"
    return 0
  done <<<"$sorted"

  return 1
}

restore_tiling_for_workspace() {
  local win_id="$1" entries="$2"
  local id region

  snap_log "auto-snap con_id=$win_id: no snap space remains; restoring snapped windows to tiling"
  while read -r id region; do
    [ -z "${id:-}" ] && continue
    "$DIR/tile-snap.sh" unsnap "$id"
  done <<<"$entries"
  i3-msg "[con_id=$win_id] floating disable, focus" >/dev/null 2>&1
  apply_autotiling_split "$win_id"
}

# ---------- new-window handler ----------
handle_new() {
  local line="$1" win_id floating entries occupied region

  win_id=$(jq -r '.container.id // empty' <<<"$line")
  [ -z "$win_id" ] && return

  # Apply current title-bar toggle state to the new window. i3 has no runtime
  # way to set the default border, so we do it per-window here.
  if [ -f "$SNAP_TITLES_STATE" ] && [ "$(cat "$SNAP_TITLES_STATE")" = "on" ]; then
    i3-msg "[con_id=$win_id] border normal" >/dev/null 2>&1
  else
    i3-msg "[con_id=$win_id] border pixel 1" >/dev/null 2>&1
  fi

  # Skip windows that are already floating (dialogs, scratchpad, for_window rules).
  floating=$(jq -r '.container.floating // ""' <<<"$line")
  case "$floating" in
    user_on|auto_on) return ;;
  esac

  # Collect snap marks on the workspace containing this window.
  entries=$(workspace_snap_entries "$win_id")
  [ -z "$entries" ] && return
  occupied=$(entries_to_quads "$entries")

  region=$(pick_fill_region "$occupied")
  if [ -z "$region" ]; then
    make_room_for_new "$win_id" "$entries" && return
    restore_tiling_for_workspace "$win_id" "$entries"
    return
  fi

  snap_log "auto-snap con_id=$win_id -> $region (occupied:$occupied)"
  "$DIR/tile-snap.sh" "$region" "$win_id"
}

# ---------- close-window handler ----------
rebalance_workspace_snaps() {
  # Input: a sequence of "id region" lines on stdin.
  local lines sorted_lines ids=() regs=() n i j others new_region
  lines=$(cat)
  [ -z "$lines" ] && return

  # Sort by region size desc, then id asc — bigger windows get first dibs
  # on growing into the freed space.
  sorted_lines=$(printf '%s\n' "$lines" | while read -r id region; do
    [ -z "$id" ] && continue
    printf '%d %s %s\n' "$(region_size "$region")" "$id" "$region"
  done | sort -k1,1nr -k2,2n)

  while read -r _ i r; do
    [ -z "$i" ] && continue
    ids+=("$i"); regs+=("$r")
  done <<<"$sorted_lines"

  n=${#ids[@]}
  (( n == 0 )) && return

  for ((i=0; i<n; i++)); do
    others=""
    for ((j=0; j<n; j++)); do
      (( j == i )) && continue
      others+=" $(mark_to_quads "${regs[$j]}")"
    done
    new_region=$(expand_region "${regs[$i]}" "$others")
    if [ -n "$new_region" ] && [ "$new_region" != "${regs[$i]}" ]; then
      snap_log "rebalance: con_id=${ids[$i]} ${regs[$i]} -> $new_region"
      i3-msg "[con_id=${ids[$i]}] unmark _snap_${regs[$i]}" >/dev/null 2>&1
      "$DIR/tile-snap.sh" "$new_region" "${ids[$i]}"
      regs[i]="$new_region"
    fi
  done
}

handle_close() {
  local line="$1" was_snap closed_id tree ws_ids ws_id

  was_snap=$(jq -r '(.container.marks // []) | map(select(startswith("_snap_"))) | length' <<<"$line" 2>/dev/null)
  [ "${was_snap:-0}" = "0" ] && return

  closed_id=$(jq -r '.container.id // 0' <<<"$line")

  # Give i3 a beat to remove the node from the tree.
  sleep 0.05

  tree=$(i3-msg -t get_tree)
  ws_ids=$(jq -r '[.. | objects | select(.type? == "workspace")] | .[].id' <<<"$tree")

  for ws_id in $ws_ids; do
    jq -r --argjson ws "$ws_id" --argjson xid "$closed_id" '
      [.. | objects | select(.type? == "workspace" and .id == $ws)][0] // empty |
      [.. | objects | select((.id? // 0) != $xid and (.window? // null) != null)] |
      .[] |
      .id as $id |
      [(.marks // [])[] | select(startswith("_snap_")) | sub("^_snap_"; "")] as $snaps |
      select($snaps | length > 0) |
      "\($id) \($snaps[0])"' <<<"$tree" | rebalance_workspace_snaps
  done
}

# ---------- subscribe loop ----------
while true; do
  i3-msg -t subscribe -m '["window"]' 2>/dev/null | while IFS= read -r line; do
    change=$(jq -r '.change // empty' <<<"$line" 2>/dev/null) || continue
    case "$change" in
      new)   handle_new   "$line" ;;
      close) handle_close "$line" ;;
    esac
  done
  snap_log "subscription ended, reconnecting in 1s"
  sleep 1
done
