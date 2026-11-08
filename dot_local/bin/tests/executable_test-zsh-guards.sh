#!/usr/bin/env bash
# Tests Zsh's tool guards: the editor choice in dot_zshenv and the aliases in
# dot_zsh/rc.d/30-aliases.zsh.

set -euo pipefail

ROOT="$(readlink -f "$(dirname "$(readlink -f "$0")")/../../..")"
ZSHENV="$ROOT/dot_zshenv"
RC="$ROOT/dot_zsh/rc.d"
[ -r "$ZSHENV" ] || { ZSHENV="$HOME/.zshenv"; RC="$HOME/.zsh/rc.d"; }
ZSH="$(command -v zsh)" || { echo "SKIP: zsh is not installed"; exit 0; }

TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT
BIN="$TEST_TMP/bin"
mkdir -p "$BIN" "$TEST_TMP/home"
ln -s "$(command -v ls)" "$BIN/ls"
cp -- "$ZSHENV" "$TEST_TMP/home/.zshenv"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}
stub() {
    printf '#!/bin/sh\n' >"$BIN/$1"
    chmod +x "$BIN/$1"
}
# PATH holds only $BIN, so a tool exists only if it is stubbed there.
editor() {
    env -i HOME="$TEST_TMP/home" PATH="$BIN" "$ZSH" -c 'print -r -- "$EDITOR $VISUAL $ZK_EDITOR"'
}
aliases() {
    env -i HOME="$TEST_TMP/home" PATH="$BIN" "$ZSH" -f -c '
        source "$1/_lib.zsh"; source "$1/30-aliases.zsh"
        eval "ls -d /" >/dev/null && print ls-ok
        print -r -- ${(j: :)${(k)aliases[(I)(ls|vi|v|h|mo|twt)]}}' zsh "$RC" 2>&1
}

[ "$(aliases)" = 'ls-ok' ] || fail "missing tools still got aliases: $(aliases | tr '\n' ' ')"
stub vim
[ "$(editor)" = 'vim vim vim' ] || fail "editor without Helix: $(editor)"
stub hx
[ "$(editor)" = 'hx hx hx' ] || fail "editor with Helix: $(editor)"
for tool in eza micro taskwarrior-tui; do stub "$tool"; done
[ "$(aliases | tr ' ' '\n' | sort | tr '\n' ' ')" = 'h ls ls-ok mo twt v vi ' ] ||
    fail "installed tools lost aliases: $(aliases | tr '\n' ' ')"

echo 'PASS: Zsh aliases and EDITOR follow the tools that are installed'
