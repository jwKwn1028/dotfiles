#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
START="$ROOT/dunst-start.sh"
[ -r "$START" ] || START="$ROOT/executable_dunst-start.sh"
DISPLAY_SETUP="$ROOT/display-setup.sh"
[ -r "$DISPLAY_SETUP" ] || DISPLAY_SETUP="$ROOT/executable_display-setup.sh"
OVERRIDE="${DUNST_SYSTEMD_OVERRIDE:-$(dirname "$ROOT")/systemd/user/dunst.service.d/override.conf}"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
RUNTIME="$TEST_TMP/runtime"
MONITORS="$TEST_TMP/monitors"
CONF="$TEST_TMP/dunstrc"
DUNST_LOG="$TEST_TMP/dunst-calls"
SYSTEMCTL_LOG="$TEST_TMP/systemctl-calls"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$MOCK_BIN" "$RUNTIME"

cat >"$MOCK_BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
cat "$DUNST_TEST_MONITORS"
EOF
cat >"$MOCK_BIN/dunst" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DUNST_TEST_DUNST_LOG"
EOF
cat >"$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$DUNST_TEST_SYSTEMCTL_LOG"
EOF
chmod +x "$MOCK_BIN/xrandr" "$MOCK_BIN/dunst" "$MOCK_BIN/systemctl"

cat >"$CONF" <<'EOF'
[global]
    follow = none
    monitor = 0

[urgency_normal]
    timeout = 10
EOF

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    [ -s "$DUNST_LOG" ] && cat "$DUNST_LOG" >&2
    [ -s "$SYSTEMCTL_LOG" ] && cat "$SYSTEMCTL_LOG" >&2
    exit 1
}

run_env() {
    env PATH="$MOCK_BIN:/usr/bin:/bin" \
        DUNST_TEST_MONITORS="$MONITORS" \
        DUNST_TEST_DUNST_LOG="$DUNST_LOG" \
        DUNST_TEST_SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
        DUNST_CONFIG_FILE="$CONF" \
        DUNST_RUNTIME_DIR="$RUNTIME" \
        DUNST_BIN="$MOCK_BIN/dunst" \
        "$@"
}

expect_index() {
    local expected="$1"
    local actual
    actual="$(run_env sh "$START" --monitor-index)"
    [ "$actual" = "$expected" ] || fail "monitor index is $actual, expected $expected"
}

# Prefer the configured output.
cat >"$MONITORS" <<'EOF'
Monitors: 2
 0: +*DP-1 2560/600x1440/340+0+0  DP-1
 1: +eDP 1920/340x1080/190+2560+0  eDP
EOF
expect_index 1
run_env sh "$START"
grep -Eq '^[[:space:]]*monitor = 1$' "$RUNTIME/dunstrc" ||
    fail 'the runtime config did not select eDP index 1'
grep -Eq '^[[:space:]]*monitor = 0$' "$CONF" ||
    fail 'the managed source config was modified'
grep -Fq -- "-conf $RUNTIME/dunstrc" "$DUNST_LOG" ||
    fail 'dunst was not launched with the runtime config'
[ "$(stat -c %a "$RUNTIME/dunstrc")" = 600 ] ||
    fail 'the runtime config is not private'
[ "$(cat "$RUNTIME/monitor-index")" = 1 ] ||
    fail 'the selected monitor index was not recorded'

# Fall back to a generic internal connector.
cat >"$MONITORS" <<'EOF'
Monitors: 2
 0: +*DP-1 2560/600x1440/340+0+0  DP-1
 1: +eDP-1 1920/340x1080/190+2560+0  eDP-1
EOF
I3_LAPTOP_OUTPUT=missing run_env sh "$START" --monitor-index >"$TEST_TMP/index"
[ "$(cat "$TEST_TMP/index")" = 1 ] || fail 'the internal-panel fallback was not used'

# Then fall back to primary and index 0.
cat >"$MONITORS" <<'EOF'
Monitors: 2
 0: +HDMI-1 1920/500x1080/300+0+0  HDMI-1
 1: +*DP-1 2560/600x1440/340+1920+0  DP-1
EOF
expect_index 1
: >"$MONITORS"
expect_index 0

# Restart only when the index changes.
cat >"$MONITORS" <<'EOF'
Monitors: 2
 0: +*DP-1 2560/600x1440/340+0+0  DP-1
 1: +eDP 1920/340x1080/190+2560+0  eDP
EOF
: >"$SYSTEMCTL_LOG"
run_env sh "$START" --sync
[ ! -s "$SYSTEMCTL_LOG" ] || fail 'an unchanged monitor index restarted dunst'

cat >"$MONITORS" <<'EOF'
Monitors: 1
 0: +*eDP 1920/340x1080/190+0+0  eDP
EOF
run_env sh "$START" --sync
grep -Fqx -- '--user try-restart dunst.service' "$SYSTEMCTL_LOG" ||
    fail 'a changed monitor index did not restart dunst'

grep -Fq 'ExecStart=%h/.config/i3/dunst-start.sh' "$OVERRIDE" ||
    fail 'the dunst systemd override does not use the runtime wrapper'
grep -Fq '"$DUNST_START" --sync' "$DISPLAY_SETUP" ||
    fail 'display setup does not resync dunst after RandR changes'

printf 'PASS: dunst 1.9 resolves and tracks the laptop monitor index\n'
