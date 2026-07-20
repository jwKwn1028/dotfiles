# ---------- hxp / wpdf: live editor + PDF preview ----------
# All function definitions live in ~/.zsh/hxp-main.zsh (which in turn
# sources ~/.zsh/hxp-lib.zsh). Tracked separately in the hxp dotfiles
# repo; this module only needs one line to wire it up.
[[ -r "$HOME/.zsh/hxp-main.zsh" ]] && source "$HOME/.zsh/hxp-main.zsh"

# --------------------------------------------------------
# Conda (lazy init; ~/.zshenv carries a minimal fallback for plain zsh -c)
# --------------------------------------------------------
[[ -r "$HOME/.zsh/conda-lazy.zsh" ]] && source "$HOME/.zsh/conda-lazy.zsh"
