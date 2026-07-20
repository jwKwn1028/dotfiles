# --------------------------------------------------------
# Universal Extract
# --------------------------------------------------------
ex () {
  if [ -f "$1" ] ; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1"   ;;
      *.tar.gz)    tar xzf "$1"   ;;
      *.bz2)       bunzip2 "$1"   ;;
      *.rar)       unrar x "$1"   ;;
      *.gz)        gunzip "$1"    ;;
      *.tar)       tar xf "$1"    ;;
      *.tbz2)      tar xjf "$1"   ;;
      *.tgz)       tar xzf "$1"   ;;
      *.zip)       unzip "$1"     ;;
      *.Z)         uncompress "$1";;
      *.7z)        7z x "$1"      ;;
      *.tar.xz)    tar xJf "$1"   ;;
      *.xz)        unxz "$1"      ;;
      *)           echo "'$1' cannot be extracted via ex()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# --------------------------------------------------------
# PDF / EPUB pickers
# --------------------------------------------------------
# One implementation; so/zo just choose the preferred viewer:
#   so -> sioyek first, zathura as fallback
#   zo -> zathura first, sioyek as fallback
# (The old standalone zo had its checks inverted and launched whichever
# viewer it had just confirmed missing.)
_zsh_open_pdf() {
  emulate -L zsh
  local caller="${funcstack[2]:-open-pdf}"
  local prefer="$1" viewer v file
  local -a order

  command -v fzf >/dev/null 2>&1 || { print -u2 "$caller: fzf not found"; return 127; }

  case "$prefer" in
    zathura) order=(zathura sioyek) ;;
    *)       order=(sioyek zathura) ;;
  esac
  for v in "${order[@]}"; do
    if command -v "$v" >/dev/null 2>&1; then
      viewer="$v"
      break
    fi
  done
  if [[ -z "$viewer" ]]; then
    print -u2 "$caller: neither sioyek nor zathura installed"
    return 127
  fi

  file="$(_zsh_ls_files pdf | fzf --prompt='Open PDF> ')" || return 1
  [[ -n "$file" ]] || return 1

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

  command -v fzf >/dev/null 2>&1 || { print -u2 "bo: fzf not found"; return 127; }
  command -v ebook-viewer >/dev/null 2>&1 || { print -u2 "bo: ebook-viewer not found"; return 127; }

  file="$(_zsh_ls_files epub | fzf --prompt='Open EPUB> ')" || return 1
  [[ -n "$file" ]] || return 1

  ebook-viewer "$file" >/dev/null 2>&1 &!
}
