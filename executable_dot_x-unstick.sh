#!/usr/bin/env bash
# Recover from "keyboard frozen in X" symptoms.
# Run from a TTY (Ctrl+Alt+F2..F6) after switching out of the X session at tty7.
#
# Order of operations: least → most invasive.
#   1. Re-enable + re-attach all input devices in X.
#   2. Identify and offer to kill unresponsive X clients (usual culprit: Zen).
#   3. Kill all Zen Browser and Ghostty processes.
#   4. Restart fcitx5 (input method — common stall point).
#   5. Restart picom (compositor — secondary stall point).
#   6. Reload i3.
# After it finishes, switch back to tty7 (Ctrl+Alt+F7) and try typing.

set -u

export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  for x in "$HOME/.Xauthority" /var/run/lightdm/root/:0; do
    [ -r "$x" ] && export XAUTHORITY="$x" && break
  done
fi

say() { printf '\n=== %s ===\n' "$*"; }
have() { command -v "$1" > /dev/null 2>&1; }

if ! have xinput || ! have xdotool; then
  echo "Need xinput and xdotool installed." >&2
  exit 1
fi

if ! xinput list > /dev/null 2>&1; then
  echo "Cannot reach X server at DISPLAY=$DISPLAY XAUTHORITY=$XAUTHORITY" >&2
  exit 1
fi

# --- 1. Re-attach + re-enable input devices ---------------------------------
say "Re-attaching floating slave devices"
master_ptr=$(xinput list --short | awk '/Virtual core pointer/  {match($0,/id=[0-9]+/); print substr($0,RSTART+3,RLENGTH-3); exit}')
master_kbd=$(xinput list --short | awk '/Virtual core keyboard/ {match($0,/id=[0-9]+/); print substr($0,RSTART+3,RLENGTH-3); exit}')

# Devices that should normally stay floating (ACPI/special-purpose).
skip_re='ThinkPad Extra Buttons|gpio-keys|Sleep Button|Video Bus|XTEST'

xinput list --short | grep "floating slave" | while IFS= read -r line; do
  case "$line" in *Keyboard* | *keyboard*) target=$master_kbd ;; *) target=$master_ptr ;; esac
  if echo "$line" | grep -qE "$skip_re"; then continue; fi
  id=$(echo "$line" | grep -oE 'id=[0-9]+' | head -1 | cut -d= -f2)
  name=$(echo "$line" | sed -E 's/.*↳ *//; s/[[:space:]]*id=.*//' | sed 's/[[:space:]]\+$//')
  [ -n "$id" ] && [ -n "$target" ] && xinput reattach "$id" "$target" 2> /dev/null \
    && printf '  reattached %-40s id=%s → master %s\n' "$name" "$id" "$target"
done

say "Re-enabling disabled input devices"
xinput list --id-only 2> /dev/null | while IFS= read -r id; do
  enabled=$(xinput list-props "$id" 2> /dev/null | awk -F: '/Device Enabled/{gsub(/[ \t]/,"",$2);print $2;exit}')
  [ "$enabled" = "0" ] || continue
  # Respect devices the user deliberately turned off in XFCE settings: if the
  # pointers xfconf channel pins Device_Enabled=0, leave it off. Without this,
  # the loop clobbers an intentionally-disabled touchpad every recovery run.
  name=$(xinput list --name-only "$id" 2> /dev/null)
  xfname=${name//[^[:alnum:] ]/}; xfname=${xfname// /_}
  if have xfconf-query \
    && [ "$(xfconf-query -c pointers -p "/$xfname/Properties/Device_Enabled" 2> /dev/null)" = "0" ]; then
    echo "  left id=$id ($name) disabled — xfconf pins it off"
    continue
  fi
  xinput enable "$id" 2> /dev/null && echo "  enabled id=$id"
done

# Re-assert the intended touchpad state. Its shadow "Mouse" node has no xfconf
# entry, so the loop above would otherwise revive a deliberately-off touchpad.
touchpad_bin="$HOME/.local/bin/touchpad"
if [ -x "$touchpad_bin" ]; then
  say "Re-applying touchpad state ($touchpad_bin apply)"
  "$touchpad_bin" apply 2>&1 | sed 's/^/  /'
fi

# --- 2. Find unresponsive X clients -----------------------------------------
say "Scanning for unresponsive X clients (usual culprit: a hung browser)"
# A window whose owning PID is in 'D' or unresponsive state often means the
# X11 client is stuck. Quick check: ping each toplevel via _NET_WM_PING.
candidates=$(xdotool search --onlyvisible '' 2> /dev/null)
hung_pids=()
hung_lines=()
for w in $candidates; do
  pid=$(xdotool getwindowpid "$w" 2> /dev/null) || continue
  [ -z "$pid" ] && continue
  name=$(xdotool getwindowname "$w" 2> /dev/null)
  state=$(awk '{print $3}' /proc/"$pid"/stat 2> /dev/null)
  # 'D' = uninterruptible sleep, 'Z' = zombie — both strong signals
  if [ "$state" = "D" ] || [ "$state" = "Z" ]; then
    hung_pids+=("$pid")
    hung_lines+=("  PID $pid state=$state  $name")
  fi
done

if [ "${#hung_pids[@]}" -gt 0 ]; then
  printf '%s\n' "${hung_lines[@]}"
  printf '\nKill these PIDs? [y/N] '
  read -r ans
  case "$ans" in
    y | Y | yes) for p in "${hung_pids[@]}"; do kill -9 "$p" 2> /dev/null && echo "  killed $p"; done ;;
    *) echo "  skipped" ;;
  esac
else
  echo "  no obviously-hung X clients detected"
  echo "  (if you suspect a specific window, run: xkill   — and click the bad window)"
fi

# --- 3. Kill Zen Browser + Ghostty ------------------------------------------
say "Killing Zen Browser and Ghostty"
target_pids=()
for pattern in \
  '(^|/)(zen|zen-bin|zen-browser)([[:space:]]|$)' \
  '(^|/)ghostty([[:space:]]|$)'
do
  while IFS= read -r pid; do
    [ -n "$pid" ] && [ "$pid" != "$$" ] && target_pids+=("$pid")
  done < <(pgrep -f "$pattern" 2> /dev/null || true)
done

if [ "${#target_pids[@]}" -gt 0 ]; then
  mapfile -t target_pids < <(printf '%s\n' "${target_pids[@]}" | sort -n -u)
  for p in "${target_pids[@]}"; do
    ps -p "$p" -o pid=,comm=,args= 2> /dev/null | sed 's/^/  /'
  done

  for p in "${target_pids[@]}"; do kill "$p" 2> /dev/null || true; done
  sleep 1
  for p in "${target_pids[@]}"; do
    if kill -0 "$p" 2> /dev/null; then
      kill -9 "$p" 2> /dev/null && echo "  force-killed $p"
    else
      echo "  killed $p"
    fi
  done
else
  echo "  no Zen Browser or Ghostty processes found"
fi

# --- 4. Restart fcitx5 ------------------------------------------------------
if pgrep -x fcitx5 > /dev/null; then
  say "Restarting fcitx5 (input method)"
  pkill -x fcitx5
  sleep 0.5
  pkill -9 -x fcitx5 2> /dev/null
  nohup fcitx5 -d > /tmp/fcitx5.log 2>&1
  sleep 0.5
  pgrep -a fcitx5 | sed 's/^/  /'
fi

# --- 5. Restart picom -------------------------------------------------------
if pgrep -x picom > /dev/null; then
  say "Restarting picom (compositor)"
  pkill -x picom
  sleep 0.5
  pkill -9 -x picom 2> /dev/null
  nohup picom -b > /tmp/picom.log 2>&1
  sleep 0.5
  pgrep -a picom | sed 's/^/  /'
fi

# --- 6. Reload i3 -----------------------------------------------------------
say "Reloading i3"
if have i3-msg; then
  if i3-msg reload > /dev/null 2>&1; then
    echo "  i3 reload requested"
  else
    echo "  i3-msg reload failed (check DISPLAY/XAUTHORITY or I3SOCK)" >&2
  fi
else
  echo "  i3-msg not found"
fi

say "Done — switch back to tty7 (Ctrl+Alt+F7) and try typing"
