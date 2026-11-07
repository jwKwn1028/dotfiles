#!/usr/bin/env bash

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT

SETUP="$ROOT/display-setup.sh"
[ -r "$SETUP" ] || SETUP="$ROOT/executable_display-setup.sh"

WORK="$TEST_TMP/i3"
MOCK_BIN="$TEST_TMP/bin"
OUTPUTS="$TEST_TMP/outputs"
CALLS="$TEST_TMP/xrandr-calls"
ERRORS="$TEST_TMP/stderr"
mkdir -p "$WORK" "$MOCK_BIN"

cp -- "$SETUP" "$WORK/display-setup.sh"
cp -- "$ROOT/_toast-common.sh" "$WORK/_toast-common.sh"
printf '#!/bin/sh\n' >"$WORK/wallpaper.sh"
chmod +x "$WORK/display-setup.sh" "$WORK/wallpaper.sh"

cat >"$MOCK_BIN/xrandr" <<EOF
#!/bin/sh
if [ "\$*" = --query ]; then
    while read -r name state; do
        printf '%s %s 1920x1080+0+0 (normal left inverted right x axis y axis)\n' "\$name" "\$state"
    done <'$OUTPUTS'
else
    printf '%s\n' "\$*" >>'$CALLS'
fi
EOF
# No-op sleep: the no-panel case would otherwise wait out the 5 s panel retry.
printf '#!/bin/sh\n' >"$MOCK_BIN/sleep"
chmod +x "$MOCK_BIN/xrandr" "$MOCK_BIN/sleep"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    [ -s "$CALLS" ] && cat "$CALLS" >&2
    [ -s "$ERRORS" ] && cat "$ERRORS" >&2
    exit 1
}

set_outputs() {
    : >"$OUTPUTS"
    while [ "$#" -gt 0 ]; do
        printf '%s %s\n' "$1" "$2" >>"$OUTPUTS"
        shift 2
    done
}

# env -i keeps I3_* variables exported by the caller's shell out of the run.
run_setup() {
    : >"$CALLS"
    env -i PATH="$MOCK_BIN:/usr/bin:/bin" \
        XDG_RUNTIME_DIR="$TEST_TMP" \
        I3_DISPLAY_SETUP_DELAY=0 \
        I3_DUNST_START=/nonexistent \
        I3_POLYBAR_LAUNCHER=/nonexistent \
        "$@" bash "$WORK/display-setup.sh" >/dev/null 2>"$ERRORS" ||
        fail 'display-setup.sh exited non-zero'
}

expect_call() {
    local expected="$1" message="$2"
    [ "$(cat "$CALLS")" = "$expected" ] || fail "$message"
}

set_outputs eDP-1 connected DP-1 disconnected DP-2 connected
run_setup
expect_call \
    '--output DP-2 --auto --pos 0x0 --rotate normal --output eDP-1 --primary --auto --right-of DP-2 --rotate normal' \
    'an eDP-1 panel was not made primary beside the external monitor'

set_outputs eDP connected DisplayPort-0 connected HDMI-A-0 disconnected
run_setup
expect_call \
    '--output DisplayPort-0 --auto --pos 0x0 --rotate normal --output eDP --primary --auto --right-of DisplayPort-0 --rotate normal' \
    'an eDP panel was not made primary beside the external monitor'

set_outputs DP-1 disconnected DP-2 disconnected eDP-1 connected
run_setup
expect_call \
    '--output eDP-1 --primary --auto --pos 0x0 --rotate normal' \
    'a lone eDP-1 panel did not get the laptop-only layout'

set_outputs LVDS-1 connected VGA-1 connected
run_setup
expect_call \
    '--output VGA-1 --auto --pos 0x0 --rotate normal --output LVDS-1 --primary --auto --right-of VGA-1 --rotate normal' \
    'an LVDS panel was not made primary'

set_outputs HDMI-1 connected DP-1 connected
run_setup
expect_call '' 'a machine without a laptop panel had its layout changed'

set_outputs eDP-1 connected HDMI-1 connected
run_setup I3_LAPTOP_OUTPUT=HDMI-1
expect_call \
    '--output eDP-1 --auto --pos 0x0 --rotate normal --output HDMI-1 --primary --auto --right-of eDP-1 --rotate normal' \
    'the configured I3_LAPTOP_OUTPUT did not win over the eDP fallback'

printf 'PASS: display setup makes the laptop panel primary under either driver naming\n'
