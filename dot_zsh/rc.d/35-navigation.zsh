# --------------------------------------------------------
# zoxide
# --------------------------------------------------------
if command -v zoxide >/dev/null 2>&1; then
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

  command -v ranger >/dev/null 2>&1 || { print -u2 "r: ranger not found"; return 127; }

  command ranger --choosedir="$tempfile" -- "$start_dir" || return

  dest="$(<"$tempfile")"
  [[ -n "$dest" && "$dest" != "$PWD" ]] && builtin cd -- "$dest"
}

alias rp='r "$HOME/Documents/Workspace/Project"'

# --------------------------------------------------------
# Yazi
# --------------------------------------------------------
y() {
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
}

alias yp='y "$HOME/Documents/Workspace/Project"'
