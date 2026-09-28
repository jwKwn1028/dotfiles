# --------------------------------------------------------
# zsh-helix-mode
# --------------------------------------------------------
# Loads before 25-completion (same order as the old monolithic .zshrc)
# and before 40-fzf / 90-plugins, which guard on the zhm_* functions.
ZHM_CURSOR_NORMAL=$'\e[2 q\e]12;#86be43\a'
ZHM_CURSOR_SELECT=$'\e[4 q\e]12;#86be43\a'
ZHM_CURSOR_INSERT=$'\e[6 q\e]12;#86be43\a'

if [[ -f "$HOME/.zsh/plugins/zsh-helix-mode/zsh-helix-mode.plugin.zsh" ]]; then
  source "$HOME/.zsh/plugins/zsh-helix-mode/zsh-helix-mode.plugin.zsh"
fi

if (( $+functions[zhm_select] )); then
  # Widgets such as fzf or edit-command-line can change the terminal cursor
  # without changing Helix mode. Reapply it when ZLE starts or redraws, even
  # if the mode has not changed. KEYMAP is usually the "main" alias in all
  # Helix modes, so use the plugin's state instead.
  _zhm_sync_cursor() {
    emulate -L zsh
    local cursor
    if (( ZHM_IN_PROMPT )); then
      # Recursive regex/pipe prompts accept text in normal and select mode.
      cursor=$ZHM_CURSOR_INSERT
    else
      case $ZHM_MODE in
        normal) cursor=$ZHM_CURSOR_NORMAL ;;
        select) cursor=$ZHM_CURSOR_SELECT ;;
        insert) cursor=$ZHM_CURSOR_INSERT ;;
        *) return 0 ;;
      esac
    fi
    printf '%b' "$cursor"
  }
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget line-init _zhm_sync_cursor
  add-zle-hook-widget line-pre-redraw _zhm_sync_cursor

  zhm_user_clipboard_v() {
    if [[ $ZHM_MODE == select ]]; then
      zhm_replace_selections_with_clipboard
    else
      zhm_clipboard_paste_after
    fi
  }
  zle -N zhm_user_clipboard_v

  bindkey -M hxnor 'V' zhm_user_clipboard_v
  bindkey -M hxnor 'v' zhm_select
  bindkey -M hxins '^[' zhm_normal
  bindkey -M hxins 'jk' zhm_normal
  bindkey -M hxins '^[h' zhm_clear_selection_move_left
  bindkey -M hxins '^[j' zhm_move_down_or_history_next
  bindkey -M hxins '^[k' zhm_move_up_or_history_prev
  bindkey -M hxins '^[l' zhm_clear_selection_move_right
  bindkey -M hxins '^[q' zhm_goto_line_start
  bindkey -M hxins '^[e' zhm_goto_line_end
  bindkey -M hxins '^X^E' edit-command-line
  bindkey -M hxnor '^X^E' edit-command-line
else
  bindkey '^X^E' edit-command-line
fi
