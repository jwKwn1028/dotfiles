# --------------------------------------------------------
# Universal Extract
# --------------------------------------------------------
ex() {
  emulate -L zsh
  (( $# )) || { print -u2 "usage: ex <archive>..."; return 2; }
  local a
  for a in "$@"; do
    [[ -f "$a" ]] || { print -u2 "ex: '$a' is not a valid file"; return 1; }
    # tar.* patterns must precede the bare-compressor ones so foo.tar.gz
    # untars instead of merely gunzipping.
    case "$a" in
      *.tar.bz2)        tar xjf "$a"        ;;
      *.tar.gz)         tar xzf "$a"        ;;
      *.tar.xz)         tar xJf "$a"        ;;
      *.tar.zst|*.tzst) tar --zstd -xf "$a" ;;
      *.tar)            tar xf "$a"         ;;
      *.tbz2)           tar xjf "$a"        ;;
      *.tgz)            tar xzf "$a"        ;;
      *.bz2)            bunzip2 "$a"        ;;
      *.gz)             gunzip "$a"         ;;
      *.xz)             unxz "$a"           ;;
      *.zst)            unzstd "$a"         ;;
      *.rar)            unrar x "$a"        ;;
      *.zip)            unzip "$a"          ;;
      *.Z)              uncompress "$a"     ;;
      *.7z)             7z x "$a"           ;;
      *)                print -u2 "ex: don't know how to extract '$a'"; return 1 ;;
    esac || return
  done
}

# --------------------------------------------------------
# PDF / EPUB pickers
# --------------------------------------------------------
# One implementation; so/zo just choose the preferred viewer:
#   so -> sioyek first, zathura as fallback
#   zo -> zathura first, sioyek as fallback
# With a path argument the viewer opens it directly; bare, fzf picks.
_zsh_open_pdf() {
  emulate -L zsh
  local caller="${funcstack[2]:-open-pdf}"
  local prefer="$1" viewer v file
  local -a order
  shift

  case "$prefer" in
    zathura) order=(zathura sioyek) ;;
    *)       order=(sioyek zathura) ;;
  esac
  for v in "${order[@]}"; do
    if _have "$v"; then
      viewer="$v"
      break
    fi
  done
  if [[ -z "$viewer" ]]; then
    print -u2 "$caller: neither sioyek nor zathura installed"
    return 127
  fi

  if [[ -n "$1" ]]; then
    file="$1"
    [[ -f "$file" ]] || { print -u2 "$caller: '$file' not found"; return 1; }
  else
    _have fzf || { print -u2 "$caller: fzf not found"; return 127; }
    file="$(_zsh_ls_files pdf | fzf --prompt='Open PDF> ')" || return
    [[ -n "$file" ]] || return 1
  fi

  case "$viewer" in
    # --new-window overrides our hxp-tuned `should_launch_new_window 0` pref so
    # ad-hoc browsing opens each PDF in its own window instead of replacing
    # the hxp preview window.
    sioyek)  sioyek --new-window "$file" >/dev/null 2>&1 &! ;;
    zathura) zathura "$file"             >/dev/null 2>&1 &! ;;
  esac
}

so() { _zsh_open_pdf sioyek "$@"; }
zo() { _zsh_open_pdf zathura "$@"; }

bo() {
  emulate -L zsh
  local file

  _have ebook-viewer || { print -u2 "bo: ebook-viewer not found"; return 127; }

  if [[ -n "$1" ]]; then
    file="$1"
    [[ -f "$file" ]] || { print -u2 "bo: '$file' not found"; return 1; }
  else
    _have fzf || { print -u2 "bo: fzf not found"; return 127; }
    file="$(_zsh_ls_files epub | fzf --prompt='Open EPUB> ')" || return
    [[ -n "$file" ]] || return 1
  fi

  ebook-viewer "$file" >/dev/null 2>&1 &!
}

# --------------------------------------------------------
# File manager
# --------------------------------------------------------
# Bare `thunar` opens $PWD rather than $HOME, and detaches so the terminal
# stays usable. `command` keeps ~/.local/bin/thunar (the GTK_THEME wrapper)
# in play; the .desktop and systemd launch paths never see this function.
thunar() {
  emulate -L zsh
  command thunar "${@:-$PWD}" >/dev/null 2>&1 &!
}
