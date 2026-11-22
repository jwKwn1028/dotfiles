# --------------------------------------------------------
# Zk
# --------------------------------------------------------
# Previews use $_zsh_bat (from _lib.zsh); the old hardcoded `bat` broke
# on this machine, where the binary is batcat.
zn() {
    local preview='cat -- {}'
    [[ $_zsh_bat != cat ]] && preview="$_zsh_bat --color=always --style=header,grid --line-range :500 {}"
    local note
    note=$(zk list --format path --sort modified- --quiet | fzf \
        --prompt='Notes> ' \
        --preview "$preview" \
        --preview-window=right:50%:wrap \
        --height=80% \
        --layout=reverse \
        --header="Enter to Edit | Ctrl-C to Cancel"
    )

    if [ -n "$note" ]; then
        hx "$note"
    fi
}

zs() {
    local preview='cat -- {}'
    [[ $_zsh_bat != cat ]] && preview="$_zsh_bat --color=always --style=header,numbers --line-range :500 {}"
    local note
    note=$(zk grep "$1" --format path --quiet | fzf \
        --prompt='Search Content> ' \
        --preview "$preview" \
        --preview-window=right:50%:wrap \
        --header="Search: $1"
    )

    if [ -n "$note" ]; then
        hx "$note"
    fi
}
