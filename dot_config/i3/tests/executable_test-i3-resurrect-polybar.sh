#!/usr/bin/env bash
# The restore wrapper must preserve Polybar's pre-restore visibility, including
# failures after the bar has been hidden. The mocks exercise the real shared
# Polybar helpers without touching the running i3/X11 session.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
RESTORE="$ROOT/i3-resurrect-restore-all.sh"
[ -r "$RESTORE" ] || RESTORE="$ROOT/executable_i3-resurrect-restore-all.sh"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
MOCK_STATE="$TEST_TMP/state"
STATE_DIR="$TEST_TMP/resurrect"
META_DIR="$TEST_TMP/resurrect-meta"

cleanup() {
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT

if [ ! -r "$ROOT/_snap-common.sh" ]; then
    APPLIED_ROOT="$TEST_TMP/i3"
    mkdir -p "$APPLIED_ROOT"
    cp -p -- "$RESTORE" "$APPLIED_ROOT/i3-resurrect-restore-all.sh"
    cp -p -- "$ROOT/_polybar-common.sh" "$APPLIED_ROOT/_polybar-common.sh"
    cp -p -- "$ROOT/executable__snap-common.sh" "$APPLIED_ROOT/_snap-common.sh"
    RESTORE="$APPLIED_ROOT/i3-resurrect-restore-all.sh"
fi

mkdir -p "$MOCK_BIN" "$MOCK_STATE/runtime" "$STATE_DIR" "$META_DIR"
printf '1\n' >"$META_DIR/workspaces.txt"

export PATH="$MOCK_BIN:/usr/bin:/bin"
export XDG_RUNTIME_DIR="$MOCK_STATE/runtime"
export I3_RESURRECT_STATE_DIR="$STATE_DIR"
export I3_RESURRECT_META_DIR="$META_DIR"
export I3_RESURRECT_LAYOUT_DELAY=0
export I3_RESURRECT_KILL_WAIT_ATTEMPTS=1
export I3_RESURRECT_KILL_POLL_INTERVAL=0
export I3_RESURRECT_WAIT_ATTEMPTS=1
export I3_RESURRECT_POLL_INTERVAL=0
export I3_POLYBAR_SETTLE_MS=10
export RESTORE_TEST_STATE_DIR="$MOCK_STATE"

cat >"$MOCK_BIN/i3-resurrect" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RESTORE_TEST_STATE_DIR/resurrect-events"
exit 0
EOF
export I3_RESURRECT="$MOCK_BIN/i3-resurrect"

cat >"$MOCK_BIN/i3-msg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RESTORE_TEST_STATE_DIR/i3-events"
case "$*" in
    '-t get_tree')
        if [ "${RESTORE_TREE_MODE:-empty}" = blocked ]; then
            printf '%s\n' '{"id":1,"type":"root","nodes":[{"id":99,"type":"con","window":123,"nodes":[]}]}'
        else
            printf '%s\n' '{"id":1,"type":"root","nodes":[{"id":10,"type":"workspace","name":"1","nodes":[],"floating_nodes":[]}]}'
        fi
        ;;
    '-t get_outputs')
        printf '%s\n' '[{"name":"eDP","active":true}]'
        ;;
    *)
        printf '%s\n' '[{"success":true}]'
        ;;
esac
EOF

cat >"$MOCK_BIN/polybar-msg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RESTORE_TEST_STATE_DIR/polybar-events"
case "$*" in
    'cmd hide') printf 'hidden\n' >"$RESTORE_TEST_STATE_DIR/polybar-state" ;;
    'cmd show') printf 'visible\n' >"$RESTORE_TEST_STATE_DIR/polybar-state" ;;
esac
EOF

cat >"$MOCK_BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    search)
        printf '4242\n'
        ;;
    windowraise)
        printf '%s\n' "$*" >>"$RESTORE_TEST_STATE_DIR/x-events"
        ;;
esac
EOF

cat >"$MOCK_BIN/xwininfo" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *'-tree'*)
        printf 'Parent window id: 0x1 (the root window)\n'
        ;;
    *)
        if [ "$(cat "$RESTORE_TEST_STATE_DIR/polybar-state")" = visible ]; then
            printf 'Map State: IsViewable\n'
        else
            printf 'Map State: IsUnMapped\n'
        fi
        ;;
esac
EOF

cat >"$MOCK_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RESTORE_TEST_STATE_DIR/notify-events"
EOF

chmod +x "$MOCK_BIN"/*

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

reset_case() {
    printf '%s\n' "$1" >"$MOCK_STATE/polybar-state"
    export RESTORE_TREE_MODE="$2"
    : >"$MOCK_STATE/polybar-events"
    : >"$MOCK_STATE/x-events"
    : >"$MOCK_STATE/i3-events"
    : >"$MOCK_STATE/resurrect-events"
    : >"$MOCK_STATE/notify-events"
}

assert_polybar_sequence() {
    local first="$1"
    local second="${2:-}"
    local count

    count="$(wc -l <"$MOCK_STATE/polybar-events")"
    [ "$count" -eq "$#" ] ||
        fail "expected $# Polybar command(s), got $count"
    [ "$(sed -n '1p' "$MOCK_STATE/polybar-events")" = "$first" ] ||
        fail "first Polybar command was not '$first'"
    if [ "$#" -eq 2 ]; then
        [ "$(sed -n '2p' "$MOCK_STATE/polybar-events")" = "$second" ] ||
            fail "second Polybar command was not '$second'"
    fi
}

run_restore() {
    local expected_status="$1"
    local status=0

    bash "$RESTORE" 2>"$MOCK_STATE/restore-stderr" || status="$?"
    [ "$status" -eq "$expected_status" ] ||
        fail "restore exited $status; expected $expected_status"
}

reset_case visible empty
run_restore 0
assert_polybar_sequence 'cmd hide' 'cmd show'
grep -Fqx 'windowraise 4242' "$MOCK_STATE/x-events" ||
    fail 'a previously visible bar was not raised after a successful restore'
[ "$(wc -l <"$MOCK_STATE/resurrect-events")" -eq 2 ] ||
    fail 'the success case did not restore both layout and programs'

reset_case hidden empty
run_restore 0
[ ! -s "$MOCK_STATE/polybar-events" ] ||
    fail 'an initially hidden bar was changed during restore'
[ ! -s "$MOCK_STATE/x-events" ] ||
    fail 'an initially hidden bar was raised during restore'

reset_case visible blocked
run_restore 1
assert_polybar_sequence 'cmd hide' 'cmd show'
grep -Fq 'Timed out waiting for existing window(s) to close' \
    "$MOCK_STATE/restore-stderr" ||
    fail 'the early restore failure did not report its cause'
grep -Fqx 'windowraise 4242' "$MOCK_STATE/x-events" ||
    fail 'the EXIT trap did not raise the bar after an early restore failure'
[ ! -s "$MOCK_STATE/resurrect-events" ] ||
    fail 'restore continued after existing windows failed to close'

printf 'PASS: i3-resurrect preserves Polybar visibility\n'
