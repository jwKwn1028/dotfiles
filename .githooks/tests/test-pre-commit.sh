#!/usr/bin/env bash
# Runs .githooks/pre-commit against throwaway repos. A stub chezmoi serves
# fixture values, so no real value is read, and every block is also checked
# for leaking a fixture value into the hook's output.

set -euo pipefail

HOOK="$(dirname "$(dirname "$(readlink -f "$0")")")/pre-commit"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    echo "FAIL: $1" >&2
    [ -r "$TEST_TMP/out" ] && sed 's/^/  | /' "$TEST_TMP/out" >&2
    exit 1
}

unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE PRIVACY_GUARD_DENYLIST
# HOME names the fixture user, so printing a home path counts as a leak.
export HOME="$TEST_TMP/jdoe42" XDG_CONFIG_HOME="$TEST_TMP/jdoe42/.config"
export GIT_CONFIG_NOSYSTEM=1 PATH="$TEST_TMP/bin:$PATH"
mkdir -p "$TEST_TMP/bin" "$XDG_CONFIG_HOME/chezmoi"

cat >"$TEST_TMP/bin/chezmoi" <<'STUB'
#!/bin/sh
if [ -n "${STUB_FAIL:-}" ]; then echo "stub: $HOME/.config/chezmoi/chezmoi.toml not found" >&2; exit 1; fi
printf '%s\t%s\n' \
    class desktop \
    desktopProfile linuxmint-i3-x11 \
    birthdayMonthDay 09-15 \
    email jane.doe@example.org \
    name 'Jane Placeholder' \
    sshRemoteUser rdoe77 \
    sshGpuHost gpu \
    sshHpcHostName hpc.fixture.example \
    tailscaleExitNode exit-fixture-node \
    username jdoe42 \
    hostname fixture-laptop \
    fqdnHostname fixture-laptop
STUB
chmod +x "$TEST_TMP/bin/chezmoi"
printf '%s\n' '# lab and institution names' '  Fixture Lab of Things  ' '' >"$XDG_CONFIG_HOME/chezmoi/denylist"

LEAKS=(jane.doe@example.org 'jane placeholder' rdoe77 hpc.fixture.example
    exit-fixture-node jdoe42 fixture-laptop 'fixture lab of things')

count=0
new_repo() {
    count=$((count + 1))
    REPO="$TEST_TMP/repo$count"
    git -c init.defaultBranch=main init -q "$REPO"
    git -C "$REPO" config user.name test
    git -C "$REPO" config user.email test@example.invalid
}
put() {
    mkdir -p "$(dirname "$REPO/$1")"
    printf '%s\n' "$2" >"$REPO/$1"
    git -C "$REPO" add -f -- "$1"
}
run_hook() {
    (cd "$REPO" && bash "$HOOK") >"$TEST_TMP/out" 2>&1
}
passes() {
    run_hook || fail "$1: expected the hook to pass"
}
no_leaks() {
    local value
    for value in "${LEAKS[@]}"; do
        if grep -qiF -- "$value" "$TEST_TMP/out"; then fail "$1: output leaks '$value'"; fi
    done
}
blocks() {
    local case_name="$1" want
    shift
    if run_hook; then fail "$case_name: expected the hook to block"; fi
    for want in "$@"; do
        grep -qF -- "$want" "$TEST_TMP/out" || fail "$case_name: output lacks '$want'"
    done
    no_leaks "$case_name"
}

new_repo
put README.md 'plain text'
passes "clean change on an unborn branch"

new_repo
put notes.txt $'one\ntwo\nssh rdoe77@login'
blocks "chezmoi value in content" "notes.txt:3: private value <sshRemoteUser>"

new_repo
put conf 'host = FIXTURE-LAPTOP'
blocks "case-insensitive, deduplicated value" "conf:1: private value <hostname/fqdnHostname>"

new_repo
put conf $'profile = linuxmint-i3-x11 desktop\nborn 09-15\nsubmit to the gpu queue'
passes "generic keys and short values are not matched"

new_repo
put LICENSE 'Copyright (c) 2026 Jane Placeholder'
passes "name is allowed in LICENSE"
put README.md 'by Jane Placeholder'
blocks "name outside LICENSE" "README.md:1: private value <name>"

new_repo
put notes.txt 'we are the fixture lab of things'
blocks "denylist entry" "notes.txt:1: private value <denylist:2>"

new_repo
put jdoe42-notes/todo.txt 'hi'
blocks "value in a file name is redacted" "<username>-notes/todo.txt: file name has private value <username>"

new_repo
: >"$REPO/exit-fixture-node.conf"
git -C "$REPO" add -- exit-fixture-node.conf
blocks "empty file named after a value" "<tailscaleExitNode>.conf: file name has private value"

new_repo
put notes.txt $'keep\nrdoe77'
git -C "$REPO" commit -q --no-verify -m base
put notes.txt 'keep'
passes "removing a value is allowed"

new_repo
put old.txt 'see /home/alice/bin'
git -C "$REPO" commit -q --no-verify -m base
git -C "$REPO" mv old.txt new.txt
passes "a pure rename does not rescan committed lines"

new_repo
put paths.txt $'run /home/alice/bin/x\nopen /Users/alice/Desktop'
blocks "literal home paths" "paths.txt:1: literal home" "paths.txt:2: literal home"

new_repo
put paths.txt $'/home/user/x\n/Users/Shared/x\n"$TEST_TMP/home/.local/bin"\n/home/linuxbrew/.linuxbrew/bin\n~/bin and $HOME/bin\n/home/alice/x  # privacy:allow'
put dot_themes/a.svg 'inkscape:export-filename="/home/sam/src.png"'
passes "placeholders, variables, third-party themes, and the allow marker"

new_repo
put ips.txt $'192.168.1.20\nping 10.0.0.7.\nexit via 100.100.100.100\n172.16.5.4:22'
blocks "private and Tailscale IPv4" "ips.txt:1: private" "ips.txt:2: private" "ips.txt:3: private" "ips.txt:4: private"

new_repo
put ips.txt $'helium-0.15.3.1\n100.200.1.1\n8.8.8.8 127.0.0.1\n172.32.0.1\nv1.10.0.0.1\n192.168.1.1  # privacy:allow'
passes "public, loopback, and version-like numbers"

new_repo
put net.txt $'ssh box.tail1234.ts.net\nfd7a:115c:a1e0::53'
blocks "tailnet names and addresses" "net.txt:1: Tailscale" "net.txt:2: Tailscale"

new_repo
put net.txt $'MagicDNS names end in *.ts.net\nts.network is unrelated'
passes "generic tailnet mentions"

new_repo
put private_dot_ssh/private_config.tmpl 'Host *'
passes "the SSH config template is allowed"
put private_dot_ssh/private_known_hosts 'x'
put keys/id_ed25519.pub 'ssh-ed25519 AAAA'
blocks "other SSH files" "private_dot_ssh/private_known_hosts: SSH file" "keys/id_ed25519.pub: SSH file"

new_repo
printf 'head\0 rdoe77 \0tail\n' >"$REPO/blob.bin"
printf '\0 192.168.1.20 \0\n' >"$REPO/ip.bin"
git -C "$REPO" add -- blob.bin ip.bin
blocks "values inside binaries" "blob.bin:1: private value <sshRemoteUser>"
if grep -qF "ip.bin" "$TEST_TMP/out"; then fail "pattern rules must skip binaries"; fi

new_repo
git -C "$REPO" config diff.noprefix true
git -C "$REPO" config diff.mnemonicPrefix true
put 'sub dir/file name.txt' 'rdoe77'
blocks "user diff config and spaces in paths" "sub dir/file name.txt:1: private value"

new_repo
put README.md 'plain text'
export PRIVACY_GUARD_DENYLIST="$TEST_TMP/missing"
passes "a missing denylist is fine"

export STUB_FAIL=1
if run_hook; then fail "a chezmoi failure must block"; fi
grep -qF "cannot read private values" "$TEST_TMP/out" || fail "chezmoi failure: message missing"
no_leaks "chezmoi failure"
unset STUB_FAIL

echo "PASS: pre-commit privacy guard"
