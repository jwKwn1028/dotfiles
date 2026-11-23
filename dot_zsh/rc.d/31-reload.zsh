typeset -g _sz_all_file=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/zsh-reload-$EUID/request

_sz_all_check() {
  emulate -L zsh
  local file
  for file in "${ZDOTDIR:-$HOME}/.zshenv" "${ZDOTDIR:-$HOME}/.zshrc" \
      "$HOME/.zsh/macos/compat.zsh" "$HOME/.zsh/rc.d/_lib.zsh" \
      "$HOME/.zsh/rc.d"/[0-9]*.zsh(N); do
    [[ -r $file ]] || continue
    command zsh -fn "$file" || {
      print -u2 -- "sz-all: fix the syntax error in ${file/#$HOME/\~} and run sz-all again"
      return 1
    }
  done
}

unalias sz-all 2>/dev/null || true
sz-all() {
  emulate -L zsh
  [[ -o interactive && -z ${SSH_CONNECTION-}${SSH_CLIENT-}${SSH_TTY-} ]] || {
    print -u2 'sz-all: run from a local interactive shell'
    return 1
  }
  _sz_all_check || return
  local directory=${_sz_all_file:h} temporary
  [[ -d $directory ]] || command mkdir -m 700 -p -- "$directory" || return
  [[ -O $directory && ! -L $directory ]] || return 1
  temporary=$(command mktemp "$directory/request.XXXXXXXX") || return
  if print -r -- "$$:$RANDOM:$RANDOM" >| "$temporary" &&
      command mv -f -- "$temporary" "$_sz_all_file"; then
    print 'sz-all: local tmux shells will reload at their next prompt'
  else
    command rm -f -- "$temporary"
    return 1
  fi
}

_sz_all_precmd() {
  emulate -L zsh
  [[ -n ${TMUX-} && -z ${SSH_CONNECTION-}${SSH_CLIENT-}${SSH_TTY-} && -r $_sz_all_file ]] || return 0
  local request=$(<"$_sz_all_file")
  [[ -n $request && $request != $_sz_all_seen ]] || return 0
  (( ${#jobstates} == 0 )) || return 0
  _sz_all_seen=$request
  _sz_all_check || return 0
  if [[ -n ${HISTFILE-} ]] && ! builtin fc -AI; then
    return 0
  fi
  exec zsh
}

if [[ -o interactive && -n ${TMUX-} && -z ${SSH_CONNECTION-}${SSH_CLIENT-}${SSH_TTY-} ]]; then
  zmodload zsh/parameter
  typeset -g _sz_all_seen=''
  [[ ! -r $_sz_all_file ]] || _sz_all_seen=$(<"$_sz_all_file")
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _sz_all_precmd
fi
