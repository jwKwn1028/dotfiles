# --------------------------------------------------------
# Plugins: autosuggestions + syntax highlighting
# --------------------------------------------------------
# Order matters: autosuggestions first, syntax highlighting last among
# plugins; 95-prompt (starship) comes after. The zhm_* integration arrays
# rely on 20-helix-mode having loaded first.
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'

if (( $+functions[zhm_prompt_accept] )); then
  ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(
    zhm_history_prev
    zhm_history_next
    zhm_prompt_accept
    zhm_accept
    zhm_accept_or_insert_newline
  )
  ZSH_AUTOSUGGEST_ACCEPT_WIDGETS+=(
    zhm_move_right
    zhm_clear_selection_move_right
  )
  ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS+=(
    zhm_move_next_word_start
    zhm_move_next_word_end
  )
fi

if [[ -f "$HOME/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$HOME/.zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if [[ -f "$HOME/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$HOME/.zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

if [[ -f "$HOME/.config/zsh/themes/tokyonight_storm-zsh-syntax-highlighting.zsh" ]]; then
  source "$HOME/.config/zsh/themes/tokyonight_storm-zsh-syntax-highlighting.zsh"
fi

if (( $+functions[zhm-add-update-region-highlight-hook] )); then
  zhm-add-update-region-highlight-hook
fi

# --------------------------------------------------------
# Autosuggestion Keybindings
# --------------------------------------------------------
bindkey '^f' autosuggest-accept
bindkey '^[f' forward-word

# --------------------------------------------------------
# Plugin updater
# --------------------------------------------------------
# The plugins under ~/.zsh/plugins are plain upstream git clones (not
# submodules, since ~/.zsh itself is not a repo yet). `zpup` fast-forwards
# each clone to its upstream; reload with `sz` afterwards.
zpup() {
  emulate -L zsh
  local d
  for d in "$HOME/.zsh/plugins"/*(N/); do
    [[ -d "$d/.git" ]] || { print -u2 "zpup: skip ${d:t} (not a git clone)"; continue; }
    print -P "%F{cyan}==>%f ${d:t}"
    git -C "$d" pull --ff-only || print -u2 "zpup: ${d:t} update failed"
  done
  print -P "%F{green}Done.%f Reload with 'sz' to pick up updates."
}
