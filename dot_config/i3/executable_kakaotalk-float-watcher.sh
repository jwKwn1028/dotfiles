#!/usr/bin/env bash
# Keep KakaoTalk floating after Wine remaps/maximizes it during login.

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
      (.container.window_properties.instance // ""),
      (.container.window_properties.title // ""),
      (.container.name // "")
    ]
    | any(test("kakaotalk|카카오톡"; "i"))
  ' <<<"$event" >/dev/null 2>&1
}

fix_kakaotalk_windows() {
  local id window_id floating fullscreen

  i3-msg -t get_tree | jq -r '
    .. | objects | select(.window? != null)
    | select(
        [
          (.window_properties.class // ""),
          (.window_properties.instance // ""),
          (.window_properties.title // ""),
          (.name // "")
        ]
        | any(test("kakaotalk|카카오톡"; "i"))
      )
    | [.id, (.window // ""), (.floating // ""), (.fullscreen_mode // 0)] | @tsv
  ' | while IFS=$'\t' read -r id window_id floating fullscreen; do
    if is_minimized_window "$window_id"; then
      continue
    fi

    if [[ "$floating" != *"_on"* || "$fullscreen" != "0" ]]; then
      i3-msg "[con_id=$id] fullscreen disable, floating enable, resize set $KAKAO_WIDTH $KAKAO_HEIGHT, move position center" >/dev/null 2>&1
    fi
  done
}

snap_log "kakaotalk watcher starting (pid $$)"

while :; do
  fix_kakaotalk_windows

  i3-msg -t subscribe -m '["window"]' 2>/dev/null | while IFS= read -r event; do
    case "$(jq -r '.change // ""' <<<"$event")" in
      close)
        ;;
      *)
        if event_is_kakaotalk "$event"; then
          sleep 0.05
          fix_kakaotalk_windows
        fi
        ;;
    esac
  done

  snap_log "kakaotalk watcher subscription ended, reconnecting in 1s"
  sleep 1
done
