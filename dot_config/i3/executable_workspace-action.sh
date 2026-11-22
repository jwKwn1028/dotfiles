#!/bin/sh
set -u
case $0 in
  */*) DIR=${0%/*} ;;
  *) DIR=. ;;
esac
HELPER=$DIR/workspace-groups.py
[ -r "$HELPER" ] || HELPER=$DIR/executable_workspace-groups.py

python_helper() {
  exec /usr/bin/python3 "${I3_GROUP_HELPER:-$HELPER}" "$@"
}

[ -z "${I3_GROUP_HELPER:-}" ] || python_helper "$@"
command -v nc >/dev/null 2>&1 || python_helper "$@"
if [ "${XDG_RUNTIME_DIR+set}" = set ] && [ -z "$XDG_RUNTIME_DIR" ]; then
  python_helper "$@"
fi

action='' value='' has_value='' group='' click='' quiet=false expect=''
for arg do
  if [ -n "$expect" ]; then
    case $arg in
      -[0-9]*) ;;
      -*) python_helper "$@" ;;
    esac
    group=$arg
    expect=
    continue
  fi
  case $arg in
    --group) expect=group ;;
    --click) click=true ;;
    --quiet) quiet=true ;;
    -[0-9]*) case ${arg#-} in
               *[!0-9]*) python_helper "$@" ;;
             esac
             if [ -n "$has_value" ] || [ -z "$action" ]; then
               python_helper "$@"
             fi
             value=$arg has_value=1 ;;
    -*) python_helper "$@" ;;
    *) if [ -z "$action" ]; then
         action=$arg
       elif [ -z "$has_value" ]; then
         value=$arg has_value=1
       else
         python_helper "$@"
       fi ;;
  esac
done
[ -z "$expect" ] || python_helper "$@"
case $action in
  '' | serve | start | bar | path | request | status) python_helper "$@" ;;
  window-menu) command -v jq >/dev/null 2>&1 || python_helper "$@" ;;
esac
case $action$value$group in
  *[!A-Za-z0-9_-]*) python_helper "$@" ;;
esac

json="{\"action\": \"$action\", \"quiet\": $quiet"
if [ -n "$has_value" ]; then
  if [ "$action" = select ]; then
    json="$json, \"group\": \"$value\""
  else
    json="$json, \"value\": \"$value\""
  fi
fi
[ -z "$group" ] || json="$json, \"group\": \"$group\""
[ -z "$click" ] || json="$json, \"click\": true"

sock=${I3SOCK:-}
[ -n "$sock" ] || sock=$(i3 --get-socketpath 2>/dev/null) || sock=
if [ -z "$sock" ]; then
  echo "No i3 session socket" >&2
  exit 1
fi
key=$(printf '%s\000%s' "${DISPLAY-}" "$sock" | sha256sum)
rest=${key#????????????????????}
key=${key%"$rest"}
address=${XDG_RUNTIME_DIR:-/tmp/i3-user-$(id -u)}/i3-groups-$key/controller.sock

send() {
  reply=$(printf '%s}\n' "$1" | nc -N -U -w 15 "$address" 2>/dev/null) || reply=
}
send "$json"
if [ "$action" = window-menu ]; then
  case $reply in
    '{"ok": true,'*)
      index=$(printf '%s\n' "$reply" | jq -j '.result.menu' |
        rofi -dmenu -i -show-icons -format i -p Window) || exit 0
      case $index in
        '' | *[!0-9]*) exit 0 ;;
      esac
      id=$(printf '%s\n' "$reply" | jq -r ".result.ids[$index] // empty")
      [ -n "$id" ] || exit 0
      send "{\"action\": \"focus\", \"quiet\": false, \"value\": \"$id\""
      ;;
  esac
fi
case $reply in
  '{"ok": true, "result": true}') exit 0 ;;
  '{"ok": true,'*) [ "$action" != placement ] || exit 1
                   exit 0 ;;
  '') echo "Workspace controller unavailable" >&2 ;;
  *) printf '%s\n' "$reply" >&2 ;;
esac
exit 1
