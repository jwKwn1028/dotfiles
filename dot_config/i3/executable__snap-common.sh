#!/usr/bin/env bash
# Shared helpers for tile-snap / resnap / snap-watcher / toggle-titles.
# Source from sibling scripts:  . "$DIR/_snap-common.sh"
#
# Provides:
#   SNAP_RUNTIME_DIR     - per-user runtime dir (cleared on reboot)
#   SNAP_TITLES_STATE    - title-bar on/off state file
#   SNAP_FOCUS_HISTORY   - last/current focus ids for focus-prev
#   SNAP_LOG             - rolling debug log
#   snap_log <msg>       - append to log, auto-rotate at 200 KB
#   mark_to_quads <r>    - region -> covered quadrants (ul ur dl dr subset)
#   region_size <r>      - region area in quadrants (4, 2, 1)
#   regions_by_size      - newline list: full, halves, quadrants
#   apply_autotiling_split <con_id> [depth_limit]
#                         - apply the same split h/v rule used by autotiling

# shellcheck disable=SC2034
SNAP_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# shellcheck disable=SC2034
SNAP_TITLES_STATE="$SNAP_RUNTIME_DIR/i3-titles.state"
# shellcheck disable=SC2034
SNAP_FOCUS_HISTORY="$SNAP_RUNTIME_DIR/i3-focus-history"
SNAP_LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/i3"
SNAP_LOG="$SNAP_LOG_DIR/snap.log"

# Append a timestamped line to the log. Caps file at ~200KB by trimming to the
# last 500 lines when exceeded. No-op (silently) if the log dir can't be made.
snap_log() {
  mkdir -p "$SNAP_LOG_DIR" 2>/dev/null || return 0
  if [ -f "$SNAP_LOG" ]; then
    local sz
    sz=$(stat -c%s "$SNAP_LOG" 2>/dev/null || echo 0)
    if [ "$sz" -gt 204800 ]; then
      tail -n 500 "$SNAP_LOG" > "$SNAP_LOG.tmp" 2>/dev/null && mv "$SNAP_LOG.tmp" "$SNAP_LOG"
    fi
  fi
  printf '[%s] %s[%d]: %s\n' "$(date +%H:%M:%S)" "${0##*/}" "$$" "$*" >> "$SNAP_LOG"
}

mark_to_quads() {
  case "$1" in
    full)        echo "ul ur dl dr" ;;
    left)        echo "ul dl" ;;
    right)       echo "ur dr" ;;
    up)          echo "ul ur" ;;
    down)        echo "dl dr" ;;
    ul|ur|dl|dr) echo "$1" ;;
  esac
}

region_size() {
  case "$1" in
    full) echo 4 ;;
    left|right|up|down) echo 2 ;;
    ul|ur|dl|dr) echo 1 ;;
    *) echo 0 ;;
  esac
}

# Region names from largest to smallest. Used when picking the best region
# that still contains a given set of quadrants.
regions_by_size() {
  printf '%s\n' full left right up down ul ur dl dr
}

apply_autotiling_split() {
  local target="$1" limit="${2:-6}"
  local fields floating fullscreen width height parent_layout parent_type
  local workspace_found depth_limit_reached desired cmd
  local i

  for i in 1 2 3 4 5 6 7 8 9 10; do
    fields=$(i3-msg -t get_tree | jq -r --argjson id "$target" --argjson limit "$limit" '
      def ancestor_paths($p):
        if ($p | length) < 2 then empty
        else ($p[:-2]), ancestor_paths($p[:-2])
        end;

      . as $tree |
      (first(paths(objects | select(.id? == $id))) // null) as $p |
      if $p == null then
        empty
      else
        ($tree | getpath($p)) as $n |
        (if ($p | length) >= 2 then ($tree | getpath($p[:-2])) else {} end) as $parent |
        (reduce (ancestor_paths($p)) as $ap
          ({count: 0, found: false, done: false};
           if .done then
             .
           else
             ($tree | getpath($ap)) as $a |
             if ($a.type? == "workspace") then
               .found = true | .done = true
             elif ((($a.nodes // []) | length) > 1) then
               .count += 1
             else
               .
             end
           end)) as $depth |
        [
          ($n.floating // ""),
          ($n.fullscreen_mode // 0),
          ($n.rect.width // 0),
          ($n.rect.height // 0),
          ($parent.layout // ""),
          ($parent.type // ""),
          ($depth.found | tostring),
          (($limit > 0 and $depth.count >= $limit) | tostring)
        ] | @tsv
      end') || return 0

    [ -n "$fields" ] || return 0
    IFS=$'\t' read -r floating fullscreen width height parent_layout parent_type workspace_found depth_limit_reached <<<"$fields"
    case "$floating" in
      user_on|auto_on) sleep 0.01 ;;
      *) break ;;
    esac
  done

  case "$floating" in
    user_on|auto_on)
      snap_log "autotiling split skipped for $target: still floating"
      return 0
      ;;
  esac
  [ "$fullscreen" = "1" ] && return 0
  [ "$workspace_found" = "true" ] || return 0
  [ "$depth_limit_reached" = "true" ] && return 0
  case "$parent_layout" in stacked|tabbed) return 0 ;; esac
  [[ "$width" =~ ^[0-9]+$ && "$height" =~ ^[0-9]+$ ]] || return 0
  (( width > 0 && height > 0 )) || return 0

  if (( height > width )); then
    desired="splitv"
    cmd="split v"
  else
    desired="splith"
    cmd="split h"
  fi

  [ "$parent_layout" = "$desired" ] && return 0

  if i3-msg "[con_id=$target] $cmd" >/dev/null 2>&1; then
    snap_log "autotiling split $target -> $desired (${width}x${height}, parent=$parent_type/$parent_layout)"
  else
    snap_log "autotiling split $target failed -> $desired (${width}x${height}, parent=$parent_type/$parent_layout)"
  fi
}
