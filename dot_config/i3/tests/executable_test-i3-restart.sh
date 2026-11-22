#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
RESTART="$ROOT/i3-restart.sh"
[ -r "$RESTART" ] || RESTART="$ROOT/executable_i3-restart.sh"
CONFIG="$ROOT/config"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
LOG="$TEST_TMP/calls"
ERR="$TEST_TMP/stderr"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$MOCK_BIN"

cat >"$MOCK_BIN/i3" <<'EOF'
#!/usr/bin/env bash
printf 'i3:%s\n' "$*" >>"$I3_RESTART_TEST_LOG"
if [ "$I3_RESTART_TEST_CHECK_FAILURE" = 1 ]; then
    printf 'mock config parse error\n' >&2
    exit 1
fi
EOF

cat >"$MOCK_BIN/i3-msg" <<'EOF'
#!/usr/bin/env bash
printf 'i3-msg:%s\n' "$*" >>"$I3_RESTART_TEST_LOG"
if [ "$I3_RESTART_TEST_MESSAGE_FAILURE" = 1 ]; then
    printf 'mock IPC error\n' >&2
    exit 1
fi
EOF

cat >"$MOCK_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'notify:%s\n' "$*" >>"$I3_RESTART_TEST_LOG"
EOF
chmod +x "$MOCK_BIN/i3" "$MOCK_BIN/i3-msg" "$MOCK_BIN/notify-send"

run_restart() {
    env PATH="$MOCK_BIN:/usr/bin:/bin" \
        HOME="$TEST_TMP/home" \
        I3_RESTART_CONFIG="$CONFIG" \
        I3_RESTART_TEST_LOG="$LOG" \
        I3_RESTART_TEST_CHECK_FAILURE="$1" \
        I3_RESTART_TEST_MESSAGE_FAILURE="$2" \
        sh "$RESTART" 2>"$ERR"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    sed 's/^/call: /' "$LOG" >&2
    sed 's/^/stderr: /' "$ERR" >&2
    exit 1
}

grep -Fq 'bindsym $mod+Shift+i exec --no-startup-id ~/.config/i3/i3-restart.sh' \
    "$CONFIG" || fail 'Super+Shift+I bypasses the validated restart wrapper'

: >"$LOG"
run_restart 0 0 || fail 'a valid config did not restart i3'
grep -Fxq "i3:-C -c $CONFIG" "$LOG" || fail 'the config was not validated'
grep -Fxq 'i3-msg:restart' "$LOG" || fail 'a valid config did not reach i3-msg'
grep -q '^notify:' "$LOG" && fail 'a successful restart emitted a failure notification'

: >"$LOG"
if run_restart 1 0; then
    fail 'an invalid config was allowed to restart i3'
fi
grep -q '^i3-msg:' "$LOG" && fail 'i3-msg ran after validation failed'
[ "$(grep -c '^notify:' "$LOG")" -eq 1 ] ||
    fail 'validation failure did not emit exactly one notification'
grep -Fq 'mock config parse error' "$ERR" ||
    fail 'validation diagnostics were not preserved on stderr'

: >"$LOG"
if run_restart 0 1; then
    fail 'an i3 IPC failure was reported as success'
fi
[ "$(grep -c '^notify:' "$LOG")" -eq 1 ] ||
    fail 'restart failure did not emit exactly one notification'
grep -Fq 'mock IPC error' "$ERR" || fail 'i3 IPC diagnostics were lost'

printf 'PASS: i3 restart validates first and reports one failure notification\n'
