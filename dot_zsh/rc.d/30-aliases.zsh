# --- Aliases ---
_have taskwarrior-tui && alias twt='taskwarrior-tui'
alias tcal='task-calendar'
if _have vim; then
  alias v='vim .'
  alias vi='vim'
fi
_have hx && alias h='hx .'
_have micro && alias mo='micro'
_have eza && alias ls='eza --color=auto --icons --long --git --no-user --no-permissions'
(( $+commands[batcat] )) && alias bat='batcat'
if _have tlp; then
  alias tlp-bat='sudo tlp-stat -b'
  alias tlp-full='sudo tlp setcharge 90 95 BAT0'
  alias tlp-restore='sudo tlp setcharge BAT0'
fi
unalias c z 2>/dev/null || true
# Close local Ghostty shells before GUI launches to preserve keyboard focus.
_close_gui_terminal() {
  if [[ -o interactive && $TERM_PROGRAM == ghostty && -z $TMUX && -z $SSH_CONNECTION ]]; then
    (( $# )) && { ( sleep 0.05; "$@" ) </dev/null >/dev/null 2>&1 &! }
    exit 0
  fi
  (( $# == 0 )) || "$@"
}
_open_gui_editor() {
  emulate -L zsh
  (( $+commands[$1] )) || { print -u2 -- "$1 not found"; return 127; }
  _close_gui_terminal command "$1" .
}
c() { _open_gui_editor code }
z() { _open_gui_editor zed }
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
alias ':qa'='i3-msg -q kill'
if _have fdfind; then
  alias fd='fdfind'
fi
unalias scpo poweroff 2>/dev/null || true
poweroff() {
  command poweroff-confirm "$@"
}
unalias wtail 2>/dev/null || true
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

# --- tmux ---
alias t='tmux new -A -s main'
alias tl='tmux ls'
alias tn='tmux new -s'
alias tk='tmux kill-session -t'

# tm [NAME]: attach, create, or pick; switches inside tmux.
tm() {
  local s=${1-}
  [[ -n $s ]] || s=$(tmux ls -F '#S' 2>/dev/null | fzf --height=40% --reverse --preview= --prompt='tmux> ') || return
  if [[ -n ${TMUX-} ]]; then
    tmux has -t "=$s" 2>/dev/null || tmux new -d -s "$s"
    tmux switch-client -t "=$s"
  else
    _ghostty_tmux_mode on
    { tmux new -A -s "$s" } always { _ghostty_tmux_mode off }
  fi
}

# ta [NAME]: restore once, then attach.
_tmux_restore_if_empty() {
  if (( $+commands[tmux-restore-if-empty] )); then
    tmux-restore-if-empty "$@"
  elif ! tmux has-session 2>/dev/null; then
    print -u2 'ta: tmux-restore-if-empty not found; cannot restore tmux'
    return 1
  fi
}

(( ${+aliases[ta]} )) && unalias ta
ta() {
  local s=${1-}
  _tmux_restore_if_empty "$s" || return
  if [[ -z $s ]]; then
    local -a names=(${(f)"$(tmux ls -F '#S' 2>/dev/null)"})
    (( $#names )) || { print -u2 'ta: no tmux sessions'; return 1 }
    if (( $#names == 1 )); then
      s=$names[1]
    else
      s=$(print -rl -- $names | fzf --disabled --no-sort --reverse --height=40% --info=hidden --preview= \
        --prompt='' --header='j/k move, Enter attach, q/Esc cancel' \
        --bind='j:down,k:up,J:down,K:up,q:abort') || return
    fi
  fi
  if [[ -n ${TMUX-} ]]; then
    tmux switch-client -t "=$s"
  else
    _ghostty_tmux_mode on
    { I3_RESURRECT_TMUX_CLIENT="${_i3_resurrect_tmux_client-}" tmux attach -t "=$s" } always { _ghostty_tmux_mode off }
  fi
}

if [[ -o interactive && -n ${I3_RESURRECT_LOCAL_TMUX-} ]]; then
  _i3_restore_local_tmux() {
    add-zsh-hook -d precmd _i3_restore_local_tmux
    local encoded=$I3_RESURRECT_LOCAL_TMUX session
    unset I3_RESURRECT_LOCAL_TMUX
    session=$(print -rn -- "$encoded" | base64 --decode) || return 0
    local _i3_resurrect_tmux_client=1
    [[ -n $session ]] && ta "$session"
    return 0
  }
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _i3_restore_local_tmux
fi

# Include Codex's chat ID in pane titles for tmux recovery.
_have codex && codex() {
  [[ -z ${TMUX-} ]] || set -- -c 'tui.terminal_title=["thread-id","thread-title"]' "$@"
  command codex "$@"
}

# Task shortcuts: t<W><D><d|s>[hml][HH:MM][r<offsets>]; see task/MANUAL.md.
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

  # Date-only tasks are valid through today.
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

# Parse extended task shortcuts after normal command lookup fails.
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
