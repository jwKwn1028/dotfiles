#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
START="$ROOT/xfsettingsd-start.sh"
[ -r "$START" ] || START="$ROOT/executable_xfsettingsd-start.sh"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir "$TEST_TMP/bin"
export XFSETTINGSD_TEST_LOG="$TEST_TMP/calls" XFSETTINGSD_TEST_RUNNING="$TEST_TMP/running"

for tool in xfconf-query xfsettingsd; do
    printf '#!/bin/sh\necho "%s $*" >>"$XFSETTINGSD_TEST_LOG"\n' "$tool" >"$TEST_TMP/bin/$tool"
done
printf '#!/bin/sh\n[ -e "$XFSETTINGSD_TEST_RUNNING" ]\n' >"$TEST_TMP/bin/pgrep"
chmod +x "$TEST_TMP/bin/"*

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    sed 's/^/  /' "$XFSETTINGSD_TEST_LOG" >&2
    exit 1
}

settings='xfconf-query -c keyboards -p /Default/RestoreNumlock --create --type bool --set true
xfconf-query -c displays -p /AutoEnableProfiles --create --type bool --set false
xfconf-query -c displays -p /Notify --create --type int --set 0
xfconf-query -c displays -p /Default --reset --recursive'

PATH="$TEST_TMP/bin:$PATH" sh "$START"
[ "$(cat "$XFSETTINGSD_TEST_LOG")" = "$settings
xfsettingsd " ] || fail 'xfsettingsd did not start after its layout settings were cleared'

: >"$XFSETTINGSD_TEST_LOG"
touch "$XFSETTINGSD_TEST_RUNNING"
PATH="$TEST_TMP/bin:$PATH" sh "$START"
[ "$(cat "$XFSETTINGSD_TEST_LOG")" = "$settings" ] || fail 'a running xfsettingsd was started again'

printf 'PASS: xfsettingsd starts without applying its own screen layout\n'
