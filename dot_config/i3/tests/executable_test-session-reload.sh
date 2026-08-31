#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
RELOAD="$ROOT/session-reload.sh"
[ -r "$RELOAD" ] || RELOAD="$ROOT/executable_session-reload.sh"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
TEST_HOME="$TEST_TMP/home"
LOG="$TEST_TMP/systemctl-calls"
PICOM_LOG="$TEST_TMP/picom-calls"
DISPLAY_LOG="$TEST_TMP/display-calls"
NOTIFY_LOG="$TEST_TMP/notify-calls"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$MOCK_BIN" "$TEST_HOME/.config/dunst"

cat >"$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SESSION_RELOAD_TEST_LOG"
if [ "${1:-}" = --user ] && [ "${2:-}" = show ]; then
    printf '%s\n' "$SESSION_RELOAD_TEST_DUNST_STARTED"
fi
if [ -n "${SESSION_RELOAD_TEST_SYSTEMCTL_FAILURE:-}" ] &&
    [[ "$*" == *"$SESSION_RELOAD_TEST_SYSTEMCTL_FAILURE"* ]]; then
    exit 1
fi
EOF
chmod +x "$MOCK_BIN/systemctl"

cat >"$MOCK_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
if [ "$*" = '-x picom' ] && [ "$SESSION_RELOAD_TEST_PICOM_RUNNING" = 1 ]; then
    exit 0
fi
exit 1
EOF
chmod +x "$MOCK_BIN/pgrep"

cat >"$MOCK_BIN/pkill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SESSION_RELOAD_TEST_PICOM_LOG"
[ "$SESSION_RELOAD_TEST_PICOM_FAILURE" = 0 ]
EOF
chmod +x "$MOCK_BIN/pkill"

cat >"$MOCK_BIN/display-setup" <<'EOF'
#!/usr/bin/env bash
printf 'call\nreload=%s\ntext=%s\n' \
    "${I3_RELOAD_TOAST:-}" "${I3_DISPLAY_TOAST:-}" \
    >>"$SESSION_RELOAD_TEST_DISPLAY_LOG"
[ "$SESSION_RELOAD_TEST_DISPLAY_FAILURE" = 0 ]
EOF
chmod +x "$MOCK_BIN/display-setup"

cat >"$MOCK_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SESSION_RELOAD_TEST_NOTIFY_LOG"
EOF
chmod +x "$MOCK_BIN/notify-send"

run() {
    : >"$LOG"
    : >"$PICOM_LOG"
    : >"$DISPLAY_LOG"
    : >"$NOTIFY_LOG"
    env PATH="$MOCK_BIN:/usr/bin:/bin" HOME="$TEST_HOME" \
        SESSION_RELOAD_TEST_LOG="$LOG" \
        SESSION_RELOAD_TEST_DUNST_STARTED="$1" \
        SESSION_RELOAD_TEST_PICOM_RUNNING="${2:-1}" \
        SESSION_RELOAD_TEST_SYSTEMCTL_FAILURE="${3:-}" \
        SESSION_RELOAD_TEST_PICOM_FAILURE="${4:-0}" \
        SESSION_RELOAD_TEST_DISPLAY_FAILURE="${5:-0}" \
        SESSION_RELOAD_TEST_PICOM_LOG="$PICOM_LOG" \
        SESSION_RELOAD_TEST_DISPLAY_LOG="$DISPLAY_LOG" \
        SESSION_RELOAD_TEST_NOTIFY_LOG="$NOTIFY_LOG" \
        I3_DISPLAY_SETUP="$MOCK_BIN/display-setup" \
        sh "$RELOAD"
}
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    sed 's/^/systemctl: /' "$LOG" >&2
    sed 's/^/picom: /' "$PICOM_LOG" >&2
    sed 's/^/display: /' "$DISPLAY_LOG" >&2
    sed 's/^/notify: /' "$NOTIFY_LOG" >&2
    exit 1
}

conf="$TEST_HOME/.config/dunst/dunstrc"
: >"$conf"

# Leave dunst alone when its config is older.
touch -d '2020-01-01 00:00:00' "$conf"
run 'Wed 2026-08-26 10:00:00 KST'
grep -Fq -- '--user daemon-reload' "$LOG" || fail 'daemon-reload was not run'
grep -Fq -- 'try-restart dunst.service' "$LOG" &&
    fail 'dunst was restarted even though its config was older'
grep -Fq -- 'try-restart task-notify.timer' "$LOG" ||
    fail 'the reminder timer was not re-read'
grep -Fxq -- '-USR1 -x picom' "$PICOM_LOG" ||
    fail 'a running picom did not receive SIGUSR1'
[ "$(grep -c '^call$' "$DISPLAY_LOG")" -eq 1 ] ||
    fail 'display setup did not run exactly once'
grep -Fxq 'reload=1' "$DISPLAY_LOG" ||
    fail 'display setup was not asked to show the reload toast'
grep -Fxq 'text=' "$DISPLAY_LOG" ||
    fail 'a successful reload unexpectedly supplied failure text'

# Restart dunst for a newer config.
touch -d '2030-01-01 00:00:00' "$conf"
run 'Wed 2026-08-26 10:00:00 KST'
grep -Fq -- 'try-restart dunst.service' "$LOG" ||
    fail 'a changed dunstrc did not restart dunst'

# An inactive dunst is harmless.
run ''
grep -Fq -- '--user daemon-reload' "$LOG" || fail 'daemon-reload was skipped without dunst'
grep -Fq -- 'try-restart task-notify.timer' "$LOG" ||
    fail 'the reminder timer was skipped without dunst'

# Missing dunstrc is harmless.
rm -f "$conf"
run 'Wed 2026-08-26 10:00:00 KST'
grep -Fq -- 'try-restart dunst.service' "$LOG" &&
    fail 'dunst was restarted with no dunstrc present'

# i3 autostart handles a stopped Picom.
run 'Wed 2026-08-26 10:00:00 KST' 0
[ ! -s "$PICOM_LOG" ] || fail 'a stopped picom was signalled'
grep -Fxq 'text=' "$DISPLAY_LOG" ||
    fail 'a stopped picom was incorrectly reported as a reload failure'

# Aggregate failures into one toast.
run 'Wed 2026-08-26 10:00:00 KST' 1 'task-notify.timer' 1
grep -Fxq 'text=i3 reload partial: task timer, picom' "$DISPLAY_LOG" ||
    fail 'component failures were not aggregated in the reload toast'
[ "$(grep -c '^call$' "$DISPLAY_LOG")" -eq 1 ] ||
    fail 'a partial failure emitted more than one display toast request'
[ ! -s "$NOTIFY_LOG" ] || fail 'a working display toast triggered a fallback notification'

# Fall back to notify-send if display setup fails.
run 'Wed 2026-08-26 10:00:00 KST' 1 '' 0 1
[ "$(wc -l <"$NOTIFY_LOG")" -eq 1 ] ||
    fail 'display failure did not emit exactly one fallback notification'
grep -Fxq -- '-u critical i3 reload partial display setup' "$NOTIFY_LOG" ||
    fail 'display failure fallback did not identify the failed component'

printf 'PASS: session reload refreshes services and picom with one summary toast\n'
