# --- zoxide ---
if _have zoxide; then
  eval "$(zoxide init zsh --cmd cd)"
fi

cd() {
  if (( $# == 1 )) && [[ $1 =~ '^--+$' ]]; then
    builtin cd "+${#1}"
  elif (( ${+functions[__zoxide_z]} )); then
    __zoxide_z "$@"
  else
    builtin cd "$@"
  fi
}

# --- Auto-list on cd ---
# List names only, without per-file Git status; skip large directories.
if _have eza; then
  AUTO_LS_MAX=${AUTO_LS_MAX:-50}

  _auto_ls() {
    emulate -L zsh
    local -a entries=(*(N))
    (( $#entries && $#entries <= AUTO_LS_MAX )) || return
    eza --color=auto --icons
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook chpwd _auto_ls
fi

# --- nnn ---
n() {
  emulate -L zsh
  setopt localoptions

  _have nnn || { print -u2 "n: nnn not found"; return 127; }

  local NNN_TMPFILE rc
  NNN_TMPFILE="$(mktemp "${TMPDIR:-/tmp}/nnn-cd.XXXXXX")" || return 1
  export NNN_TMPFILE

  command nnn "$@"
  rc=$?
  if (( rc == 0 )) && [[ -s "$NNN_TMPFILE" ]]; then
    source "$NNN_TMPFILE" || rc=$?
  fi
  rm -f -- "$NNN_TMPFILE"
  return $rc
}
alias np='n "$HOME/Documents/Workspace/Project"'

# --- ranger ---
r() {
  emulate -L zsh
  setopt localoptions

  _have ranger || { print -u2 "r: ranger not found"; return 127; }

  local start_dir="${1:-$PWD}" tmp dest rc
  tmp="$(mktemp "${TMPDIR:-/tmp}/ranger-cd.XXXXXX")" || return 1

  command ranger --choosedir="$tmp" -- "$start_dir"
  rc=$?
  if (( rc == 0 )); then
    dest="$(<"$tmp")"
    if [[ -n "$dest" && "$dest" != "$PWD" ]]; then
      builtin cd -- "$dest" || rc=$?
    fi
  fi
  rm -f -- "$tmp"
  return $rc
}
alias rp='r "$HOME/Documents/Workspace/Project"'

# --- Yazi ---
y() {
  emulate -L zsh
  setopt localoptions

  _have yazi || { print -u2 "y: yazi not found"; return 127; }

  local tmp cwd rc
  tmp="$(mktemp "${TMPDIR:-/tmp}/yazi-cwd.XXXXXX")" || return 1

  command yazi "$@" --cwd-file="$tmp"
  rc=$?
  if (( rc == 0 || rc == 10 )); then
    cwd="$(<"$tmp")"
    if [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
      builtin cd -- "$cwd" || rc=$?
    fi
  fi
  rm -f -- "$tmp"
  if (( rc == 10 )); then
    _close_gui_terminal
    return 0
  fi
  return $rc
}
alias yp='y "$HOME/Documents/Workspace/Project"'
alias yd='y "$HOME/Downloads"'
alias yl='y "$HOME/Documents/Workspace/Known/Paper/Library/Library"'

yc() {
  emulate -L zsh
  local source_dir
  source_dir=$(command chezmoi source-path) || return
  y "$source_dir" "$@"
}

yr() {
  emulate -L zsh
  local repo_root
  repo_root=$(command git rev-parse --show-toplevel) || return
  y "$repo_root" "$@"
}
