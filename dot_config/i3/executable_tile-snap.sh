#!/usr/bin/env bash
# Snap a window to a region of its workspace (XFWM-style). Window becomes
# floating in that rect and gets a `_snap_<region>` mark so snap-watcher.sh
# can see which quadrants are occupied. The first snap also captures the
# original geometry in a `_presnap_<x>_<y>_<w>_<h>_<floating>` mark. Tiled
# windows also get temporary parent/sibling anchor marks so `unsnap` can put
# them back near their original tree slot instead of relying on i3's default
# unfloat insertion point.
#
# Usage: tile-snap.sh <region> [con_id]
#   region: left|right|up|down|ul|ur|dl|dr|full|unsnap
#   con_id: optional. If given, target that container; otherwise focused.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

REGION="$1"
TARGET="${2:-}"

mark_exists() {
  local mark="$1"
  i3-msg -t get_tree | jq -e --arg mark "$mark" '
    any(.. | objects; ((.marks // []) | index($mark)) != null)
  ' >/dev/null 2>&1
}

con_exists() {
  local con_id="$1"
  i3-msg -t get_tree | jq -e --argjson id "$con_id" '
    any(.. | objects; .id? == $id)
  ' >/dev/null 2>&1
}

split_cmd_for_layout() {
  case "$1" in
    splith) printf '%s\n' "split h" ;;
    splitv) printf '%s\n' "split v" ;;
    *) return 1 ;;
  esac
}

cleanup_tiling_restore_marks() {
  local target="$1" mark

  for mark in "_snap_parent_$target" "_snap_prev_$target" "_snap_next_$target"; do
    i3-msg "[con_mark=\"^$mark$\"] unmark $mark" >/dev/null 2>&1
  done
}

restore_tiled_presnap() {
  local target="$1" tiling_mark="$2"
  local parent layout prev next anchor parent_anchor side split_cmd parent_alive

  [ -n "$tiling_mark" ] || return 1
  IFS=_ read -r _ _ parent layout prev next <<<"$tiling_mark"
  if ! [[ "${parent:-}" =~ ^[0-9]+$ && "${prev:-}" =~ ^[0-9]+$ && "${next:-}" =~ ^[0-9]+$ ]]; then
    snap_log "unsnap $target: malformed tiling mark '$tiling_mark'"
    return 1
  fi

  anchor=""
  parent_anchor="_snap_parent_$target"
  side=""
  if [ "${prev:-0}" != "0" ] && mark_exists "_snap_prev_$target"; then
    anchor="_snap_prev_$target"
    side="after-prev"
  elif [ "${next:-0}" != "0" ] && mark_exists "_snap_next_$target"; then
    anchor="_snap_next_$target"
    side="before-next"
  else
    snap_log "unsnap $target: no tiling restore anchor remains"
    return 1
  fi

  parent_alive=0
  if [ "${parent:-0}" != "0" ] && con_exists "$parent"; then
    parent_alive=1
  fi

  if [ "$parent_alive" = "1" ] && mark_exists "$parent_anchor"; then
    i3-msg "[con_mark=\"^$anchor$\"] focus" >/dev/null 2>&1
    i3-msg "[con_id=$target] floating disable, focus" >/dev/null
    sleep 0.03
    i3-msg "[con_id=$target] move container to mark $parent_anchor" >/dev/null 2>&1 || return 1
    if [ "$side" = "before-next" ]; then
      i3-msg "[con_id=$target] swap container with mark $anchor" >/dev/null 2>&1 || return 1
    fi
    snap_log "unsnap $target: restored tiled slot via parent/$side (parent=$parent layout=$layout)"
    return 0
  fi

  if [ "$parent_alive" = "0" ] && split_cmd=$(split_cmd_for_layout "$layout"); then
    i3-msg "[con_mark=\"^$anchor$\"] $split_cmd" >/dev/null 2>&1
  fi

  i3-msg "[con_id=$target] floating disable, focus" >/dev/null
  sleep 0.03
  i3-msg "[con_id=$target] move container to mark $anchor" >/dev/null 2>&1 || return 1

  if [ "$side" = "before-next" ]; then
    i3-msg "[con_id=$target] swap container with mark $anchor" >/dev/null 2>&1 || return 1
  fi

  snap_log "unsnap $target: restored tiled slot via anchor/$side (parent=$parent layout=$layout parent_alive=$parent_alive)"
  return 0
}

if [ -n "$TARGET" ] && ! [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  snap_log "rejected non-numeric con_id: $TARGET"
  echo "tile-snap: invalid con_id: $TARGET" >&2
  exit 1
fi

# Resolve the target con_id up front; we need it for polling and pre-snap
# geometry capture. If TARGET wasn't given, look up the focused id.
if [ -z "$TARGET" ]; then
  TARGET=$(i3-msg -t get_tree | jq -r '
    [.. | objects | select(.focused? == true and .window? != null)][0].id // empty')
  if [ -z "$TARGET" ] || ! [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    snap_log "no focused window con_id"
    exit 1
  fi
fi

# Serialize concurrent invocations for the same window. Key autorepeat on the
# snap/unsnap bindings can fire this script in bursts; without a lock those run
# concurrently and race on the same marks (e.g. two unsnaps reading the same
# _presnap_ mark before either unmarks it). Take a per-target non-blocking lock
# and skip if another instance already holds it. The lock auto-releases when
# this process exits. Different windows lock on different files, so they still
# run in parallel. If the lock file can't be created, proceed unlocked.
exec {LOCK_FD}>"$SNAP_RUNTIME_DIR/tile-snap-$TARGET.lock" 2>/dev/null
if [ -n "${LOCK_FD:-}" ] && ! flock -n "$LOCK_FD"; then
  snap_log "skip $REGION $TARGET: another tile-snap holds the lock"
  exit 0
fi

# ---------- unsnap: restore pre-snap geometry and exit ----------
if [ "$REGION" = "unsnap" ]; then
  IFS='|' read -r PRE FLOATING TILING <<<"$(i3-msg -t get_tree | jq -r --argjson id "$TARGET" '
    [.. | objects | select(.id? == $id)][0] |
    (.marks // []) as $m |
    ([$m[] | select(startswith("_presnap_"))][0] // "") as $pre |
    ([$m[] | select(startswith("_snap_"))][0] // "") as $snap |
    ([$m[] | select(startswith("_pretiling_"))][0] // "") as $tiling |
    "\($pre)|\($snap)|\($tiling)"')"
  if [ -z "$PRE" ]; then
    snap_log "unsnap $TARGET: no _presnap_ mark; floating disable"
    i3-msg "[con_id=$TARGET] floating disable" >/dev/null 2>&1
    [ -n "$FLOATING" ] && i3-msg "[con_id=$TARGET] unmark $FLOATING" >/dev/null 2>&1
    [ -n "$TILING" ] && i3-msg "[con_id=$TARGET] unmark $TILING" >/dev/null 2>&1
    cleanup_tiling_restore_marks "$TARGET" "$TILING"
    apply_autotiling_split "$TARGET"
    exit 0
  fi
  # _presnap_<x>_<y>_<w>_<h>_<floating0|1>
  IFS=_ read -r _ _ px py pw ph pf <<<"$PRE"
  if ! [[ "$px" =~ ^-?[0-9]+$ && "$py" =~ ^-?[0-9]+$ && "$pw" =~ ^[0-9]+$ && "$ph" =~ ^[0-9]+$ ]]; then
    snap_log "unsnap $TARGET: malformed mark '$PRE'"
    i3-msg "[con_id=$TARGET] unmark $PRE" >/dev/null 2>&1
    [ -n "$FLOATING" ] && i3-msg "[con_id=$TARGET] unmark $FLOATING" >/dev/null 2>&1
    [ -n "$TILING" ] && i3-msg "[con_id=$TARGET] unmark $TILING" >/dev/null 2>&1
    cleanup_tiling_restore_marks "$TARGET" "$TILING"
    exit 1
  fi
  if [ "$pf" = "1" ]; then
    i3-msg "[con_id=$TARGET] floating enable, resize set $pw $ph, move position $px $py" >/dev/null
  else
    restore_tiled_presnap "$TARGET" "$TILING" || i3-msg "[con_id=$TARGET] floating disable" >/dev/null
    apply_autotiling_split "$TARGET"
  fi
  i3-msg "[con_id=$TARGET] unmark $PRE" >/dev/null 2>&1
  [ -n "$FLOATING" ] && i3-msg "[con_id=$TARGET] unmark $FLOATING" >/dev/null 2>&1
  [ -n "$TILING" ] && i3-msg "[con_id=$TARGET] unmark $TILING" >/dev/null 2>&1
  cleanup_tiling_restore_marks "$TARGET" "$TILING"
  snap_log "unsnap $TARGET -> ${px},${py} ${pw}x${ph} float=$pf"
  exit 0
fi

# ---------- workspace + output geometry ----------
read -r WS_OUTPUT X Y W H <<<"$(i3-msg -t get_tree | jq -r --argjson id "$TARGET" '
  [.. | objects | select(.type? == "workspace") |
   select([.. | objects | .id?] | index($id))][0] |
  "\(.output) \(.rect.x) \(.rect.y) \(.rect.width) \(.rect.height)"')"

# jq emits "null" for missing fields; treat any non-positive as failure.
if ! [[ "${W:-}" =~ ^[0-9]+$ && "${H:-}" =~ ^[0-9]+$ ]] || (( W <= 0 || H <= 0 )); then
  snap_log "could not resolve workspace rect for con_id=$TARGET (got W=$W H=$H)"
  exit 1
fi

read -r OX OY OW OH <<<"$(i3-msg -t get_outputs | jq -r --arg o "$WS_OUTPUT" '
  .[] | select(.active and .name == $o) | "\(.rect.x) \(.rect.y) \(.rect.width) \(.rect.height)"')"

# On mixed-height monitors i3/X can expose root-sized pseudo outputs and stale
# workspace rects during output changes. Keep snaps inside the real active
# output, while preserving workspace insets when the workspace rect is sane.
if [[ "${OH:-}" =~ ^[0-9]+$ ]]; then
  if (( X < OX || Y < OY || X + W > OX + OW || Y + H > OY + OH )); then
    X=$OX; Y=$OY; W=$OW; H=$OH
  fi
fi

# Polybar setups vary: some reserve space via struts, some just cover the
# screen. Walk visible polybar windows and only add the inset i3 has not
# already removed from the workspace rect.
TOP_INSET=0
BOT_INSET=0
for win in $(xdotool search --class '^[Pp]olybar$' 2>/dev/null); do
  info=$(xwininfo -id "$win" 2>/dev/null) || continue
  [[ "$info" == *"IsViewable"* ]] || continue
  pb_w=$(awk '/Width:/ {print $2; exit}' <<<"$info")
  pb_h=$(awk '/Height:/ {print $2; exit}' <<<"$info")
  pb_y=$(awk '/Absolute upper-left Y:/ {print $4}' <<<"$info")
  pb_x=$(awk '/Absolute upper-left X:/ {print $4}' <<<"$info")
  [ -z "$pb_w" ] || [ -z "$pb_h" ] && continue
  # Skip polybars on a different monitor. Check both axes because an external
  # output may be vertically offset next to a panel with different dimensions.
  (( pb_x + pb_w <= X || pb_x >= X + W )) && continue
  (( pb_y + pb_h <= Y || pb_y >= Y + H )) && continue
  if [[ "${OH:-}" =~ ^[0-9]+$ ]] && (( pb_y < OY + OH / 2 )); then
    (( pb_h > TOP_INSET )) && TOP_INSET=$pb_h
  else
    (( pb_h > BOT_INSET )) && BOT_INSET=$pb_h
  fi
done

if [[ "${OH:-}" =~ ^[0-9]+$ ]]; then
  RESERVED_TOP=$((Y - OY))
  RESERVED_BOT=$(((OY + OH) - (Y + H)))
  (( RESERVED_TOP < 0 )) && RESERVED_TOP=0
  (( RESERVED_BOT < 0 )) && RESERVED_BOT=0
else
  RESERVED_TOP=0
  RESERVED_BOT=0
fi

TOP_INSET=$((TOP_INSET > RESERVED_TOP ? TOP_INSET - RESERVED_TOP : 0))
BOT_INSET=$((BOT_INSET > RESERVED_BOT ? BOT_INSET - RESERVED_BOT : 0))

Y=$((Y + TOP_INSET))
H=$((H - TOP_INSET - BOT_INSET))
(( W <= 0 || H <= 0 )) && { snap_log "non-positive WxH after insets"; exit 1; }

HW=$((W / 2))
HH=$((H / 2))
# Other half — use W-HW so odd widths fill exactly with no 1px gap.
HW2=$((W - HW))
HH2=$((H - HH))

case "$REGION" in
  full)   tw=$W;   th=$H;   tx=$X;        ty=$Y ;;
  left)   tw=$HW;  th=$H;   tx=$X;        ty=$Y ;;
  right)  tw=$HW2; th=$H;   tx=$((X+HW)); ty=$Y ;;
  up)     tw=$W;   th=$HH;  tx=$X;        ty=$Y ;;
  down)   tw=$W;   th=$HH2; tx=$X;        ty=$((Y+HH)) ;;
  ul)     tw=$HW;  th=$HH;  tx=$X;        ty=$Y ;;
  ur)     tw=$HW2; th=$HH;  tx=$((X+HW)); ty=$Y ;;
  dl)     tw=$HW;  th=$HH2; tx=$X;        ty=$((Y+HH)) ;;
  dr)     tw=$HW2; th=$HH2; tx=$((X+HW)); ty=$((Y+HH)) ;;
  *) echo "unknown region: $REGION" >&2; snap_log "unknown region: $REGION"; exit 1 ;;
esac

# Match the workspace's title-bar default so the floating window's geometry
# is deterministic (otherwise a window opened tiled with `normal` border
# keeps it after `floating enable` and the title bar eats H).
if [ -f "$SNAP_TITLES_STATE" ] && [ "$(cat "$SNAP_TITLES_STATE")" = "on" ]; then
  BORDER="normal"
else
  BORDER="pixel 1"
fi

# Capture pre-snap state on the *first* snap of this window so unsnap can
# restore it later. For tiled windows, also capture the nearest split parent
# plus previous/next sibling anchors. resnap re-runs tile-snap with the same
# id, so we must only capture when no _presnap_ mark exists yet.
read -r HAS_PRE CUR_X CUR_Y CUR_W CUR_H CUR_FLOAT SLOT_PARENT SLOT_LAYOUT SLOT_PREV SLOT_NEXT <<<"$(i3-msg -t get_tree | jq -r --argjson id "$TARGET" '
  def slot_entries($p):
    [range(0; ($p | length) - 1) as $i |
     select($p[$i] == "nodes") |
     {parent_path: $p[:$i], idx: $p[$i + 1]}];

  . as $tree |
  [.. | objects | select(.id? == $id)][0] as $n |
  (first(paths(objects | select(.id? == $id))) // null) as $p |
  (if $p == null then
     {parent: 0, layout: "none", idx: -1, children: []}
   else
     ([slot_entries($p)[] |
       . as $slot |
       ($tree | getpath($slot.parent_path)) as $parent |
       ($parent.nodes // []) as $children |
       ($children[$slot.idx] // {}) as $child |
       select((($parent.type? == "workspace") or
               (($parent.type? == "con") and (($child.type? // "") != "workspace"))) and
              (($children | length) > 1)) |
       {parent: ($parent.id // 0), layout: ($parent.layout // "none"),
        idx: $slot.idx, children: $children}] | last) //
       {parent: 0, layout: "none", idx: -1, children: []}
   end) as $restore |
  (($n.marks // []) | any(startswith("_presnap_"))) as $hp |
  [
    ($hp | tostring),
    ($n.rect.x // 0),
    ($n.rect.y // 0),
    ($n.rect.width // 0),
    ($n.rect.height // 0),
    ($n.floating // ""),
    ($restore.parent // 0),
    ($restore.layout // "none"),
    (if ($restore.idx // -1) > 0 then ($restore.children[$restore.idx - 1].id // 0) else 0 end),
    (if (($restore.idx // -1) >= 0 and (($restore.idx + 1) < ($restore.children | length))) then
       ($restore.children[$restore.idx + 1].id // 0)
     else 0 end)
  ] | @tsv')"
if [ "$HAS_PRE" = "false" ]; then
  case "$CUR_FLOAT" in
    user_on|auto_on) pf=1 ;;
    *) pf=0 ;;
  esac
  if [[ "$CUR_X" =~ ^-?[0-9]+$ && "$CUR_Y" =~ ^-?[0-9]+$ && "$CUR_W" =~ ^[0-9]+$ && "$CUR_H" =~ ^[0-9]+$ ]]; then
    i3-msg "[con_id=$TARGET] mark --add _presnap_${CUR_X}_${CUR_Y}_${CUR_W}_${CUR_H}_${pf}" >/dev/null
  fi
  if [ "$pf" = "0" ] &&
     [[ "${SLOT_PARENT:-}" =~ ^[0-9]+$ && "${SLOT_PREV:-}" =~ ^[0-9]+$ && "${SLOT_NEXT:-}" =~ ^[0-9]+$ ]] &&
     [ "${SLOT_PARENT:-0}" != "0" ] &&
     { [ "${SLOT_PREV:-0}" != "0" ] || [ "${SLOT_NEXT:-0}" != "0" ]; }; then
    i3-msg "[con_id=$TARGET] mark --add _pretiling_${SLOT_PARENT}_${SLOT_LAYOUT}_${SLOT_PREV}_${SLOT_NEXT}" >/dev/null 2>&1
    i3-msg "[con_id=$SLOT_PARENT] mark --add _snap_parent_$TARGET" >/dev/null 2>&1
    [ "${SLOT_PREV:-0}" != "0" ] && i3-msg "[con_id=$SLOT_PREV] mark --add _snap_prev_$TARGET" >/dev/null 2>&1
    [ "${SLOT_NEXT:-0}" != "0" ] && i3-msg "[con_id=$SLOT_NEXT] mark --add _snap_next_$TARGET" >/dev/null 2>&1
  fi
fi

# Strip any prior _snap_* marks before adding the new one. i3's `mark --add`
# accumulates, so without this a window re-snapped from left->full would
# carry both _snap_left and _snap_full, and resnap.sh would later race
# multiple tile-snap calls for the same window in parallel.
OLD_SNAPS=$(i3-msg -t get_tree | jq -r --argjson id "$TARGET" '
  ([.. | objects | select(.id? == $id)][0].marks // []) |
  map(select(startswith("_snap_"))) | join(",")')
UNMARK_PREFIX=""
if [ -n "$OLD_SNAPS" ]; then
  IFS=',' read -ra _old <<<"$OLD_SNAPS"
  for _m in "${_old[@]}"; do
    [ -n "$_m" ] && UNMARK_PREFIX+="unmark $_m, "
  done
fi

# Stage 1: leave fullscreen, set border + float, apply mark. Then poll for the
# floating state to flip — apps with size hints (terminals) need a moment.
i3-msg "[con_id=$TARGET] ${UNMARK_PREFIX}fullscreen disable, border $BORDER, floating enable, mark --add _snap_$REGION" >/dev/null
for _ in 1 2 3 4 5 6 7 8 9 10; do
  state=$(i3-msg -t get_tree | jq -r --argjson id "$TARGET" '
    [.. | objects | select(.id? == $id)][0].floating // "stopped_on"')
  case "$state" in user_on|auto_on) break ;; esac
  sleep 0.01
done

# Stage 2: place it. Retry while the rect doesn't fit. Some apps, especially
# terminals, round requested sizes to their size hints; if that makes the
# window too tall for a visible bar inset, i3 clamps it back to y=0. Shrink the
# requested size by the reported overflow so the actual window lands inside the
# target rect instead of covering the bar.
attempts=0
req_w=$tw
req_h=$th
fit=""
while (( attempts < 10 )); do
  i3-msg "[con_id=$TARGET] resize set $req_w $req_h, move position $tx $ty" >/dev/null
  sleep 0.02
  read -r aw ah ax ay <<<"$(i3-msg -t get_tree | jq -r --argjson id "$TARGET" '
    [.. | objects | select(.id? == $id)][0] | "\(.rect.width) \(.rect.height) \(.rect.x) \(.rect.y)"')"
  if [ "$aw" = "$tw" ] && [ "$ah" = "$th" ] && [ "$ax" = "$tx" ] && [ "$ay" = "$ty" ]; then
    fit="exact"
    break
  fi
  if (( ax >= tx && ay >= ty && ax + aw <= tx + tw && ay + ah <= ty + th )); then
    fit="inside"
    break
  fi

  over_w=0
  over_h=0
  (( ax < tx )) && over_w=$((tx - ax))
  (( ax + aw > tx + tw && ax + aw - tx - tw > over_w )) && over_w=$((ax + aw - tx - tw))
  (( ay < ty )) && over_h=$((ty - ay))
  (( ay + ah > ty + th && ay + ah - ty - th > over_h )) && over_h=$((ay + ah - ty - th))

  (( over_w > 0 && req_w > over_w )) && req_w=$((req_w - over_w))
  (( over_h > 0 && req_h > over_h )) && req_h=$((req_h - over_h))
  attempts=$((attempts + 1))
done

if [ -z "$fit" ]; then
  snap_log "snap $TARGET $REGION: rect did not converge (want ${tw}x${th}+${tx}+${ty}, got ${aw}x${ah}+${ax}+${ay})"
elif [ "$fit" = "inside" ]; then
  snap_log "snap $TARGET $REGION inside ${aw}x${ah}+${ax}+${ay} (target ${tw}x${th}+${tx}+${ty}, attempts=$((attempts+1)))"
else
  snap_log "snap $TARGET $REGION ${tw}x${th}+${tx}+${ty} (attempts=$((attempts+1)))"
fi
