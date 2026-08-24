#!/usr/bin/env bash
# Every confirmation backend must act only on explicit acceptance. In
# particular, the timeout statuses that used to trigger a delayed shutdown are
# cancellation paths.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
SCRIPT="$ROOT/scripts/confirm-poweroff.sh"
[ -r "$SCRIPT" ] || SCRIPT="$ROOT/scripts/executable_confirm-poweroff.sh"
TEST_TMP="$(mktemp -d)"
ACTION_LOG="$TEST_TMP/actions"

cleanup() {
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT

make_common_mocks() {
    local bin="$1"
    mkdir -p "$bin"

    cat >"$bin/systemctl" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$POWER_ACTION_LOG"
EOF

    cat >"$bin/timeout" <<'EOF'
#!/bin/bash
shift
exec "$@"
EOF

    chmod +x "$bin/systemctl" "$bin/timeout"
}

ZENITY_BIN="$TEST_TMP/zenity-bin"
make_common_mocks "$ZENITY_BIN"
cat >"$ZENITY_BIN/zenity" <<'EOF'
#!/bin/bash
exit "${POWER_DIALOG_STATUS:-1}"
EOF
chmod +x "$ZENITY_BIN/zenity"

ROFI_BIN="$TEST_TMP/rofi-bin"
make_common_mocks "$ROFI_BIN"
cat >"$ROFI_BIN/rofi" <<'EOF'
#!/bin/bash
printf '%s\n' "${POWER_DIALOG_CHOICE:-}"
exit "${POWER_DIALOG_STATUS:-1}"
EOF
chmod +x "$ROFI_BIN/rofi"

XMESSAGE_BIN="$TEST_TMP/xmessage-bin"
make_common_mocks "$XMESSAGE_BIN"
cat >"$XMESSAGE_BIN/xmessage" <<'EOF'
#!/bin/bash
exit "${POWER_DIALOG_STATUS:-1}"
EOF
chmod +x "$XMESSAGE_BIN/xmessage"

NO_DIALOG_BIN="$TEST_TMP/no-dialog-bin"
NOTIFY_LOG="$TEST_TMP/notifications"
make_common_mocks "$NO_DIALOG_BIN"
cat >"$NO_DIALOG_BIN/notify-send" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$POWER_NOTIFY_LOG"
EOF
chmod +x "$NO_DIALOG_BIN/notify-send"

run_prompt() {
    local bin="$1"
    local action="$2"
    local status="$3"
    local choice="${4:-}"

    : >"$ACTION_LOG"
    env \
        PATH="$bin" \
        POWER_ACTION_LOG="$ACTION_LOG" \
        POWER_DIALOG_STATUS="$status" \
        POWER_DIALOG_CHOICE="$choice" \
        /usr/bin/bash "$SCRIPT" "$action" 1
}

assert_action() {
    local expected="$1"
    grep -Fqx "$expected" "$ACTION_LOG" || {
        printf 'FAIL: expected systemctl %s, got:\n' "$expected" >&2
        cat "$ACTION_LOG" >&2
        exit 1
    }
}

assert_cancelled() {
    [ ! -s "$ACTION_LOG" ] || {
        printf 'FAIL: a cancelled prompt still ran systemctl:\n' >&2
        cat "$ACTION_LOG" >&2
        exit 1
    }
}

run_prompt "$ZENITY_BIN" poweroff 0
assert_action poweroff
run_prompt "$ZENITY_BIN" poweroff 5
assert_cancelled

run_prompt "$ROFI_BIN" reboot 0 Restart
assert_action reboot
run_prompt "$ROFI_BIN" reboot 0 Cancel
assert_cancelled
run_prompt "$ROFI_BIN" reboot 124
assert_cancelled

run_prompt "$XMESSAGE_BIN" poweroff 0
assert_action poweroff
run_prompt "$XMESSAGE_BIN" poweroff 124
assert_cancelled

: >"$ACTION_LOG"
: >"$NOTIFY_LOG"
status=0
env \
    PATH="$NO_DIALOG_BIN" \
    POWER_ACTION_LOG="$ACTION_LOG" \
    POWER_NOTIFY_LOG="$NOTIFY_LOG" \
    /usr/bin/bash "$SCRIPT" poweroff 1 || status="$?"
[ "$status" -eq 1 ] || {
    printf 'FAIL: no-dialog cancellation exited %s instead of 1\n' "$status" >&2
    exit 1
}
assert_cancelled
grep -Fq 'Power action cancelled' "$NOTIFY_LOG" || {
    printf 'FAIL: the missing-dialog path did not notify the user\n' >&2
    exit 1
}

if env PATH="$ZENITY_BIN" /usr/bin/bash "$SCRIPT" suspend 1 >/dev/null 2>&1; then
    printf 'FAIL: an unsupported power action was accepted\n' >&2
    exit 1
fi
if env PATH="$ZENITY_BIN" /usr/bin/bash "$SCRIPT" poweroff 0 >/dev/null 2>&1; then
    printf 'FAIL: a zero confirmation timeout was accepted\n' >&2
    exit 1
fi
if env PATH="$ZENITY_BIN" /usr/bin/bash "$SCRIPT" poweroff later >/dev/null 2>&1; then
    printf 'FAIL: a nonnumeric confirmation timeout was accepted\n' >&2
    exit 1
fi

printf 'PASS: power confirmation is fail-safe\n'
