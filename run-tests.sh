#!/usr/bin/env bash
# Run all non-Xephyr tests in parallel (--serial: one at a time); exit 1 on any failure.

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1
export PYTHONDONTWRITEBYTECODE=1

jobs=$(nproc 2> /dev/null || echo 4)
if [ "${1:-}" = --serial ]; then jobs=1; fi
export TEST_JOBS=$jobs # The i3 suite runs its sections with the same limit.

# Timing-sensitive tests run alone, after the others.
alone=(dot_local/bin/tests/executable_test-cpu-load.sh dot_local/bin/tests/executable_test-session-save.sh)
tests=()
for test in dot_config/i3/tests/executable_run-fast.sh dot_local/bin/tests/executable_test-* .githooks/tests/test-*; do
  case " ${alone[*]} " in *" $test "*) ;; *) tests+=("$test") ;; esac
done
tests+=("${alone[@]}")
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0 skipped=0 next=0

run_one() {
  local index=$1 test=$2 start=$SECONDS status
  local -a command
  case "$test" in
    *.py) command=(python3 "$test") ;;
    *.zsh) command=(zsh "$test") ;;
    *) command=(bash "$test") ;;
  esac
  mkdir -m 700 "$work/runtime-$index" # Own runtime dir: no shared locks, none of the live session's.
  if ! XDG_RUNTIME_DIR="$work/runtime-$index" "${command[@]}" < /dev/null > "$work/$index.out" 2>&1; then
    status=FAIL
  elif grep -qE 'SKIP:|skipped=[1-9]' "$work/$index.out"; then
    status=SKIP
  else
    status=PASS
  fi
  printf '%s %d\n' "$status" $((SECONDS - start)) > "$work/$index.result.tmp" \
    && mv -- "$work/$index.result.tmp" "$work/$index.result"
}

# Print finished results in list order.
report() {
  local status seconds extra
  while [ "$next" -lt "${#tests[@]}" ] && [ -e "$work/$next.result" ]; do
    if ! read -r status seconds extra < "$work/$next.result" \
      || [[ ! $status =~ ^(PASS|FAIL|SKIP)$ || ! $seconds =~ ^[0-9]+$ || -n $extra ]]; then
      printf 'FAIL: invalid result for %s\n' "${tests[next]}" >&2
      status=FAIL seconds=0
    fi
    printf '%-62s %s %4ds\n' "${tests[next]}" "$status" "$seconds"
    case $status in
      FAIL)
        failed=$((failed + 1))
        tail -n 15 "$work/$next.out" | sed 's/^/    | /'
        ;;
      SKIP) skipped=$((skipped + 1)) ;;
    esac
    next=$((next + 1))
  done
}

start=$SECONDS
for index in "${!tests[@]}"; do
  if [ "$index" -ge $((${#tests[@]} - ${#alone[@]})) ]; then
    wait
    report # The alone tests start once everything else has finished.
    run_one "$index" "${tests[index]}"
  else
    while [ "$(jobs -rp | wc -l)" -ge "$jobs" ]; do
      wait -n
      report
    done
    run_one "$index" "${tests[index]}" &
  fi
  report
done
wait
report
[ "$next" -eq "${#tests[@]}" ] || {
  printf 'FAIL: missing result for %s\n' "${tests[next]}" >&2
  exit 1
}

printf '\n%d tests: %d failed, %d skipped (%ds)\n' "${#tests[@]}" "$failed" "$skipped" $((SECONDS - start))
[ "$failed" -eq 0 ]
