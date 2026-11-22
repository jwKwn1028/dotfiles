#!/usr/bin/env bash
# Tests dot_var/app/org.onlyoffice.desktopeditors/config/onlyoffice/modify_DesktopEditors.conf.

set -euo pipefail

SOURCE_ROOT="$(readlink -f "$(dirname "$(readlink -f "$0")")/../../..")"
SCRIPT="dot_var/app/org.onlyoffice.desktopeditors/config/onlyoffice/modify_DesktopEditors.conf"
[ -r "$SOURCE_ROOT/$SCRIPT" ] || SOURCE_ROOT="$(chezmoi source-path 2>/dev/null || true)"
if [ ! -r "$SOURCE_ROOT/$SCRIPT" ]; then
    echo "SKIP: the chezmoi source directory is unavailable from the applied tree"
    exit 0
fi

TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT
OUT="$TEST_TMP/out"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

# check NAME INPUT EXPECTED (printf formats)
check() {
    # shellcheck disable=SC2059
    printf "$2" | python3 "$SOURCE_ROOT/$SCRIPT" >"$OUT" || fail "$1: exited $?"
    # shellcheck disable=SC2059
    cmp -s "$OUT" <(printf "$3") || {
        echo "--- got:" >&2; cat -A "$OUT" >&2
        fail "$1"
    }
}

check 'empty file gets the key' \
    '' \
    '[General]\ntitlebar=system\n'
check 'custom frame is replaced in place' \
    '[General]\nopenPath=/data/docs\ntitlebar=custom\nposition=@Rect(0 0 1920 1080)\n' \
    '[General]\nopenPath=/data/docs\ntitlebar=system\nposition=@Rect(0 0 1920 1080)\n'
check 'already system is left alone' \
    '[General]\ntitlebar=system\n\n[EditorsGeometry]\n0\\maximized=true\n' \
    '[General]\ntitlebar=system\n\n[EditorsGeometry]\n0\\maximized=true\n'
check 'missing key is added to [General]' \
    '[General]\nsavePath=/data\n\n[Other]\ntitlebar=custom\n' \
    '[General]\ntitlebar=system\nsavePath=/data\n\n[Other]\ntitlebar=custom\n'
check 'missing [General] is prepended' \
    '[EditorsGeometry]\n0\\maximized=true' \
    '[General]\ntitlebar=system\n\n[EditorsGeometry]\n0\\maximized=true\n'
check 'CRLF line endings are kept' \
    '[General]\r\ntitlebar=custom\r\n' \
    '[General]\r\ntitlebar=system\r\n'
check 'non-UTF-8 bytes pass through' \
    '[General]\nopenPath=/data/\xff\xfe\ntitlebar=custom\n' \
    '[General]\nopenPath=/data/\xff\xfe\ntitlebar=system\n'

echo 'PASS: ONLYOFFICE titlebar set to system, rest kept'
