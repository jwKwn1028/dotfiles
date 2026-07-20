# --------------------------------------------------------
# Starship Prompt
# --------------------------------------------------------
# Fallback if starship is ever missing:
# PROMPT='%n %{%F{#86BE43}%}%~%{%f%} %# '
if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi
