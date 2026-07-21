# --------------------------------------------------------
# Shared helpers for the rc.d modules
# --------------------------------------------------------
# Sourced by ~/.zshrc before the numbered modules.

# _have <cmd>  ->  succeeds if <cmd> is an external command on PATH.
# Centralizes the `command -v x >/dev/null 2>&1` / `whence -p x` guard that the
# numbered modules would otherwise repeat for every optional tool.
_have() { whence -p -- "$1" >/dev/null 2>&1; }

# Resolve tool variants once so every module agrees on the same binary.
#   _zsh_fd  -> fd | fdfind | ''    (Debian/Ubuntu package fd as fdfind)
#   _zsh_bat -> bat | batcat | cat
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

# _zsh_ls_files [-d] [ext]
#   Print candidate paths under $PWD: hidden included, .git pruned.
#   -d lists directories instead; ext restricts to files with that
#   extension (case-insensitive). fd/fdfind when available, find(1)
#   otherwise. Replaces the fd -> fdfind -> find ladders that were
#   copy-pasted into so/zo/bo/crpd.
_zsh_ls_files() {
  emulate -L zsh
  local kind=file ext
  [[ "$1" == -d ]] && { kind=dir; shift; }
  ext="$1"

  if [[ -n $_zsh_fd ]]; then
    local -a cmd=("$_zsh_fd" --hidden --exclude .git --strip-cwd-prefix)
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
