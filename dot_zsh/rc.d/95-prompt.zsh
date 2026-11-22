# Starship prompt.
#
# Fallback if starship is ever missing:
#   PROMPT='%n %{%F{#86BE43}%}%~%{%f%} %# '
#
# The banner goes in after Starship, so it prefixes the final PROMPT instead of
# being overwritten by prompt initialization.

if _have starship; then
  eval "$(starship init zsh)"
fi

if (( $+functions[_zsh_banner_install] )); then
  setopt promptsubst
  _zsh_banner_install
fi
