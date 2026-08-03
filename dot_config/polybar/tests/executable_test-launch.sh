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
# blueman-tray outlives the launcher, so the lock fd matters there too -- more,
# even: a bar dies with the next relaunch, the applet holds the lock for the
# rest of the session.
if [ "$*" = "-f blueman-tray" ]; then
    printf '%s|%s\n' "$lock_fd" "$*" >>"$POLYBAR_TEST_STATE_DIR/applet-events"
    exit 0
fi
printf '%s|%s|%s\n' "${MONITOR:-}" "$lock_fd" "$*" >>"$POLYBAR_TEST_STATE_DIR/launch-events"
EOF

# nm-applet's icon shows up on the third probe, so the redock has to wait.
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

cat >"$MOCK_STATE/xrandr-output" <<'EOF'
Screen 0: minimum 8 x 8, current 4480 x 1440, maximum 32767 x 32767
eDP connected primary 1920x1080+2560+0 (normal left inverted right x axis y axis)
HDMI-A-0 connected 2560x1440+0+0 (normal left inverted right x axis y axis)
DP-1 connected (normal left inverted right x axis y axis)
EOF

: >"$MOCK_STATE/launch-events"
: >"$MOCK_STATE/ipc-events"
: >"$MOCK_STATE/applet-events"
bash "$LAUNCHER"

# The tray is pinned to the internal panel, so eDP gets it even with an external
# output attached, and the external output gets the trayless layout.
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
# Dock order is arrival order: redocking before nm-applet's icon is back puts
# Bluetooth left of Wi-Fi, and bar mode's H/L then walks the two stops leftward.
[ "$(tail -n 1 "$MOCK_STATE/applet-events")" = 'closed|-f blueman-tray' ] ||
    { printf 'FAIL: blueman-tray was redocked before nm-applet had docked\n' >&2
      cat "$MOCK_STATE/applet-events" >&2; exit 1; }
[ "$(grep -c '^probe ' "$MOCK_STATE/applet-events")" -ge 3 ] ||
    { printf 'FAIL: the redock did not wait for nm-applet\n' >&2; exit 1; }

# With no external output, the laptop panel still owns the one X11 tray.
cat >"$MOCK_STATE/xrandr-output" <<'EOF'
Screen 0: minimum 8 x 8, current 1920 x 1080, maximum 32767 x 32767
eDP connected primary 1920x1080+0+0 (normal left inverted right x axis y axis)
EOF
: >"$MOCK_STATE/launch-events"
: >"$MOCK_STATE/ipc-events"
bash "$LAUNCHER"
grep -Fqx 'eDP|closed|-f polybar --reload tray' "$MOCK_STATE/launch-events" ||
    { printf 'FAIL: primary bar did not receive the tray fallback\n' >&2; exit 1; }

cat >"$MOCK_STATE/xrandr-output" <<'EOF'
Screen 0: minimum 8 x 8, current 4480 x 1440, maximum 32767 x 32767
eDP connected primary 1920x1080+2560+0 (normal left inverted right x axis y axis)
HDMI-A-0 connected 2560x1440+0+0 (normal left inverted right x axis y axis)
DP-1 connected (normal left inverted right x axis y axis)
EOF

# A Polybar that ignores SIGTERM must not wedge the launcher: without the kill
# timeout the run below never returns and no bar reaches the second monitor.
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
