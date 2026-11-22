#!/bin/zsh
# Install the macOS prelude hook and the packages the rc.d modules need there.
#
# Three packages only, covering the real macOS/GNU incompatibilities. Everything
# else rc.d references is an optional user-facing tool, left to the user.

emulate -L zsh
setopt errexit nounset pipefail

if [[ $OSTYPE != darwin* ]]; then
  print -u2 -- 'macos/install.zsh must be run on macOS.'
  exit 2
fi

typeset root="${${(%):-%N}:A:h}"
typeset hook='[[ -r "$HOME/.zsh/macos/compat.zsh" ]] && source "$HOME/.zsh/macos/compat.zsh"'

if ! (( $+commands[brew] )); then
  print -u2 -- 'Homebrew is required. Install it first, then rerun this script.'
  exit 1
fi

brew install coreutils rsync fzf

if [[ ! -e "$HOME/.zshenv" ]]; then
  print -r -- "$hook" > "$HOME/.zshenv"
elif ! command grep -Fq 'macos/compat.zsh' "$HOME/.zshenv"; then
  print -r -- '' '# macOS compatibility for unchanged ~/.zsh/rc.d modules' \
    "$hook" >> "$HOME/.zshenv"
fi

if [[ ! -e "$HOME/.fzf.zsh" && ! -L "$HOME/.fzf.zsh" ]]; then
  command ln -s .zsh/macos/fzf.zsh "$HOME/.fzf.zsh"
fi

source "$root/compat.zsh"
exec "$root/doctor.zsh"
