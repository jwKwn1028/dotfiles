# hxp owns its functions and resume hook; provisioning clones it.
[[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"

# --------------------------------------------------------
# Conda (lazy init; ~/.zshenv carries a minimal fallback for plain zsh -c)
# --------------------------------------------------------
[[ -r "$HOME/.zsh/conda-lazy.zsh" ]] && source "$HOME/.zsh/conda-lazy.zsh"
