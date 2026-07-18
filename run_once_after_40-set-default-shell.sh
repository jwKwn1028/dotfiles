#!/usr/bin/env bash
# Makes zsh the login shell (the whole dotfile set targets zsh).
set -euo pipefail

zsh_path="$(command -v zsh || true)"
if [ -z "$zsh_path" ]; then
    echo "zsh not installed yet; skipping default-shell change."
    exit 0
fi

# Ensure zsh is a valid login shell.
if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
    echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
fi

current_shell="$(getent passwd "$USER" | cut -d: -f7)"
if [ "$current_shell" != "$zsh_path" ]; then
    echo "==> Setting default shell to $zsh_path (may prompt for your password)"
    chsh -s "$zsh_path" || echo "chsh failed; run manually: chsh -s $zsh_path"
else
    echo "Default shell is already $zsh_path."
fi
