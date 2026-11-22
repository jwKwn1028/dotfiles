# macOS compatibility prelude for the unchanged rc.d modules.
# Source this from ~/.zshenv so PATH and clipboard variables are ready before
# ~/.zshrc loads _lib.zsh and the numbered modules.
#
# The narrow shims stay ahead of both Homebrew and Apple's system utilities.
# zsh-helix-mode only auto-detects X11 and Wayland, so an explicit override is
# respected and the native macOS clipboard commands are used otherwise.

[[ $OSTYPE == darwin* ]] || return 0

typeset -gU path PATH
typeset -g MACOS_ZSH_COMPAT_ROOT="${${(%):-%N}:A:h}"
typeset -aU _macos_compat_prefixes _macos_compat_paths
typeset _macos_compat_prefix

[[ -n ${HOMEBREW_PREFIX:-} ]] &&
  _macos_compat_prefixes+=("$HOMEBREW_PREFIX")
_macos_compat_prefixes+=(/opt/homebrew /usr/local)

for _macos_compat_prefix in "${_macos_compat_prefixes[@]}"; do
  [[ -d "$_macos_compat_prefix/opt/rsync/bin" ]] &&
    _macos_compat_paths+=("$_macos_compat_prefix/opt/rsync/bin")
  [[ -d "$_macos_compat_prefix/bin" ]] &&
    _macos_compat_paths+=("$_macos_compat_prefix/bin")
  [[ -d "$_macos_compat_prefix/sbin" ]] &&
    _macos_compat_paths+=("$_macos_compat_prefix/sbin")
done

path=(
  "$MACOS_ZSH_COMPAT_ROOT/bin"
  "${_macos_compat_paths[@]}"
  "${path[@]}"
)
export PATH MACOS_ZSH_COMPAT_ROOT

(( ${+ZHM_CLIPBOARD_PIPE_CONTENT_TO} )) ||
  ZHM_CLIPBOARD_PIPE_CONTENT_TO=pbcopy
(( ${+ZHM_CLIPBOARD_READ_CONTENT_FROM} )) ||
  ZHM_CLIPBOARD_READ_CONTENT_FROM=pbpaste
export ZHM_CLIPBOARD_PIPE_CONTENT_TO ZHM_CLIPBOARD_READ_CONTENT_FROM

unset _macos_compat_prefix _macos_compat_prefixes _macos_compat_paths
