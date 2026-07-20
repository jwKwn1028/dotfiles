# --------------------------------------------------------
# Aliases
# --------------------------------------------------------
alias twt='taskwarrior-tui'
alias v='vim .'
alias c='code .'
alias h='hx .'
alias z='zed .'
alias vi='vim'
alias mu='micro'
alias ls='eza --color=auto --icons --long --git --no-user --no-permissions'
(( $+commands[batcat] )) && alias bat='batcat'
alias hz='${EDITOR:-hx} ~/.zsh/rc.d'   # config now lives in modules (was ~/.zshrc)
alias sz='source ~/.zshrc && print "Zsh config reloaded."'
if command -v fdfind >/dev/null 2>&1; then
  alias fd='fdfind'
fi
alias scpo='print "shutting down..." && systemctl poweroff'
alias scrb='print "reboot ..." && systemctl reboot'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# --------------------------------------------------------
# Ripgrep (rg)
# --------------------------------------------------------
alias rg='rg --smart-case'
