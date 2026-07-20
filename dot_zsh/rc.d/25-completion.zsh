# --------------------------------------------------------
# Completion
# --------------------------------------------------------
# Note: the (#q...) glob below needs EXTENDED_GLOB (set in 00-options).
autoload -Uz compinit

_compdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p -- "${_compdump%/*}" 2>/dev/null

if [[ -n $_compdump(#qN.mh+24) ]]; then
  compinit -d "$_compdump"
else
  compinit -C -d "$_compdump"
fi
unset _compdump

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
if [[ -n "${LS_COLORS:-}" ]]; then
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
fi
