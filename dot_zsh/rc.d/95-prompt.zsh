# --------------------------------------------------------
# Starship Prompt
# --------------------------------------------------------
# Fallback if starship is ever missing:
# PROMPT='%n %{%F{#86BE43}%}%~%{%f%} %# '
if _have starship; then
  eval "$(starship init zsh)"
fi

# Install after Starship so the resize-aware startup banner prefixes the final
# prompt definition instead of being overwritten by prompt initialization.
if (( $+functions[_zsh_banner_install] )); then
  setopt promptsubst
  _zsh_banner_install
fi
