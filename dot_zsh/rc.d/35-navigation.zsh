# --------------------------------------------------------
# zoxide
# --------------------------------------------------------
if _have zoxide; then
  eval "$(zoxide init zsh --cmd cd)"
fi

cd() {
  if (( $# == 1 )) && [[ $1 =~ '^--+$' ]]; then
    builtin cd "+${#1}"
  elif (( ${+functions[__zoxide_z] )); then
    __zoxide_z "$@"
  else
    builtin cd "$@"
  fi
}

# --------------------------------------------------------
# Auto-list on cd
# --------------------------------------------------------
# Names only: the `ls` alias in 30-aliases.zsh adds --long --git, which costs a
# git status per file. This runs on every directory change, so it stays a plain
# grid -- one fork, no git.
#
# Skipped past AUTO_LS_MAX entries so `cd /usr/bin` does not scroll the screen
# away. The count comes from a glob rather than `eza | wc -l` so the common case
# forks once, not twice; (N) matches eza's default of hiding dotfiles.
#
# 50: this repo's root is 41 entries, so the original 40 cap silently did
# nothing in a directory used constantly. 50 clears that without letting a
# genuinely large directory take over the screen.
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
