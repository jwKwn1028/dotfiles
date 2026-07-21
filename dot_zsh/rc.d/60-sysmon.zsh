# sysmon: live CPU/GPU load and temps, RAM load, and fan speeds.
# Usage: sysmon [interval_seconds]
#   CPU temp  -> k10temp / Tctl        (AMD die temp)
#   GPU temp  -> amdgpu  / edge        (integrated Radeon)
#   fans      -> thinkpad-isa fan1/fan2
# echo a zsh color for a temperature.  Args: <temp> <green_thr> <yellow_thr>
# Matches fastfetch (~/.config/fastfetch/config.jsonc) semantics + colors:
#   temp >  yellow -> light_red (9)     temp >  green -> light_yellow (11)     else -> green
_sysmon_tcolor () {
  if   (( $1 > $3 )); then print -n 9
  elif (( $1 > $2 )); then print -n 11
  else                     print -n green
  fi
}

# CPU utilization %, via the shared calculator so sysmon and polybar's cpu
# module always agree on the method (2s-ish window, iowait counted as idle).
# See ~/.local/bin/cpu-load for the details.
_sysmon_cpu_load () {
  "$HOME/.local/bin/cpu-load" sysmon
}

# RAM utilization %, using MemAvailable so reclaimable cache is not counted as
# used memory. Round to the nearest whole percent to match CPU/GPU load output.
_sysmon_ram_load () {
  awk '
    /^MemTotal:/     { total=$2 }
    /^MemAvailable:/ { available=$2 }
    END {
      if (total > 0) printf "%.0f", 100 * (total - available) / total
      else print 0
    }
  ' /proc/meminfo
}

# AMD integrated GPU busy %, straight from amdgpu sysfs.
_sysmon_gpu_load () {
  local f
  for f in /sys/class/drm/card*/device/gpu_busy_percent; do
    [[ -r $f ]] && { print -rn -- "$(<$f)"; return; }
  done
  print -n 0
}

_sysmon_frame () {           # render one snapshot
  emulate -L zsh
  setopt prompt_percent      # local (LOCAL_OPTIONS): guarantee %% -> % in print -P,
                             # even if the session left prompt_percent unset

  local cpu_name gpu_name
  cpu_name="$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo)"
  if [[ $cpu_name == *"w/ "* ]]; then          # APU: GPU name is baked into the CPU string
    gpu_name="${cpu_name##*w/ }"
  else
    gpu_name="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -1 | sed 's/.*: //')"
    [[ -z $gpu_name ]] && gpu_name="unknown"
  fi

  # One pass over machine-readable sensor output; match by chip prefix + label.
  local vals cpu_temp gpu_temp fan1 fan2
  vals="$(sensors -u 2>/dev/null | awk '
    /^[^ ]/ && !/:/  { chip=$0; next }                     # chip header line
    /^[^ ].*:$/      { label=$0; sub(/:$/,"",label); next } # label line
    /^  / {
      split($0,a,":"); key=a[1]; val=a[2]; gsub(/ /,"",key); gsub(/ /,"",val)
      if (chip ~ /^k10temp/  && label=="Tctl" && key=="temp1_input") cpu=val
      if (chip ~ /^amdgpu/   && label=="edge" && key=="temp1_input") gpu=val
      if (chip ~ /^thinkpad/ && label=="fan1" && key=="fan1_input")  f1=val
      if (chip ~ /^thinkpad/ && label=="fan2" && key=="fan2_input")  f2=val
    }
    END { printf "%s %s %s %s", cpu, gpu, f1, f2 }
  ')"
  read cpu_temp gpu_temp fan1 fan2 <<< "$vals"

  local ct gt f1 f2 cl gl rl
  ct=$(printf '%.0f' "${cpu_temp:-0}"); gt=$(printf '%.0f' "${gpu_temp:-0}")
  f1=$(printf '%.0f' "${fan1:-0}");     f2=$(printf '%.0f' "${fan2:-0}")
  cl=$(_sysmon_cpu_load);               gl=$(_sysmon_gpu_load)
  rl=$(_sysmon_ram_load)

  print -P "%F{8}$(date '+%H:%M:%S')%f"
  print -P " %F{cyan}%BCPU%b%f  $cpu_name"
  print -P "        temp   %F{$(_sysmon_tcolor ${cpu_temp:-0} 70 90)}${ct}°C%f"
  print -P "        load   %F{white}${cl}%%%f"
  print -P " %F{magenta}%BGPU%b%f  $gpu_name"
  print -P "        temp   %F{$(_sysmon_tcolor ${gpu_temp:-0} 65 85)}${gt}°C%f"
  print -P "        load   %F{white}${gl}%%%f"
  print -P " %F{green}%BRAM%b%f  usage  %F{white}${rl}%%%f"
  print -P " %F{blue}%BFAN%b%f  fan1   %F{white}${f1} RPM%f   fan2   %F{white}${f2} RPM%f"
}

_sysmon_draw () {            # center and draw an already-collected snapshot
  emulate -L zsh
  setopt extended_glob

  local frame="$1" line plain
  local -a frame_lines
  local -i frame_width=0 line_width
  local -i frame_height cols rows left top row

  frame_lines=("${(@f)frame}")
  frame_height=${#frame_lines}

  # print -P emits SGR color sequences.  Ignore those non-printing bytes when
  # finding the width so that the visible frame, rather than its escapes, is
  # centered.  The frame contains no tabs or double-width characters.
  for line in "${frame_lines[@]}"; do
    plain=${line//$'\e'\[[0-9;]##m/}
    line_width=${#plain}
    (( line_width > frame_width )) && frame_width=$line_width
  done

  cols=${COLUMNS:-80}
  rows=${LINES:-24}
  (( left = cols > frame_width  ? (cols - frame_width) / 2 + 1 : 1 ))
  (( top  = rows > frame_height ? (rows - frame_height) / 2 + 1 : 1 ))

  # Erase the old placement after a resize, then clear each destination line
  # on ordinary refreshes so shorter values cannot leave trailing characters.
  (( $2 )) && printf '\e[2J'
  row=$top
  for line in "${frame_lines[@]}"; do
    printf '\e[%d;%dH\e[2K%s' "$row" "$left" "$line"
    (( ++row ))
  done
}

sysmon () {
  emulate -L zsh
  setopt local_traps no_monitor

  local interval="${1:-2}"
  local frame
  local -i interrupted=0 resized=1 clear_frame timer_pid

  # Keep the invoking shell intact and make signal handlers local to sysmon.
  tput smcup 2>/dev/null                                   # alternate screen
  tput civis 2>/dev/null                                   # hide cursor
  trap 'interrupted=1' HUP INT TERM
  trap 'resized=1' WINCH

  while (( ! interrupted )); do
    frame="$(_sysmon_frame)"
    (( interrupted )) && break
    (( clear_frame = resized, resized = 0 ))
    _sysmon_draw "$frame" "$clear_frame"

    # A foreground sleep delays WINCH traps until it exits.  Waiting on a
    # background timer lets a resize interrupt wait, so the cached frame can
    # be repositioned immediately without collecting the sensors again.
    sleep "$interval" &
    timer_pid=$!
    while kill -0 "$timer_pid" 2>/dev/null; do
      wait "$timer_pid" 2>/dev/null
      if (( interrupted )); then
        kill "$timer_pid" 2>/dev/null
        wait "$timer_pid" 2>/dev/null
        break
      fi
      (( clear_frame = resized, resized = 0 ))
      if (( clear_frame )); then
        _sysmon_draw "$frame" 1
      fi
    done
  done

  tput cnorm 2>/dev/null                                   # restore cursor
  tput rmcup 2>/dev/null                                   # restore shell screen
}
