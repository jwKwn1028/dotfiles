#!/usr/bin/env bash
# Re-apply tile-snap.sh to every window marked `_snap_<region>` after the usable
# rect changes. One entry per window: the largest mark wins.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

mapfile -t entries < <(i3-msg -t get_tree | jq -r '
  def snap_size:
    if . == "_snap_full" then 4
    elif test("^_snap_(left|right|up|down)$") then 2
    elif test("^_snap_(ul|ur|dl|dr)$") then 1
    else 0
    end;
  .. | objects | select(.window? != null) |
  . as $n |
  ([(.marks? // [])[] |
      select(test("^_snap_(full|left|right|up|down|ul|ur|dl|dr)$"))]) as $marks |
  ($marks | if length == 0 then null else max_by(snap_size) end) as $m |
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
