#!/usr/bin/env bash
# Polybar multi-monitor launch behavior.
#
# Each failure message names what its case pins down. The mocks make nm-applet's
# icon appear only on the third probe (redocking before it is back leaves
# Bluetooth left of Wi-Fi, the wrong order for bar mode's h/l) and make one
# Polybar ignore SIGTERM (without the kill timeout the launcher never returns).

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
export POLYBAR_LOG_MAX_BYTES=80
export POLYBAR_LOG_KEEP_LINES=3
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
[ "${POLYBAR_XRANDR_FAIL:-0}" = 1 ] && exit 1
cat "$POLYBAR_TEST_STATE_DIR/xrandr-output"
EOF

cat >"$MOCK_BIN/setsid" <<'EOF'
#!/usr/bin/env bash
if { : >&9; } 2>/dev/null; then
    lock_fd=open
else
    lock_fd=closed
fi
# blueman-tray outlives the launcher, so the lock fd matters there too -- more,
# even: a bar dies with the next relaunch, the applet holds the lock for the
# rest of the session.
if [ "$*" = "-f blueman-tray" ]; then
    printf '%s|%s\n' "$lock_fd" "$*" >>"$POLYBAR_TEST_STATE_DIR/applet-events"
    exit 0
fi
# The tray cursor helper outlives the launcher too, and it is not a bar -- keep
# it out of the file the bar-count assertions read.
case "$*" in
    *tray-cursor.py*)
        printf '%s|%s\n' "$lock_fd" "$*" >>"$POLYBAR_TEST_STATE_DIR/cursor-events"
        exit 0
        ;;
esac
printf '%s|%s|%s\n' "${MONITOR:-}" "$lock_fd" "$*" >>"$POLYBAR_TEST_STATE_DIR/launch-events"
EOF

cat >"$MOCK_BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
printf 'probe %s\n' "$*" >>"$POLYBAR_TEST_STATE_DIR/applet-events"
probes=$(grep -c '^probe ' "$POLYBAR_TEST_STATE_DIR/applet-events")
[ "$probes" -ge 3 ] && printf '4242\n'
exit 0
EOF

cat >"$MOCK_BIN/xwininfo" <<'EOF'
#!/usr/bin/env bash
printf 'Map State: IsViewable\nWidth: 19\nHeight: 19\n'
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
    "-x blueman-tray")
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF

cat >"$MOCK_BIN/pkill" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$POLYBAR_TEST_STATE_DIR/applet-events"
EOF

cat >"$MOCK_BIN/polybar-msg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$POLYBAR_TEST_STATE_DIR/ipc-events"
EOF

chmod +x "$MOCK_BIN"/*

# A transient RandR failure must not tear down the working bars or tray applet.
: >"$MOCK_STATE/killall-events"
: >"$MOCK_STATE/applet-events"
POLYBAR_XRANDR_FAIL=1 bash "$LAUNCHER"
[ ! -s "$MOCK_STATE/killall-events" ] || {
    printf 'FAIL: RandR failure killed existing Polybar processes\n' >&2
    exit 1
}
[ ! -s "$MOCK_STATE/applet-events" ] || {
    printf 'FAIL: RandR failure stopped the Bluetooth tray applet\n' >&2
    exit 1
}

cat >"$MOCK_STATE/xrandr-output" <<'EOF'
Screen 0: minimum 8 x 8, current 4480 x 1440, maximum 32767 x 32767
eDP connected primary 1920x1080+2560+0 (normal left inverted right x axis y axis)
HDMI-A-0 connected 2560x1440+0+0 (normal left inverted right x axis y axis)
DP-1 connected (normal left inverted right x axis y axis)
EOF

: >"$MOCK_STATE/launch-events"
: >"$MOCK_STATE/ipc-events"
: >"$MOCK_STATE/applet-events"
: >"$MOCK_STATE/cursor-events"
for line in $(seq 1 20); do
    printf 'old-%02d-xxxxxxxx\n' "$line"
done >"$POLYBAR_LOG_DIR/polybar-eDP.log"
bash "$LAUNCHER"

grep -Fqx 'eDP|closed|-f polybar --reload tray' "$MOCK_STATE/launch-events" ||
    { printf 'FAIL: tray bar was not launched on eDP\n' >&2; exit 1; }
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
grep -Fqx -- '-x blueman-tray' "$MOCK_STATE/applet-events" ||
    { printf 'FAIL: blueman-tray was not stopped before Polybar\n' >&2; exit 1; }
grep -Fqx -- 'closed|-f blueman-tray' "$MOCK_STATE/applet-events" ||
    { printf 'FAIL: blueman-tray was not redocked with the lock fd closed\n' >&2
      cat "$MOCK_STATE/applet-events" >&2; exit 1; }
[ "$(tail -n 1 "$MOCK_STATE/applet-events")" = 'closed|-f blueman-tray' ] ||
    { printf 'FAIL: blueman-tray was redocked before nm-applet had docked\n' >&2
      cat "$MOCK_STATE/applet-events" >&2; exit 1; }
[ "$(grep -c '^probe ' "$MOCK_STATE/applet-events")" -ge 3 ] ||
    { printf 'FAIL: the redock did not wait for nm-applet\n' >&2; exit 1; }
grep -q '^closed|.*tray-cursor\.py' "$MOCK_STATE/cursor-events" ||
    { printf 'FAIL: the tray cursor helper was not started with the lock fd closed\n' >&2
      cat "$MOCK_STATE/cursor-events" >&2; exit 1; }
if grep -Fq 'old-01-' "$POLYBAR_LOG_DIR/polybar-eDP.log"; then
    printf 'FAIL: an oversized Polybar log kept its oldest lines\n' >&2
    exit 1
fi
[ "$(grep -c '^old-' "$POLYBAR_LOG_DIR/polybar-eDP.log")" -le 3 ] ||
    { printf 'FAIL: Polybar log rotation kept more than the configured tail\n' >&2
      exit 1; }
grep -Fq 'old-20-' "$POLYBAR_LOG_DIR/polybar-eDP.log" ||
    { printf 'FAIL: Polybar log rotation discarded the newest old line\n' >&2
      exit 1; }

cat >"$MOCK_STATE/xrandr-output" <<'EOF'
Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767
eDP connected primary 1920x1080+0+0 (normal left inverted right x axis y axis)
EOF
: >"$MOCK_STATE/launch-events"
: >"$MOCK_STATE/ipc-events"
bash "$LAUNCHER"
grep -Fqx 'eDP|closed|-f polybar --reload tray' "$MOCK_STATE/launch-events" ||
    { printf 'FAIL: primary bar did not receive the tray fallback\n' >&2; exit 1; }

DEFAULT_STATE_HOME="$MOCK_STATE/default-state-home"
: >"$MOCK_STATE/launch-events"
: >"$MOCK_STATE/ipc-events"
env -u POLYBAR_LOG_DIR XDG_STATE_HOME="$DEFAULT_STATE_HOME" bash "$LAUNCHER"
[ -f "$DEFAULT_STATE_HOME/polybar/polybar-eDP.log" ] ||
    { printf 'FAIL: the default Polybar log did not use XDG_STATE_HOME\n' >&2
      exit 1; }

cat >"$MOCK_STATE/xrandr-output" <<'EOF'
Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767
eDP/../../owned connected primary 1920x1080+0+0 (normal left inverted right x axis y axis)
EOF
: >"$MOCK_STATE/launch-events"
: >"$MOCK_STATE/ipc-events"
bash "$LAUNCHER"
grep -Fqx 'eDP/../../owned|closed|-f polybar --reload tray' \
    "$MOCK_STATE/launch-events" ||
    { printf 'FAIL: a monitor with path punctuation was not launched\n' >&2; exit 1; }
[ -f "$POLYBAR_LOG_DIR/polybar-eDP_.._.._owned.log" ] ||
    { printf 'FAIL: unsafe monitor-name characters reached the log path\n' >&2
      exit 1; }

cat >"$MOCK_STATE/xrandr-output" <<'EOF'
Screen 0: minimum 8 x 8, current 4480 x 1440, maximum 32767 x 32767
eDP connected primary 1920x1080+2560+0 (normal left inverted right x axis y axis)
HDMI-A-0 connected 2560x1440+0+0 (normal left inverted right x axis y axis)
DP-1 connected (normal left inverted right x axis y axis)
EOF

cat >"$MOCK_BIN/killall" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$POLYBAR_TEST_STATE_DIR/killall-events"
case "$*" in
    *--wait*) sleep 60 ;;
esac
EOF
chmod +x "$MOCK_BIN/killall"

: >"$MOCK_STATE/launch-events"
: >"$MOCK_STATE/ipc-events"
: >"$MOCK_STATE/killall-events"
bash "$LAUNCHER"

grep -Fq -- '-9 polybar' "$MOCK_STATE/killall-events" ||
    { printf 'FAIL: a hung graceful kill was not escalated to SIGKILL\n' >&2; exit 1; }
[ "$(wc -l <"$MOCK_STATE/launch-events")" -eq 2 ] ||
    { printf 'FAIL: hung kill stopped the bars from being relaunched\n' >&2; exit 1; }

printf 'PASS: Polybar multi-monitor launch behavior\n'
