#!/usr/bin/env bash
# Runs every test but the live Xephyr ones, continuing past failures; exits 1
# if any failed. Output with SKIP: or skipped=N counts as a skip.

set -uo pipefail
cd "$(dirname "$(readlink -f "$0")")" || exit 1
export PYTHONDONTWRITEBYTECODE=1

tests=(dot_config/i3/tests/executable_run-fast.sh
    dot_local/bin/tests/executable_test-* .githooks/tests/test-*)
out="$(mktemp)"
trap 'rm -f "$out"' EXIT
failed=0 skipped=0

for test in "${tests[@]}"; do
    case "$test" in
        *.py) command=(python3 "$test") ;;
        *.zsh) command=(zsh "$test") ;;
        *) command=(bash "$test") ;;
    esac
    printf '%-62s' "$test"
    start=$SECONDS
    if ! "${command[@]}" </dev/null >"$out" 2>&1; then
        status=FAIL; failed=$((failed + 1))
    elif grep -qE 'SKIP:|skipped=[1-9]' "$out"; then
        status=SKIP; skipped=$((skipped + 1))
    else
        status=PASS
    fi
    printf ' %s %4ds\n' "$status" $((SECONDS - start))
    if [ "$status" = FAIL ]; then tail -n 15 "$out" | sed 's/^/    | /'; fi
done

printf '\n%d tests: %d failed, %d skipped\n' "${#tests[@]}" "$failed" "$skipped"
[ "$failed" -eq 0 ]
