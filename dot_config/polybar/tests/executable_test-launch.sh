#!/usr/bin/env bash

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
LAUNCHER="$ROOT/launch.sh"
[ -x "$LAUNCHER" ] || LAUNCHER="$ROOT/executable_launch.sh"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
MOCK_STATE="$TEST_TMP/state"

cleanup() {
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$MOCK_STATE/runtime" "$MOCK_STATE/log"
export PATH="$MOCK_BIN:/usr/bin:/bin"
export XDG_RUNTIME_DIR="$MOCK_STATE/runtime"
export POLYBAR_LOG_DIR="$MOCK_STATE/log"
export POLYBAR_TEST_STATE_DIR="$MOCK_STATE"

cat >"$MOCK_BIN/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"$MOCK_BIN/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$POLYBAR_TEST_STATE_DIR/killall-events"
EOF

cat >"$MOCK_BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
cat "$POLYBAR_TEST_STATE_DIR/xrandr-output"
EOF

cat >"$MOCK_BIN/setsid" <<'EOF'
#!/usr/bin/env bash
if { : >&9; } 2>/dev/null; then
    lock_fd=open
else
    lock_fd=closed
fi
printf '%s|%s|%s\n' "${MONITOR:-}" "$lock_fd" "$*" >>"$POLYBAR_TEST_STATE_DIR/launch-events"
EOF

cat >"$MOCK_BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    "-xc polybar")
        wc -l <"$POLYBAR_TEST_STATE_DIR/launch-events"
        ;;
    "-x polybar")
        [ -s "$POLYBAR_TEST_STATE_DIR/launch-events" ]
        ;;
    *)
        exit 1
        ;;
esac
EOF

cat >"$MOCK_BIN/polybar-msg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$POLYBAR_TEST_STATE_DIR/ipc-events"
EOF

chmod +x "$MOCK_BIN"/*

cat >"$MOCK_STATE/xrandr-output" <<'EOF'
Screen 0: minimum 8 x 8, current 4480 x 1440, maximum 32767 x 32767
eDP connected primary 1920x1080+2560+0 (normal left inverted right x axis y axis)
HDMI-A-0 connected 2560x1440+0+0 (normal left inverted right x axis y axis)
DP-1 connected (normal left inverted right x axis y axis)
EOF

: >"$MOCK_STATE/launch-events"
: >"$MOCK_STATE/ipc-events"
bash "$LAUNCHER"

grep -Fqx 'eDP|closed|-f polybar --reload main' "$MOCK_STATE/launch-events" ||
    { printf 'FAIL: primary bar was not launched on eDP\n' >&2; exit 1; }
grep -Fqx 'HDMI-A-0|closed|-f polybar --reload external' "$MOCK_STATE/launch-events" ||
    { printf 'FAIL: external bar was not launched on HDMI-A-0\n' >&2; exit 1; }
if grep -Fq 'DP-1|' "$MOCK_STATE/launch-events"; then
    printf 'FAIL: a bar was launched on connected but inactive DP-1\n' >&2
    exit 1
fi
[ "$(wc -l <"$MOCK_STATE/launch-events")" -eq 2 ] ||
    { printf 'FAIL: expected exactly two bar instances\n' >&2; exit 1; }
grep -Fqx 'cmd hide' "$MOCK_STATE/ipc-events" ||
    { printf 'FAIL: startup visibility was not broadcast\n' >&2; exit 1; }

printf 'PASS: Polybar multi-monitor launch behavior\n'
