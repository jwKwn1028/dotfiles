# --------------------------------------------------------
# Starship Prompt
# --------------------------------------------------------
# Fallback if starship is ever missing:
# PROMPT='%n %{%F{#86BE43}%}%~%{%f%} %# '
if _have starship; then
  eval "$(starship init zsh)"
fi
