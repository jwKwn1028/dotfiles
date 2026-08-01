#!/usr/bin/env bash
# Two polybar bars (one per monitor) share the "polybar" instance key. They must
# not consume each other's snapshot: that measured a few milliseconds instead of
# the interval and made a calm machine read 50%.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
CPU_LOAD="$ROOT/cpu-load"
[ -x "$CPU_LOAD" ] || CPU_LOAD="$ROOT/executable_cpu-load"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT
export XDG_RUNTIME_DIR="$TEST_TMP"

run() { bash "$CPU_LOAD" "$@"; }

# Prime the state, then poll as two bars offset by ~0.2s inside one 2s cycle.
run polybar 2 >/dev/null
sleep 1
bar_a=$(run polybar 2)
sleep 0.2
bar_b=$(run polybar 2)

[ "$bar_a" = "$bar_b" ] ||
    { printf 'FAIL: bars disagree within one cycle (%s vs %s)\n' "$bar_a" "$bar_b" >&2; exit 1; }

# The second bar must not have advanced the window either -- if it had, the next
# real cycle would measure from 0.2s ago instead of from a full interval.
read -r _ _ stamp_b _ <"$XDG_RUNTIME_DIR/cpu-load.polybar.state"
sleep 0.2
run polybar 2 >/dev/null
read -r _ _ stamp_c _ <"$XDG_RUNTIME_DIR/cpu-load.polybar.state"
[ "$stamp_b" = "$stamp_c" ] ||
    { printf 'FAIL: a too-fresh snapshot was replaced\n' >&2; exit 1; }

# Past 75% of the interval, the next caller does advance it.
sleep 1.5
run polybar 2 >/dev/null
read -r _ _ stamp_d _ <"$XDG_RUNTIME_DIR/cpu-load.polybar.state"
[ "$stamp_d" != "$stamp_c" ] ||
    { printf 'FAIL: the window never advanced\n' >&2; exit 1; }

# Separate instance keys stay independent, and output is a sane percentage.
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
