#!/usr/bin/env bash
# Keep KakaoTalk floating after Wine remaps/retiles it during login.
# Explicit fullscreen is left alone so i3's fullscreen toggle behaves normally.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
. "$DIR/_snap-common.sh"

mkdir -p "$SNAP_RUNTIME_DIR" 2>/dev/null || exit 0

LOCK="$SNAP_RUNTIME_DIR/i3-kakaotalk-float-watcher.lock"
exec 200>"$LOCK"
if ! flock -w 5 200; then
  snap_log "kakaotalk watcher lock contended for >5s; exiting"
  exit 0
fi

KAKAO_WIDTH=420
KAKAO_HEIGHT=760

is_minimized_window() {
  local window_id="$1"

  [[ -n "$window_id" && "$window_id" != "null" ]] || return 1

  xprop -id "$window_id" WM_STATE _NET_WM_STATE 2>/dev/null \
    | grep -Eq 'IconicState|WithdrawnState|_NET_WM_STATE_HIDDEN'
}

event_is_kakaotalk() {
  local event="$1"

  jq -e '
    [
      (.container.window_properties.class // ""),
      (.container.window_properties.instance // "")
    ]
    | any(test("^kakaotalk\\.exe$"; "i"))
  ' <<<"$event" >/dev/null 2>&1
}

fix_kakaotalk_windows() {
  local trigger="${1:-scan}"
  local id window_id floating fullscreen

  i3-msg -t get_tree | jq -r '
    .. | objects | select(.window? != null)
    | select(
        [
          (.window_properties.class // ""),
          (.window_properties.instance // "")
        ]
        | any(test("^kakaotalk\\.exe$"; "i"))
      )
    | [.id, (.window // ""), (.floating // ""), (.fullscreen_mode // 0)] | @tsv
  ' | while IFS=$'\t' read -r id window_id floating fullscreen; do
    if is_minimized_window "$window_id"; then
      continue
    fi

    # A fullscreen window is intentional from i3's point of view. Repairing it
    # here makes `fullscreen toggle` and this watcher issue opposite commands.
    if [[ "$fullscreen" != "0" ]]; then
      continue
    fi

    if [[ "$floating" != *"_on"* ]]; then
      snap_log "kakaotalk repair trigger=$trigger con_id=$id floating=${floating:-unknown}"
      i3-msg "[con_id=$id] floating enable, resize set $KAKAO_WIDTH $KAKAO_HEIGHT, move position center" >/dev/null 2>&1
    fi
  done
}

snap_log "kakaotalk watcher starting (pid $$)"

while :; do
  fix_kakaotalk_windows startup

  i3-msg -t subscribe -m '["window"]' 2>/dev/null | while IFS= read -r event; do
    change=$(jq -r '.change // ""' <<<"$event" 2>/dev/null) || continue
    case "$change" in
      new|fullscreen_mode|floating)
        if event_is_kakaotalk "$event"; then
          sleep 0.05
          fix_kakaotalk_windows "$change"
        fi
        ;;
    esac
  done

  snap_log "kakaotalk watcher subscription ended, reconnecting in 1s"
  sleep 1
done
