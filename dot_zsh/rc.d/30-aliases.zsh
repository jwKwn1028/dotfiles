# --- Aliases ---
alias twt='taskwarrior-tui'
alias tcal='task-calendar'
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
unalias hz 2>/dev/null || true
hz() {   # edit zsh config in the chezmoi source; files differing from live open directly
  emulate -L zsh
  local line target src
  local -a files targets=(~/.zshenv ~/.zprofile ~/.zshrc ~/.zsh)

  if (( ! $+commands[chezmoi] )); then
    ${EDITOR:-hx} ~/.zsh/rc.d
    return
  fi

  for line in ${(f)"$(chezmoi status -x externals,scripts -- $targets)"}; do
    target=$HOME/${line[4,-1]}
    [[ ${line[1]} != ' ' && -e $target ]] && files+=($target)   # edited live: open both sides
    src=$(chezmoi source-path -- $target 2>/dev/null) && files+=($src)
  done
  (( $#files )) || files=("$(chezmoi source-path -- ~/.zsh/rc.d)")

  ${EDITOR:-hx} $files

  local changes=$(chezmoi --color=true diff --no-pager -r -x externals,scripts -- $targets)   # diff, unlike apply, doesn't recurse by default
  [[ -n $changes ]] || return 0
  print -r -- $changes | less -FRX
  if read -q "?hz: apply to live config? [y/N] "; then
    print
    chezmoi apply -x externals,scripts -- $targets && print "hz: applied; run sz to reload"
  else
    print "\nhz: not applied"
  fi
}
unalias sz 2>/dev/null || true
sz() {   # full restart (no double-wrapped ZLE widgets); shows config changes first
  emulate -L zsh
  local f old new old_label new_label
  local -a reply changed

  if (( ${+_zshrc_snap} && ${+functions[_zshrc_modules]} )); then
    _zshrc_modules
    for f in ${(k)_zshrc_snap} $reply; do
      if (( ${+_zshrc_snap[$f]} )); then
        [[ -r $f && $_zshrc_snap[$f] == "$(<$f)" ]] && continue
      else
        [[ -r $f ]] || continue
      fi
      changed+=($f)
    done
    changed=(${(ou)changed})
  fi

  if (( $#changed )); then
    for f in $changed; do
      old_label=/dev/null new_label=/dev/null old= new=
      (( ${+_zshrc_snap[$f]} )) && old_label=${f/#$HOME/\~} old=$_zshrc_snap[$f]
      [[ -r $f ]] && new_label=${f/#$HOME/\~} new=$(<$f)
      diff -u --color=always --label $old_label --label $new_label \
        <(print -rn -- ${old:+$old$'\n'}) <(print -rn -- ${new:+$new$'\n'})
    done | less -FRX
    for f in $changed; do   # exec into a config that won't parse leaves a broken shell
      [[ -r $f ]] && ! zsh -fn $f && {
        print -u2 "sz: not reloading; fix the syntax error in ${f/#$HOME/\~}"
        return 1
      }
    done
  fi

  print "reloading zsh..."
  exec zsh
}
alias ':q'='exit'
alias ':qa'='xdotool key --clearmodifiers alt+F4'
if _have fdfind; then
  alias fd='fdfind'
fi
unalias scpo poweroff 2>/dev/null || true
poweroff() {
  local host reply

  if [ "$#" -ne 0 ]; then
    printf 'poweroff wrapper accepts no arguments\n' >&2
    return 2
  fi

  host=$(command hostname -s) || return 1
  printf 'Power off %s? [y/N] (10s timeout): ' "$host" >/dev/tty ||
    return 1

  IFS= read -r -t 10 reply </dev/tty || {
    printf '\nNo confirmation received; cancelled.\n'
    return 1
  }

  case "$reply" in
    [yY] | [yY][eE][sS]) command systemctl poweroff ;;
    *) printf 'Cancelled.\n'; return 1 ;;
  esac
}
wtail() {   # absolutise args so tail -v headers name the full path
  emulate -L zsh
  local f
  local -a files

  if (( $# == 0 )); then
    printf 'usage: wtail FILE...\n' >&2
    return 2
  fi

  for f in "$@"; do
    files+=("${f:a}")
  done
  watch -x -d -n 10 tail -v -n 10 "${files[@]}"
}

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
