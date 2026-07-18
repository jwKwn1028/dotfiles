#!/usr/bin/env bash
# Re-applies tile-snap.sh to every window currently marked `_snap_<region>`.
# Called after toggle-titles.sh or `polybar-msg cmd toggle` so snapped
# windows re-fit the workspace's new usable rect / border state. Each window
# is re-snapped concurrently — tile-snap targets disjoint windows so there
# is no cross-window contention.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

# One entry per window (not per mark). If a window has stale duplicate
# _snap_* marks from before tile-snap learned to strip them, pick the first
# one; tile-snap will then unmark the rest as part of re-snapping.
mapfile -t entries < <(i3-msg -t get_tree | jq -r '
  .. | objects | select(.window? != null) |
  . as $n |
  ([(.marks? // [])[] | select(startswith("_snap_"))][0]) as $m |
  select($m != null) |
  "\($n.id) \($m | sub("^_snap_"; ""))"')

if [ "${#entries[@]}" -eq 0 ]; then
  snap_log "resnap: no snapped windows"
  exit 0
fi

snap_log "resnap: ${#entries[@]} window(s)"

for e in "${entries[@]}"; do
  [ -z "$e" ] && continue
  id="${e%% *}"
  region="${e##* }"
  {
    i3-msg "[con_id=$id] unmark _snap_$region" >/dev/null 2>&1
    "$DIR/tile-snap.sh" "$region" "$id"
  } &
done
wait
