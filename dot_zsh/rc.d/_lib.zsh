# Shared helpers for the rc.d modules. Sourced by ~/.zshrc before the numbered
# ones.
#
# _have <cmd> is the shared "is this optional tool on PATH" guard.
#
# Tool variants are resolved once so every module agrees on the same binary:
#   _zsh_fd  -> fd | fdfind | ''    (Debian/Ubuntu package fd as fdfind)
#   _zsh_bat -> bat | batcat | cat
#
# _zsh_ls_files [-d] [ext] prints candidate paths under $PWD, via fd or find(1):
# hidden included, .git pruned, .gitignore NOT honored -- fd would otherwise hide
# files the find(1) fallback lists, making the same call differ per machine. -d
# lists directories; ext restricts by extension, case-insensitively.

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
  ext="$1"

  if [[ -n $_zsh_fd ]]; then
    local -a cmd=("$_zsh_fd" --hidden --no-ignore --exclude .git --strip-cwd-prefix)
    if [[ $kind == dir ]]; then
      cmd+=(--type d)
    elif [[ -n $ext ]]; then
      cmd+=(-e "$ext")
    fi
    "${cmd[@]}"
  else
    local -a cmd=(find . -mindepth 1)
    if [[ $kind == dir ]]; then
      cmd+=(-type d)
    else
      cmd+=(-type f)
      [[ -n $ext ]] && cmd+=(-iname "*.$ext")
    fi
    cmd+=(-not -path '*/.git' -not -path '*/.git/*' -print)
    "${cmd[@]}" | sed 's|^\./||'
  fi
}
