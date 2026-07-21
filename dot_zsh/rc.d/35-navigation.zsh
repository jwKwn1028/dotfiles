# --------------------------------------------------------
# zoxide
# --------------------------------------------------------
if _have zoxide; then
  eval "$(zoxide init zsh --cmd cd)"
fi

cd() {
  if (( $# == 1 )) && [[ $1 =~ '^--+$' ]]; then
    builtin cd "+${#1}"
  elif (( $+functions[__zoxide_z] )); then
    __zoxide_z "$@"
  else
    builtin cd "$@"
  fi
}

# --------------------------------------------------------
# ranger
# --------------------------------------------------------
r() {
  emulate -L zsh
  setopt localoptions localtraps

  local start_dir="${1:-$PWD}"
  local tempfile dest

  tempfile="$(mktemp "${TMPDIR:-/tmp}/ranger-cd.XXXXXX")" || return 1
  trap 'rm -f -- "$tempfile"' EXIT

  _have ranger || { print -u2 "r: ranger not found"; return 127; }

  command ranger --choosedir="$tempfile" -- "$start_dir" || return

  dest="$(<"$tempfile")"
  [[ -n "$dest" && "$dest" != "$PWD" ]] && builtin cd -- "$dest"
}

alias rp='r "$HOME/Documents/Workspace/Project"'

# --------------------------------------------------------
# Yazi
# --------------------------------------------------------
y() {
  emulate -L zsh
  setopt localoptions localtraps

  local tmp cwd
  tmp="$(mktemp "${TMPDIR:-/tmp}/yazi-cwd.XXXXXX")" || return 1
  trap 'rm -f -- "$tmp"' EXIT

  _have yazi || { print -u2 "y: yazi not found"; return 127; }

  yazi "$@" --cwd-file="$tmp"

  cwd="$(<"$tmp")"
  [[ -n "$cwd" && "$cwd" != "$PWD" ]] && builtin cd -- "$cwd"
}

alias yp='y "$HOME/Documents/Workspace/Project"'
