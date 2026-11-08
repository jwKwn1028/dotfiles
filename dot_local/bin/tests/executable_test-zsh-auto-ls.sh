#!/usr/bin/env bash
# Tests the cd auto-list in dot_zsh/rc.d/35-navigation.zsh.

set -euo pipefail

ROOT="$(readlink -f "$(dirname "$(readlink -f "$0")")/../../..")"
NAV="$ROOT/dot_zsh/rc.d/35-navigation.zsh"
[ -r "$NAV" ] || NAV="$HOME/.zsh/rc.d/35-navigation.zsh"
if ! command -v eza >/dev/null || ! command -v script >/dev/null || ! command -v zsh >/dev/null; then
    echo "SKIP: eza, zsh, or script(1) is not installed"
    exit 0
fi

TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir "$TEST_TMP/dir"
touch "$TEST_TMP/dir/listed-file"
cat >"$TEST_TMP/driver.zsh" <<'ZSH'
_have() { [[ $1 == eza ]] && whence -p eza >/dev/null; }
source "$1"
dir=$2 n=0
printf 'a\nb\nc\n' | while read -r line; do cd "$dir"; (( n++ )); done
print -r -- "loop:$n"
x=$(cd "$dir" && pwd)
print -r -- "subst:${x//$'\n'/|}"
cd /
cd "$dir"
ZSH

# script(1) gives zsh a terminal, as at a prompt.
script -qec "zsh -f $(printf '%q %q %q' "$TEST_TMP/driver.zsh" "$NAV" "$TEST_TMP/dir")" /dev/null \
    </dev/null 2>&1 | tr -d '\r' | sed 's/\x1b\[[0-9;]*m//g' >"$TEST_TMP/out"

fail() {
    echo "FAIL: $1" >&2
    sed 's/^/  | /' "$TEST_TMP/out" >&2
    exit 1
}
grep -qx 'loop:3' "$TEST_TMP/out" || fail 'the auto-list swallowed piped loop input'
grep -qxF "subst:$TEST_TMP/dir" "$TEST_TMP/out" || fail 'the auto-list leaked into a command substitution'
grep -q 'listed-file' "$TEST_TMP/out" || fail 'cd at a terminal no longer lists the directory'

echo 'PASS: zsh auto-list keeps piped input and command substitutions clean'
