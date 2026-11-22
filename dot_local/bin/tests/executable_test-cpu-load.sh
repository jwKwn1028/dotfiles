#!/usr/bin/env bash
# Concurrent bars must reuse one sample per interval, without shortening it.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
CPU_LOAD="$ROOT/cpu-load"
[ -x "$CPU_LOAD" ] || CPU_LOAD="$ROOT/executable_cpu-load"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
export XDG_RUNTIME_DIR="$TEST_TMP"

run() { bash "$CPU_LOAD" "$@"; }

run polybar 2 >/dev/null
sleep 1
bar_a=$(run polybar 2)
sleep 0.2
bar_b=$(run polybar 2)

[ "$bar_a" = "$bar_b" ] ||
    { printf 'FAIL: bars disagree within one cycle (%s vs %s)\n' "$bar_a" "$bar_b" >&2; exit 1; }

read -r _ _ stamp_b _ <"$XDG_RUNTIME_DIR/cpu-load.polybar.state"
sleep 0.2
run polybar 2 >/dev/null
read -r _ _ stamp_c _ <"$XDG_RUNTIME_DIR/cpu-load.polybar.state"
[ "$stamp_b" = "$stamp_c" ] ||
    { printf 'FAIL: a too-fresh snapshot was replaced\n' >&2; exit 1; }

sleep 1.5
run polybar 2 >/dev/null
read -r _ _ stamp_d _ <"$XDG_RUNTIME_DIR/cpu-load.polybar.state"
[ "$stamp_d" != "$stamp_c" ] ||
    { printf 'FAIL: the window never advanced\n' >&2; exit 1; }

load=$(run sysmon 2)
[ -f "$XDG_RUNTIME_DIR/cpu-load.sysmon.state" ] ||
    { printf 'FAIL: instance key did not get its own state\n' >&2; exit 1; }
case "$load" in
    ''|*[!0-9]*) printf 'FAIL: non-numeric load %s\n' "$load" >&2; exit 1 ;;
esac
if [ "$load" -lt 0 ] || [ "$load" -gt 100 ]; then
    printf 'FAIL: load %s out of range\n' "$load" >&2
    exit 1
fi

printf 'PASS: cpu-load shares one window across concurrent callers\n'

# --follow prints a first value promptly, then one on each whole interval.
start=${EPOCHREALTIME//[!0-9]/}
{ timeout 3.4 bash "$CPU_LOAD" probe 1 --follow || true; } |
    while IFS= read -r line; do
        printf '%s %s\n' "${EPOCHREALTIME//[!0-9]/}" "$line"
    done >"$TEST_TMP/follow"
mapfile -t follow <"$TEST_TMP/follow"
[ "${#follow[@]}" -ge 3 ] ||
    { printf 'FAIL: --follow printed %s lines in 3.4s\n' "${#follow[@]}" >&2; exit 1; }
for i in "${!follow[@]}"; do
    read -r stamp load <<<"${follow[i]}"
    case "$load" in
        ''|*[!0-9]*) printf 'FAIL: --follow printed non-numeric %s\n' "$load" >&2; exit 1 ;;
    esac
    [ "$load" -le 100 ] || { printf 'FAIL: --follow load %s out of range\n' "$load" >&2; exit 1; }
    if [ "$i" = 0 ]; then
        [ $((stamp - start)) -lt 1000000 ] ||
            { printf 'FAIL: --follow took %s us to print\n' $((stamp - start)) >&2; exit 1; }
    elif [ $((stamp % 1000000)) -ge 200000 ]; then
        printf 'FAIL: --follow line %s not on a second boundary (%s)\n' "$i" "$stamp" >&2
        exit 1
    fi
done
printf 'PASS: cpu-load --follow prints on interval boundaries\n'
