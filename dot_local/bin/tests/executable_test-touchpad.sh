#!/usr/bin/env bash
set -euo pipefail

BIN_ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TOUCHPAD="$BIN_ROOT/touchpad"
[ -r "$TOUCHPAD" ] || TOUCHPAD="$BIN_ROOT/executable_touchpad"
SOURCE_ROOT="$(readlink -f "$BIN_ROOT/../..")"
WRAPPER="$SOURCE_ROOT/executable_dot_toggle-touchpad.sh"
[ -r "$WRAPPER" ] || WRAPPER="$HOME/.toggle-touchpad.sh"

TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
STATE_HOME="$TEST_TMP/state"
ACTION_LOG="$TEST_TMP/actions"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$MOCK_BIN" "$STATE_HOME"

cat >"$MOCK_BIN/xinput" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    list)
        if [ "${2:-}" = --name-only ]; then
            printf 'ELAN0688 device %s\n' "${3:-unknown}"
        else
            printf '%s\n' \
                '↳ ELAN0688 Touchpad id=12 [slave pointer]' \
                '↳ ELAN0688 Mouse id=13 [slave pointer]'
        fi
        ;;
    enable|disable)
        printf '%s %s\n' "$1" "$2" >>"$TOUCHPAD_TEST_ACTION_LOG"
        [ "${TOUCHPAD_TEST_FAIL_ID:-}" != "$2" ]
        ;;
    *) exit 1 ;;
esac
EOF

cat >"$MOCK_BIN/xfconf-query" <<'EOF'
#!/usr/bin/env bash
case " $* " in
    *' -s '*)
        printf 'xfconf %s\n' "$*" >>"$TOUCHPAD_TEST_ACTION_LOG"
        [ "${TOUCHPAD_TEST_XFCONF_FAIL:-0}" != 1 ]
        ;;
    *) exit 0 ;;
esac
EOF
chmod +x "$MOCK_BIN/xinput" "$MOCK_BIN/xfconf-query"

status=0
env PATH="$MOCK_BIN:/usr/bin:/bin" \
    XDG_STATE_HOME="$STATE_HOME" \
    TOUCHPAD_TEST_ACTION_LOG="$ACTION_LOG" \
    TOUCHPAD_TEST_FAIL_ID=13 \
    bash "$TOUCHPAD" disable >/dev/null 2>"$TEST_TMP/failure" || status=$?
[ "$status" -ne 0 ] || {
    printf 'FAIL: partial xinput failure was reported as success\n' >&2
    exit 1
}
[ ! -e "$STATE_HOME/touchpad.state" ] || {
    printf 'FAIL: failed disable still updated persistent state\n' >&2
    exit 1
}

: >"$ACTION_LOG"
env PATH="$MOCK_BIN:/usr/bin:/bin" \
    XDG_STATE_HOME="$STATE_HOME" \
    TOUCHPAD_TEST_ACTION_LOG="$ACTION_LOG" \
    bash "$TOUCHPAD" disable >/dev/null
[ "$(cat "$STATE_HOME/touchpad.state")" = disabled ] || {
    printf 'FAIL: successful disable did not persist its state\n' >&2
    exit 1
}
[ "$(grep -c '^disable ' "$ACTION_LOG")" -eq 2 ] || {
    printf 'FAIL: disable did not reach both touchpad nodes\n' >&2
    exit 1
}

status=0
env PATH="$MOCK_BIN:/usr/bin:/bin" \
    XDG_STATE_HOME="$STATE_HOME" \
    TOUCHPAD_TEST_ACTION_LOG="$ACTION_LOG" \
    TOUCHPAD_TEST_XFCONF_FAIL=1 \
    bash "$TOUCHPAD" enable >/dev/null 2>"$TEST_TMP/xfconf-failure" || status=$?
[ "$status" -ne 0 ] || {
    printf 'FAIL: XFCE synchronization failure was reported as success\n' >&2
    exit 1
}
[ "$(cat "$STATE_HOME/touchpad.state")" = disabled ] || {
    printf 'FAIL: XFCE failure still changed persistent state\n' >&2
    exit 1
}

cat >"$MOCK_BIN/canonical-touchpad" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$TOUCHPAD_WRAPPER_LOG"
EOF
chmod +x "$MOCK_BIN/canonical-touchpad"
env TOUCHPAD_BIN="$MOCK_BIN/canonical-touchpad" \
    TOUCHPAD_WRAPPER_LOG="$TEST_TMP/wrapper" \
    bash "$WRAPPER" on
[ "$(cat "$TEST_TMP/wrapper")" = enable ] || {
    printf 'FAIL: legacy wrapper did not delegate on -> enable\n' >&2
    exit 1
}

printf 'PASS: touchpad state changes require every backend operation\n'
