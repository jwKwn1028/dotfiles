#!/usr/bin/env bash
# Trigger bookkeeping for randr-hotplug.sh: which i3 `output` events deserve a
# display-setup.sh run. Assertions are on the run count per event sequence; X11
# is mocked to a connected-output list the test rewrites between steps, and
# events come from a FIFO the test holds open so their timing is known.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"

QUIET=0.15
# Past one drain window, so a step expecting no run really gave it the chance.
SETTLE=0.7

# Must preserve the exit status: `wait` on the killed daemon reports 143, which
# would otherwise become the test's own result.
cleanup() {
  local status=$?
  exec 4>&- 2>/dev/null || true
  if [ -n "${DAEMON_PID:-}" ]; then
    kill "$DAEMON_PID" 2>/dev/null || true
    wait "$DAEMON_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_TMP"
  exit "$status"
}
trap cleanup EXIT

export XDG_RUNTIME_DIR="$TEST_TMP"
export PATH="$TEST_TMP/bin:$PATH"
mkdir -p "$TEST_TMP/bin"

OUTPUTS="$TEST_TMP/outputs"
RUN_LOG="$TEST_TMP/runs"
TOAST_LOG="$TEST_TMP/toasts"
FIFO="$TEST_TMP/events"
: > "$RUN_LOG"
: > "$TOAST_LOG"
mkfifo "$FIFO"

HOTPLUG="$ROOT/randr-hotplug.sh"
[ -f "$HOTPLUG" ] || HOTPLUG="$ROOT/executable_randr-hotplug.sh"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# --- mocks ---------------------------------------------------------------
# xrandr --query, rendered from whatever output list the current step set.
printf '%s\n' '#!/bin/sh' \
  "while read -r name state; do printf '%s %s 1920x1080+0+0 (normal left inverted)\\n' \"\$name\" \"\$state\"; done < '$OUTPUTS'" \
  > "$TEST_TMP/bin/xrandr"

# i3-msg -t subscribe -m '["output"]': every event the test writes to the FIFO.
printf '%s\n' '#!/bin/sh' "exec cat '$FIFO'" > "$TEST_TMP/bin/i3-msg"

printf '%s\n' '#!/bin/sh' \
  "printf 'run\\n' >> '$RUN_LOG'" \
  "printf '%s\\n' \"\${I3_DISPLAY_TOAST:-}\" >> '$TOAST_LOG'" \
  > "$TEST_TMP/bin/display-setup-mock"

chmod +x "$TEST_TMP/bin/xrandr" "$TEST_TMP/bin/i3-msg" \
  "$TEST_TMP/bin/display-setup-mock"

# --- helpers -------------------------------------------------------------
set_outputs() {
  : > "$OUTPUTS"
  for name in "$@"; do
    printf '%s connected\n' "$name" >> "$OUTPUTS"
  done
}

emit_event() {
  printf '{"change":"unspecified"}\n' >&4
}

runs() {
  wc -l < "$RUN_LOG" | tr -d ' '
}

toasts() {
  wc -l < "$TOAST_LOG" | tr -d ' '
}

# --- run -----------------------------------------------------------------
set_outputs eDP

I3_DISPLAY_SETUP="$TEST_TMP/bin/display-setup-mock" \
  I3_RANDR_HOTPLUG_QUIET="$QUIET" \
  bash "$HOTPLUG" &
DAEMON_PID=$!

# Held open all test, so the daemon keeps one subscription instead of
# resubscribing on EOF.
exec 4>"$FIFO"
sleep "$SETTLE"

[ "$(runs)" = 0 ] || fail "daemon ran display-setup before any event arrived"
[ "$(toasts)" = 0 ] || fail "daemon announced a display change before any event arrived"

# A mode/position change -- what display-setup.sh itself emits.
emit_event
sleep "$SETTLE"
[ "$(runs)" = 0 ] || fail "an event with an unchanged output set ran display-setup"
[ "$(toasts)" = 0 ] || fail "an unchanged output set produced a toast"

# One hotplug: many events, one new output, one run.
set_outputs eDP DisplayPort-1
emit_event
emit_event
emit_event
sleep "$SETTLE"
[ "$(runs)" = 1 ] || fail "a hotplug burst produced $(runs) runs, want exactly 1"
[ "$(tail -n 1 "$TOAST_LOG")" = "Display connected" ] ||
  fail "a plug did not request the connected toast"

# The churn display-setup.sh causes must not re-trigger it.
emit_event
emit_event
sleep "$SETTLE"
[ "$(runs)" = 1 ] || fail "post-run event churn triggered display-setup again"
[ "$(toasts)" = 1 ] || fail "post-run event churn produced another toast"

# Unplug is a change in the same way.
set_outputs eDP
emit_event
sleep "$SETTLE"
[ "$(runs)" = 2 ] || fail "an unplug produced $(runs) runs, want 2"
[ "$(tail -n 1 "$TOAST_LOG")" = "Display disconnected" ] ||
  fail "an unplug did not request the disconnected toast"

# A set returning to a previous value is still a change from the one before.
set_outputs eDP DisplayPort-1
emit_event
sleep "$SETTLE"
[ "$(runs)" = 3 ] || fail "replugging the same output did not run display-setup"
[ "$(tail -n 1 "$TOAST_LOG")" = "Display connected" ] ||
  fail "a replug did not request the connected toast"

# A hotplug during the run emits into the drain that follows it, so nothing is
# left to wake the daemon. The next mock run stands in for that.
cat > "$TEST_TMP/bin/display-setup-mock" <<EOF
#!/bin/sh
printf 'run\n' >> '$RUN_LOG'
printf '%s\n' "\${I3_DISPLAY_TOAST:-}" >> '$TOAST_LOG'
if [ ! -e '$TEST_TMP/midrun-fired' ]; then
  : > '$TEST_TMP/midrun-fired'
  printf 'eDP connected\nDisplayPort-1 connected\nHDMI-1 connected\n' > '$OUTPUTS'
fi
EOF
chmod +x "$TEST_TMP/bin/display-setup-mock"

set_outputs eDP
emit_event
sleep "$SETTLE"
[ "$(runs)" = 5 ] ||
  fail "a hotplug during the run left $(runs) runs, want 5 (the mid-run output went unconfigured)"
[ "$(tail -n 2 "$TOAST_LOG" | head -n 1)" = "Display disconnected" ] ||
  fail "the first mid-run change did not request the disconnected toast"
[ "$(tail -n 1 "$TOAST_LOG")" = "Display connected" ] ||
  fail "the second mid-run change did not request the connected toast"

# Replacing one output with another in a single burst has no count direction.
set_outputs eDP HDMI-1 USB-C-1
emit_event
sleep "$SETTLE"
[ "$(runs)" = 6 ] || fail "a same-count output replacement did not run display-setup"
[ "$(tail -n 1 "$TOAST_LOG")" = "Display changed" ] ||
  fail "a same-count output replacement did not request the changed toast"

printf 'PASS: randr-hotplug triggers and toasts\n'
