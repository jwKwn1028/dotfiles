#!/usr/bin/env bash
# Recover from "keyboard frozen in X". Run from a TTY (Ctrl+Alt+F2..F6) after
# switching out of the X session at tty7; switch back with Ctrl+Alt+F7 after.
#
# Least to most invasive: 0. capture the frozen state (GPU/power/kernel) to
# ~/.local/share/x-freeze-logs/; 1. re-attach input devices; 2. offer to kill
# unresponsive X clients (usually Zen); 3. kill Zen + Ghostty; 4. restart
# fcitx5; 5. restart picom; 6. reload i3.

set -u

export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  for x in "$HOME/.Xauthority" /var/run/lightdm/root/:0; do
    [ -r "$x" ] && export XAUTHORITY="$x" && break
  done
fi

say() { printf '\n=== %s ===\n' "$*"; }
have() { command -v "$1" > /dev/null 2>&1; }

# --- 0. Capture pre-recovery diagnostic state -------------------------------
# Photographs the FROZEN state before any recovery touches it. Runs before the
# xinput/X reachability exits below, so GPU/power/kernel data survives even when
# X is wedged. Every X probe is wrapped in `timeout`: a hung X server must not
# be able to hang the capture itself.
capture_freeze_state() {
  local ts dir log gpu d f out rc
  ts=$(date +%Y%m%d-%H%M%S)
  dir="$HOME/.local/share/x-freeze-logs"
  mkdir -p "$dir" 2> /dev/null || dir="/tmp"
  log="$dir/freeze-$ts.log"

  # Find the amdgpu card dynamically (card numbering can shift across boots).
  gpu=""
  for d in /sys/class/drm/card[0-9]*/device; do
    [ "$(basename "$(readlink "$d/driver" 2> /dev/null)" 2> /dev/null)" = "amdgpu" ] \
      && gpu="$d" && break
  done

  {
    echo "# x-unstick freeze capture @ $(date -Is)"
    echo "# host=$(cat /proc/sys/kernel/hostname 2> /dev/null)  kernel=$(uname -r)  uptime=$(cut -d' ' -f1 /proc/uptime)s"

    echo
    echo "===== POWER SOURCE (was it really on battery?) ====="
    for f in /sys/class/power_supply/AC/online \
      /sys/class/power_supply/BAT0/status \
      /sys/class/power_supply/BAT0/capacity; do
      [ -r "$f" ] && printf '%s = %s\n' "$f" "$(cat "$f" 2> /dev/null)"
    done

    echo
    echo "===== GPU DPM / CLOCKS (pinned at the 600MHz floor? busy or idle?) ====="
    echo "amdgpu card: ${gpu:-NOT FOUND}"
    for f in power_dpm_force_performance_level power_dpm_state gpu_busy_percent \
      mem_busy_percent pp_dpm_sclk pp_dpm_mclk pp_dpm_pcie; do
      [ -n "$gpu" ] && [ -r "$gpu/$f" ] && { echo "--- $f ---"; cat "$gpu/$f" 2> /dev/null; }
    done

    echo
    echo "===== CPU FREQ / IDLE / PROFILE ====="
    echo "platform_profile  = $(cat /sys/firmware/acpi/platform_profile 2> /dev/null)"
    echo "amd_pstate.status = $(cat /sys/devices/system/cpu/amd_pstate/status 2> /dev/null)"
    echo "governor          = $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2> /dev/null)"
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
      printf '  %s = %s kHz\n' "$(echo "$f" | grep -oE 'cpu[0-9]+')" "$(cat "$f" 2> /dev/null)"
    done

    echo
    echo "===== LOAD / PROCESS STATES (D = stuck on I/O, Z = zombie) ====="
    cat /proc/loadavg
    ps -eo pid,stat,pcpu,comm --sort=-pcpu 2> /dev/null \
      | awk 'NR==1 || $2 ~ /^[DZ]/ || /Xorg|picom|i3|fcitx5|zen|ghostty/'

    echo
    echo "===== X / i3 RESPONSIVENESS (timeout-guarded) ====="
    echo "DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-unset}"
    if have xset; then
      out=$(timeout 3 xset q 2>&1); rc=$?
      echo "-- xset q (rc=$rc; 124=TIMEOUT => X server itself wedged, not just input) --"
      printf '%s\n' "$out" | head -20
    fi
    if have i3-msg; then
      out=$(timeout 3 i3-msg -t get_version 2>&1); rc=$?
      echo "-- i3 ipc (rc=$rc; 124=TIMEOUT => i3 wedged) --"
      printf '%s\n' "$out" | head -5
    fi

    echo
    echo "===== INPUT DEVICES (detached/floating at freeze? tests the #1 recovery premise) ====="
    if have xinput; then
      out=$(timeout 3 xinput list --short 2>&1); rc=$?
      echo "(rc=$rc; 124=TIMEOUT)"
      printf '%s\n' "$out"
    fi

    echo
    echo "===== IRQ TOTALS x2 (~1s apart; a counter that does NOT move = that source is dead) ====="
    echo "  amdgpu=display/vblank  i8042=internal kbd  ELAN0688=touchpad"
    awk '/(i8042|amdgpu|ELAN0688|pinctrl_amd|AMDI0010)/{s=0;for(i=2;i<=NF;i++){if($i~/^[0-9]+$/)s+=$i;else break};lbl="";for(j=i;j<=NF;j++)lbl=lbl" "$j;printf "  total=%-9s%s\n",s,lbl}' /proc/interrupts
    sleep 1
    echo "  --- after 1s ---"
    awk '/(i8042|amdgpu|ELAN0688|pinctrl_amd|AMDI0010)/{s=0;for(i=2;i<=NF;i++){if($i~/^[0-9]+$/)s+=$i;else break};lbl="";for(j=i;j<=NF;j++)lbl=lbl" "$j;printf "  total=%-9s%s\n",s,lbl}' /proc/interrupts

    echo
    echo "===== INPUT SUBSYSTEM EVENTS (why did the devices detach to floating?) ====="
    for L in "$HOME/.local/share/xorg/Xorg.0.log" /var/log/Xorg.0.log; do
      if [ -r "$L" ]; then
        echo "-- $L (input/detach/error lines) --"
        grep -niE 'input|slave|floating|detach|libinput|hotplug|autoadd|remove|\(EE\)' "$L" 2>/dev/null | tail -20
        break
      fi
    done
    echo "-- recent kernel input/i2c device events (add/remove/timeout) --"
    if command -v journalctl > /dev/null 2>&1; then
      journalctl -k -b -0 --no-pager 2>&1 \
        | grep -iE 'input:|i2c_designware|AMDI0010|elan|ELAN0688|hid|new .*device|disconnect|removed|reset|failed|timeout' \
        | tail -20
    fi

    echo
    echo "===== KERNEL LOG TAIL (amdgpu / drm / gpu reset / flip) ====="
    if dmesg > /dev/null 2>&1; then
      dmesg | tail -80
    elif sudo -n dmesg > /dev/null 2>&1; then
      sudo -n dmesg | tail -80
    elif command -v journalctl > /dev/null 2>&1; then
      journalctl -k -b -0 -n 120 --no-pager 2>&1 | tail -120
    else
      echo "[kernel log needs root — after recovery run: sudo dmesg | tail -80]"
    fi
  } >> "$log" 2>&1

  echo "  freeze state captured -> $log"
  # Keep only the 40 most recent captures.
  ls -1t "$dir"/freeze-*.log 2> /dev/null | tail -n +41 | xargs -r rm -f 2> /dev/null
}
capture_freeze_state

# Capture-only mode (~/.x-capture.sh over SSH): grab the frozen state and STOP --
# no VT switch happened, so the readings are uncontaminated. Recover afterwards
# from a TTY with the normal invocation.
if [ "${1:-}" = "--capture-only" ] || [ -n "${X_UNSTICK_CAPTURE_ONLY:-}" ]; then
  echo "  (capture-only mode — recovery skipped; recover later with: ~/.x-unstick.sh)"
  exit 0
fi

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
  # Respect devices deliberately turned off in XFCE settings: if the pointers
  # xfconf channel pins Device_Enabled=0, leave it off.
  name=$(xinput list --name-only "$id" 2> /dev/null)
  xfname=${name//[^[:alnum:] ]/}; xfname=${xfname// /_}
  if have xfconf-query \
    && [ "$(xfconf-query -c pointers -p "/$xfname/Properties/Device_Enabled" 2> /dev/null)" = "0" ]; then
    echo "  left id=$id ($name) disabled — xfconf pins it off"
    continue
  fi
  xinput enable "$id" 2> /dev/null && echo "  enabled id=$id"
done

# Re-assert the touchpad state: its shadow "Mouse" node has no xfconf entry, so
# the loop above would otherwise revive a deliberately-off touchpad.
touchpad_bin="$HOME/.local/bin/touchpad"
if [ -x "$touchpad_bin" ]; then
  say "Re-applying touchpad state ($touchpad_bin apply)"
  "$touchpad_bin" apply 2>&1 | sed 's/^/  /'
fi

# --- 2. Find unresponsive X clients -----------------------------------------
say "Scanning for unresponsive X clients (usual culprit: a hung browser)"
# A toplevel whose owning PID is in 'D'/unresponsive often means a stuck client.
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
