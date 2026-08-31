# --- Aliases ---
alias twt='taskwarrior-tui'
alias v='vim .'
alias c='code .'
alias h='hx .'
alias z='zed .'
alias vi='vim'
alias mo='micro'
alias ls='eza --color=auto --icons --long --git --no-user --no-permissions'
(( $+commands[batcat] )) && alias bat='batcat'
btop () {
  emulate -L zsh
  if [[ $TERM_PROGRAM != ghostty ]] || (( ! $+commands[xdotool] )); then
    command btop "$@"
    return
  fi
  xdotool key --clearmodifiers ctrl+minus ctrl+minus ctrl+minus
  sleep 0.15
  command btop "$@"
  xdotool key --clearmodifiers ctrl+0
}
alias hz='${EDITOR:-hx} ~/.zsh/rc.d'   # config now lives in modules (was ~/.zshrc)
alias sz='print "reloading zsh..." && exec zsh'   # full restart: re-reads .zshenv + rc.d without double-wrapping ZLE widgets
alias ':q'='exit'
alias ':qa'='xdotool key --clearmodifiers alt+F4'
if _have fdfind; then
  alias fd='fdfind'
fi
alias scpo='print "shutting down..." && systemctl poweroff'
alias wtail='watch -d -n 10 tail -v -n 10'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# --- Ripgrep (rg) ---
alias rg='rg --smart-case'

# --- Taskwarrior quick-add by weekday ---
#   t<W><D><d|s>[hml][HH:MM][r<offsets>]   W = weeks ahead 0-4, D = ISO weekday
#   d = due, s = scheduled, h/m/l = priority, r = reminder offsets (bare = hours)
# e.g. t04s prep slides / t12sm16:30r1d,2 golf.  See ~/.config/task/MANUAL.md.
_task_when() {   # <weeks ahead 0-4> <ISO-dow 1-7>  ->  YYYY-MM-DD
  emulate -L zsh
  local wk=$1 d=$2 dow off
  dow=$(date +%u)
  off=$(( d - dow + 7 * wk ))
  date -d "$off days" +%F
}

_task_quick_add() {   # <name> <weeks> <ISO-dow> <due|scheduled> <HH:MM|''> <h|m|l|''> <offsets|''> <args...>
  emulate -L zsh
  local name=$1 wk=$2 d=$3 attr=$4 at=$5 priority=$6 remind=$7 when suggestion
  local -a mods
  shift 7
  when=$(_task_when "$wk" "$d") || return
  [[ -n $at ]] && when+=T$at

  # A past date can never fire a reminder; bare shortcuts have no time, so they
  # are judged on the day.
  if [[ -n $at ]] && (( $(date -d "$when" +%s) <= $(date +%s) )) ||
     [[ -z $at && $when < $(date +%F) ]]; then
    (( wk < 4 )) && suggestion="t$(( wk + 1 ))${name#t?}"
    print -u2 "$name: $(date -d "$when" '+%a %F') is in the past${suggestion:+ (did you mean $suggestion?)}"
    return 2
  fi

  mods=( "$attr:$when" )
  [[ -n $priority ]] && mods+=( "priority:${(U)priority}" )
  if [[ -n $remind ]]; then
    # Rejected here rather than stored: task-notify would only skip it.
    [[ $remind =~ '^[0-9]+(\.[0-9]+)?[mhd]?(,[0-9]+(\.[0-9]+)?[mhd]?)*$' ]] || {
      print -u2 "$name: invalid reminder offsets: $remind (e.g. 1d,2,30m)"
      return 2
    }
    mods+=( "remind:$remind" )
  fi
  task add "$@" "${mods[@]}"
}

() {   # define the 70 shortcuts: {0..4} x {1..7} x {d,s}
  emulate -L zsh
  local wk D sf attr name
  for wk in {0..4}; do
    for D in {1..7}; do
      for sf attr in d due s scheduled; do
        name=t$wk$D$sf
        functions[$name]="(( \$# )) || { print -u2 \"usage: $name <description> [+tag project:x ...]\"; return 2 }
_task_quick_add $name $wk $D $attr '' '' '' \"\$@\""
      done
    done
  done
}

# Time and priority suffixes are part of the command name, so no finite set of
# functions covers them. Recognize extended shortcuts after normal lookup fails;
# delegate other misses.
if (( $+functions[command_not_found_handler] )) &&
   [[ ${functions[command_not_found_handler]} != *'_task_quick_add'* ]]; then
  functions[_task_command_not_found_fallback]=$functions[command_not_found_handler]
fi

command_not_found_handler() {
  emulate -L zsh
  local shortcut=$1

  if [[ $shortcut =~ '^t([0-4])([1-7])([ds])([hml])?(([01][0-9]|2[0-3]):[0-5][0-9])?(r([0-9.,dhm]+))?$' ]]; then
    local -a parts=( "${match[@]}" )
    shift
    (( $# )) || {
      print -u2 "usage: $shortcut <description> [+tag project:x ...]"
      return 2
    }

    local attr=due
    [[ ${parts[3]} == s ]] && attr=scheduled
    _task_quick_add "$shortcut" "${parts[1]}" "${parts[2]}" "$attr" \
      "${parts[5]}" "${parts[4]}" "${parts[8]}" "$@"
    return $?
  fi

  if (( $+functions[_task_command_not_found_fallback] )); then
    _task_command_not_found_fallback "$@"
    return $?
  fi

  print -u2 -- "zsh: command not found: $shortcut"
  return 127
}
