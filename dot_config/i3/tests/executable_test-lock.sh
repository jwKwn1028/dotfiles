#!/usr/bin/env bash
# lock.sh styles i3lock-color and hands stock i3lock only the flags it accepts.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
export PATH="$TEST_TMP/bin:$PATH"
mkdir -p "$TEST_TMP/bin"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

LOCK="$ROOT/lock.sh"
[ -f "$LOCK" ] || LOCK="$ROOT/executable_lock.sh"

mock_i3lock() {
  cat >"$TEST_TMP/bin/i3lock" <<MOCK
#!/bin/sh
if [ "\$1" = --version ]; then
  echo 'i3lock: version $1 (2023-07-28) © 2010 Michael Stapelberg'
  exit 0
fi
printf '%s\n' "\$*" >"$TEST_TMP/args"
MOCK
  chmod +x "$TEST_TMP/bin/i3lock"
}

mock_i3lock 2.13.c.5
bash "$LOCK"
args=" $(cat "$TEST_TMP/args") "
case "$args" in " -n -c 292d3e "*) ;; *) fail "i3lock-color lost nofork or the background:$args" ;; esac
for flag in --radius=60 --verif-font=JuliaMono --wrong-font=JuliaMono; do
  case "$args" in *" $flag "*) ;; *) fail "i3lock-color call is missing $flag" ;; esac
done
case "$args" in *" --clock "*|*" --force-clock "*|*" -k "*) fail "i3lock-color call shows the clock" ;; esac

mock_i3lock 2.14.1
bash "$LOCK"
[ "$(cat "$TEST_TMP/args")" = "-n -c 292d3e" ] ||
  fail "stock i3lock got flags it rejects: $(cat "$TEST_TMP/args")"

printf 'PASS: lock.sh styles i3lock-color and falls back to stock i3lock\n'
