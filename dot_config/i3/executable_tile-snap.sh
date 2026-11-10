#!/usr/bin/env bash

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

if [ -z "$TARGET" ]; then
  TARGET=$(i3-msg -t get_tree | jq -r '
    [.. | objects | select(.focused? == true and .window? != null)][0].id // empty')
  if [ -z "$TARGET" ] || ! [[ "$TARGET" =~ ^[0-9]+$ ]]; then
    snap_log "no focused window con_id"
    exit 1
  fi
fi

if [ "${SNAP_PLACEMENT_CHECKED:-0}" != 1 ] && [ -x "$DIR/workspace-action.sh" ]; then
  "$DIR/workspace-action.sh" placement "$TARGET" || exit 0
fi

exec {LOCK_FD}>"$SNAP_RUNTIME_DIR/tile-snap-$TARGET.lock" 2>/dev/null
if [ -n "${LOCK_FD:-}" ] && ! flock -n "$LOCK_FD"; then
  snap_log "skip $REGION $TARGET: another tile-snap holds the lock"
  exit 0
fi

if [ "$REGION" = "unsnap" ]; then
  IFS='|' read -r PRE FLOATING TILING <<<"$(i3-msg -t get_tree | jq -r --argjson id "$TARGET" '
    [.. | objects | select(.id? == $id)][0] |
    (.marks // []) as $m |
    ([$m[] | select(startswith("_presnap_"))][0] // "") as $pre |
    ([$m[] | select(test("^_snap_(full|left|right|up|down|ul|ur|dl|dr)$"))][0] // "") as $snap |
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

IFS='|' read -r X Y W H OX OY OW OH HAS_PRE CUR_X CUR_Y CUR_W CUR_H CUR_FLOAT \
  SLOT_PARENT SLOT_LAYOUT SLOT_PREV SLOT_NEXT OLD_SNAPS <<<"$(i3-msg -t get_tree |
  jq -r --argjson id "$TARGET" --argjson outputs "$(i3-msg -t get_outputs || echo '[]')" '
  def slot_entries($p):
    [range(0; ($p | length) - 1) as $i |
     select($p[$i] == "nodes") |
     {parent_path: $p[:$i], idx: $p[$i + 1]}];

  . as $tree |
  [.. | objects | select(.id? == $id)][0] as $n |
  ([.. | objects | select(.type? == "workspace") |
    select([.. | objects | .id?] | index($id))][0] // {}) as $ws |
  ([$outputs[] | select(.active and .name == $ws.output)][0] // {}) as $out |
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
  [
    $ws.rect.x, $ws.rect.y, $ws.rect.width, $ws.rect.height,
    $out.rect.x, $out.rect.y, $out.rect.width, $out.rect.height,
    (($n.marks // []) | any(startswith("_presnap_"))),
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
     else 0 end),
    (($n.marks // []) | map(select(test("^_snap_(full|left|right|up|down|ul|ur|dl|dr)$"))) | join(","))
  ] | map(if . == null then "" else tostring end) | join("|")')"

if ! [[ "${W:-}" =~ ^[0-9]+$ && "${H:-}" =~ ^[0-9]+$ ]] || (( W <= 0 || H <= 0 )); then
  snap_log "could not resolve workspace rect for con_id=$TARGET (got W=$W H=$H)"
  exit 1
fi

if [[ "${OH:-}" =~ ^[0-9]+$ ]]; then
  if (( X < OX || Y < OY || X + W > OX + OW || Y + H > OY + OH )); then
    X=$OX; Y=$OY; W=$OW; H=$OH
  fi
fi

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

if [ -f "$SNAP_TITLES_STATE" ] && [ "$(cat "$SNAP_TITLES_STATE")" = "on" ]; then
  BORDER="normal"
else
  BORDER="pixel 1"
fi

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

UNMARK_PREFIX=""
if [ -n "$OLD_SNAPS" ]; then
  IFS=',' read -ra _old <<<"$OLD_SNAPS"
  for _m in "${_old[@]}"; do
    [ -n "$_m" ] && UNMARK_PREFIX+="unmark $_m, "
  done
fi

STAGE="${UNMARK_PREFIX}fullscreen disable, border $BORDER, floating enable, mark --add _snap_$REGION, "
attempts=0
req_w=$tw
req_h=$th
fit=""
while (( attempts < 10 )); do
  i3-msg "[con_id=$TARGET] ${STAGE}resize set $req_w $req_h, move position $tx $ty" >/dev/null
  STAGE=""
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
