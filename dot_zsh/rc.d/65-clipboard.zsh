# --------------------------------------------------------
# Clipboard helper: shared with tmux via ~/.local/bin/clipcopy
# --------------------------------------------------------
_clipcopy() {
  if _have clipcopy; then
    clipcopy
  else
    print -u2 "_clipcopy: ~/.local/bin/clipcopy not found."
    return 127
  fi
}

# Postfix pipeline shorthand: command Y
alias -g Y='| _clipcopy'

crpf() {
  emulate -L zsh
  setopt localoptions
  local p
  p="$(fzf --prompt='file> ')" || return 130
  print -rn -- "$p" | _clipcopy
  print -r -- "$p"
}

crpd() {
  emulate -L zsh
  setopt localoptions
  local p
  p="$(_zsh_ls_files -d | fzf --prompt='dir> ')" || return 130
  print -rn -- "$p" | _clipcopy
  print -r -- "$p"
}
