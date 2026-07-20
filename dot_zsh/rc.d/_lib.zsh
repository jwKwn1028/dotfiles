# --------------------------------------------------------
# Shared helpers for the rc.d modules
# --------------------------------------------------------
# Sourced by ~/.zshrc before the numbered modules.

# Resolve tool variants once so every module agrees on the same binary.
#   _zsh_fd  -> fd | fdfind | ''    (Debian/Ubuntu package fd as fdfind)
#   _zsh_bat -> bat | batcat | cat
if whence -p fd >/dev/null; then
  _zsh_fd=fd
elif whence -p fdfind >/dev/null; then
  _zsh_fd=fdfind
else
  _zsh_fd=
fi

if whence -p bat >/dev/null; then
  _zsh_bat=bat
elif whence -p batcat >/dev/null; then
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
