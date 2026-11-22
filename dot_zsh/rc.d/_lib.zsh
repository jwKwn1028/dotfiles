# Shared helpers for the rc.d modules, sourced by ~/.zshrc before the numbered ones.
#
#   _have <cmd>   guard for optional tools on PATH
#   _zsh_fd -> fd | fdfind | ''     _zsh_bat -> bat | batcat | cat
#   _zsh_ls_files [-d] [ext...]  candidate paths under $PWD via fd or find(1):
#     hidden included, .git pruned, .gitignore NOT honored (else fd and the
#     find(1) fallback differ per machine). -d lists directories; exts filter.

_have() { whence -p -- "$1" >/dev/null 2>&1; }

if _have fd; then
  _zsh_fd=fd
elif _have fdfind; then
  _zsh_fd=fdfind
else
  _zsh_fd=
fi

if _have bat; then
  _zsh_bat=bat
elif _have batcat; then
  _zsh_bat=batcat
else
  _zsh_bat=cat
fi

_zsh_ls_files() {
  emulate -L zsh
  local kind=file ext
  [[ "$1" == -d ]] && { kind=dir; shift; }
  local -a exts=("$@")

  if [[ -n $_zsh_fd ]]; then
    local -a cmd=("$_zsh_fd" --hidden --no-ignore --exclude .git --strip-cwd-prefix)
    if [[ $kind == dir ]]; then
      cmd+=(--type d)
    else
      for ext in $exts; do cmd+=(-e "$ext"); done
    fi
    "${cmd[@]}"
  else
    local -a cmd=(find . -mindepth 1)
    if [[ $kind == dir ]]; then
      cmd+=(-type d)
    else
      cmd+=(-type f)
      if (( $#exts )); then
        cmd+=('(')
        for ext in $exts; do cmd+=(-iname "*.$ext" -o); done
        cmd[-1]=')'
      fi
    fi
    cmd+=(-not -path '*/.git' -not -path '*/.git/*' -print)
    "${cmd[@]}" | sed 's|^\./||'
  fi
}
