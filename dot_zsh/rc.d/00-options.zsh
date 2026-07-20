# --------------------------------------------------------
# Shell options, history, base ZLE widgets
# --------------------------------------------------------
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt EXTENDED_GLOB   # 25-completion's zcompdump age check relies on this

# History
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d "${HISTFILE:h}" ]] || mkdir -p -- "${HISTFILE:h}"
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_SAVE_NO_DUPS
setopt HIST_FCNTL_LOCK
setopt HIST_VERIFY
setopt AUTO_PUSHD
setopt HIST_FIND_NO_DUPS
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt NO_CLOBBER
unsetopt CORRECT

autoload -Uz edit-command-line zmv
zle -N edit-command-line
