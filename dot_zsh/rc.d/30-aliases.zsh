# --------------------------------------------------------
# Aliases
# --------------------------------------------------------
alias twt='taskwarrior-tui'
alias v='vim .'
alias c='code .'
alias h='hx .'
alias z='zed .'
alias vi='vim'
alias mu='micro'
alias ls='eza --color=auto --icons --long --git --no-user --no-permissions'
(( $+commands[batcat] )) && alias bat='batcat'
alias hz='${EDITOR:-hx} ~/.zsh/rc.d'   # config now lives in modules (was ~/.zshrc)
alias sz='source ~/.zshrc && print "Zsh config reloaded."'
if command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
fi
alias scpo='print "shutting down..." && systemctl poweroff'
alias scrb='print "reboot ..." && systemctl reboot'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# --------------------------------------------------------
# Ripgrep (rg)
# --------------------------------------------------------
alias rg='rg --smart-case'

# --------------------------------------------------------
# Taskwarrior quick-add by weekday
# --------------------------------------------------------
# Name patterns:
#   t<t|n><D><d|s>
#   t<t|n><D><d|s><HH:MM>
#   tt = this week          tn = next week
#   D  = ISO weekday, 1=Mon .. 7=Sun
#   d  = due                s  = scheduled
# Examples:
#   tt4s prep slides        -> scheduled Thursday this week
#   tt2s16:30 golf          -> scheduled Tuesday this week at 16:30
#   tn2d dentist +health    -> due Tuesday next week
#   tt1d retro              -> due Monday this week (may be in the past)
# The date is computed here (not via Taskwarrior's ambiguous weekday
# synonym); trailing args (+tag, project:x, ...) pass on to `task add`.
_task_when() {   # <this|next> <ISO-dow 1-7>  ->  YYYY-MM-DD
  emulate -L zsh
  local base=$1 d=$2 dow off
  dow=$(date +%u)
  off=$(( d - dow ))
  [[ $base == next ]] && (( off += 7 ))
  date -d "$off days" +%F
}

_task_quick_add() {   # <this|next> <ISO-dow> <due|scheduled> <HH:MM|''> <args...>
  emulate -L zsh
  local base=$1 d=$2 attr=$3 at=$4 when
  shift 4
  when=$(_task_when "$base" "$d") || return
  [[ -n $at ]] && when+=T$at
  task add "$@" "$attr:$when"
}

() {   # define the 28 shortcuts: {tt,tn} x {1..7} x {d,s}
  emulate -L zsh
  local wk wname D sf attr
  for wk wname in tt this tn next; do
    for D in {1..7}; do
      for sf attr in d due s scheduled; do
        functions[$wk$D$sf]="(( \$# )) || { print -u2 \"usage: $wk$D$sf <description> [+tag project:x ...]\"; return 2 }
_task_quick_add $wname $D $attr '' \"\$@\""
      done
    done
  done
}

# A time is part of the command name, so there cannot be a finite set of
# predeclared functions for it. Recognize timed shortcuts only after normal
# command lookup fails, and delegate all other misses to any existing handler.
if (( $+functions[command_not_found_handler] )) &&
   [[ ${functions[command_not_found_handler]} != *'_task_quick_add'* ]]; then
  functions[_task_command_not_found_fallback]=$functions[command_not_found_handler]
fi

command_not_found_handler() {
  emulate -L zsh
  local shortcut=$1

  if [[ $shortcut =~ '^(tt|tn)([1-7])([ds])(([01][0-9]|2[0-3]):[0-5][0-9])$' ]]; then
    local -a parts=( "${match[@]}" )
    shift
    (( $# )) || {
      print -u2 "usage: $shortcut <description> [+tag project:x ...]"
      return 2
    }

    local base=this attr=due
    [[ ${parts[1]} == tn ]] && base=next
    [[ ${parts[3]} == s ]] && attr=scheduled
    _task_quick_add "$base" "${parts[2]}" "$attr" "${parts[4]}" "$@"
    return $?
  fi

  if (( $+functions[_task_command_not_found_fallback] )); then
    _task_command_not_found_fallback "$@"
    return $?
  fi

  print -u2 -- "zsh: command not found: $shortcut"
  return 127
}
