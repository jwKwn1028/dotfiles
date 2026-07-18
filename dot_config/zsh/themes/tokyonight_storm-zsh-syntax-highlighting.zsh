# TokyoNight Storm token colors for zsh-syntax-highlighting
# Works best when your terminal palette is set to TokyoNight Storm.

typeset -gA ZSH_HIGHLIGHT_STYLES

# Errors / unknown
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=#f7768e,bold'

# Shell language
ZSH_HIGHLIGHT_STYLES[reserved-word]='fg=#bb9af7,bold'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=#bb9af7'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=#bb9af7'

# Commands
ZSH_HIGHLIGHT_STYLES[command]='fg=#7aa2f7'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=#bb9af7,bold'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=#7aa2f7'

# Builtins / aliases / functions
ZSH_HIGHLIGHT_STYLES[alias]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[suffix-alias]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[function]='fg=#7dcfff'

# Args / strings / paths
ZSH_HIGHLIGHT_STYLES[path]='fg=#a9b1d6'
ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=#a9b1d6'
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=#9ece6a'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=#9ece6a'
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]='fg=#9ece6a'
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]='fg=#9ece6a'
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=#9ece6a'

# Options / globs
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=#e0af68'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=#e0af68'
ZSH_HIGHLIGHT_STYLES[globbing]='fg=#e0af68'

# Expansions
ZSH_HIGHLIGHT_STYLES[assign]='fg=#7dcfff'
ZSH_HIGHLIGHT_STYLES[arithmetic-expansion]='fg=#ff9e64'
ZSH_HIGHLIGHT_STYLES[command-substitution]='fg=#ff9e64'
ZSH_HIGHLIGHT_STYLES[process-substitution]='fg=#ff9e64'

# Comments
ZSH_HIGHLIGHT_STYLES[comment]='fg=#414868,italic'
