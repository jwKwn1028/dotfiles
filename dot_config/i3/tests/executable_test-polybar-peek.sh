#!/usr/bin/env bash

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
MOCK_STATE="$TEST_TMP/mock-state"

cleanup() {
  rm -rf "$TEST_TMP"
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$MOCK_STATE/runtime" "$MOCK_STATE/state-home" "$MOCK_STATE/home"

export POLYBAR_TEST_STATE_DIR="$MOCK_STATE"
export XDG_RUNTIME_DIR="$MOCK_STATE/runtime"
export XDG_STATE_HOME="$MOCK_STATE/state-home"
export HOME="$MOCK_STATE/home"
export I3_POLYBAR_PEEK_MS=240
export PATH="$MOCK_BIN:/usr/bin:/bin"

cat > "$MOCK_BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  search)
    printf '4242\n'
    ;;
  windowraise)
    printf 'raise\n' >> "$POLYBAR_TEST_STATE_DIR/x-events"
    ;;
esac
EOF

cat > "$MOCK_BIN/xwininfo" <<'EOF'
#!/usr/bin/env bash
if [ "$(cat "$POLYBAR_TEST_STATE_DIR/visibility")" = visible ]; then
  printf 'Map State: IsViewable\n'
else
  printf 'Map State: IsUnMapped\n'
fi
EOF

cat > "$MOCK_BIN/polybar-msg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$POLYBAR_TEST_STATE_DIR/polybar-events"
case "${2:-}" in
  show) printf 'visible\n' > "$POLYBAR_TEST_STATE_DIR/visibility" ;;
  hide) printf 'hidden\n' > "$POLYBAR_TEST_STATE_DIR/visibility" ;;
  *) exit 1 ;;
esac
EOF

cat > "$MOCK_BIN/i3-msg" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = -t ] && [ "${2:-}" = get_tree ]; then
  printf 'get_tree\n' >> "$POLYBAR_TEST_STATE_DIR/i3-events"
  printf '{"nodes":[]}\n'
elif [ "${1:-}" = -t ] && [ "${2:-}" = get_workspaces ]; then
  current="$(cat "$POLYBAR_TEST_STATE_DIR/current-workspace")"
  printf 'get_workspaces\n' >> "$POLYBAR_TEST_STATE_DIR/i3-events"
  printf '[{"num":%s,"name":"%s","focused":true}]\n' "$current" "$current"
else
  printf '%s\n' "$*" >> "$POLYBAR_TEST_STATE_DIR/i3-events"
  printf '[{"success":true}]\n'
fi
EOF

cat > "$MOCK_BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
printf 'eDP connected primary 1920x1080+0+0\n'
EOF

chmod +x "$MOCK_BIN/xdotool" "$MOCK_BIN/xwininfo" \
  "$MOCK_BIN/polybar-msg" "$MOCK_BIN/i3-msg" "$MOCK_BIN/xrandr"
printf '5\n' > "$MOCK_STATE/current-workspace"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_state() {
  local expected="$1"
  local actual
  actual=$(cat "$MOCK_STATE/visibility")
  [ "$actual" = "$expected" ] ||
    fail "expected Polybar state '$expected', got '$actual'"
}

wait_for_state() {
  local expected="$1"

  for _ in $(seq 1 80); do
    if [ "$(cat "$MOCK_STATE/visibility")" = "$expected" ]; then
      return 0
    fi
    sleep 0.025
  done
  fail "timed out waiting for Polybar state '$expected'"
}

wait_for_peek_exit() {
  for _ in $(seq 1 80); do
    if [ ! -e "$XDG_RUNTIME_DIR/i3-polybar-peek.owner" ] \
      && [ ! -e "$XDG_RUNTIME_DIR/i3-polybar-peek.hold" ]; then
      return 0
    fi
    sleep 0.025
  done
  fail "timed out waiting for the peek worker"
}

reset_case() {
  local initial="$1"

  wait_for_peek_exit
  printf '%s\n' "$initial" > "$MOCK_STATE/visibility"
  : > "$MOCK_STATE/polybar-events"
  : > "$MOCK_STATE/i3-events"
  : > "$MOCK_STATE/x-events"
}

# Hidden bars are shown after the workspace changes, then hidden by the worker.
reset_case hidden
"$ROOT/workspace-action.sh" switch 3
assert_state visible
grep -Fqx 'workspace number 3' "$MOCK_STATE/i3-events" ||
  fail "workspace switch was not sent to i3"
wait_for_state hidden
wait_for_peek_exit
grep -Fqx 'cmd show' "$MOCK_STATE/polybar-events" ||
  fail "hidden bar was not shown"
grep -Fqx 'cmd hide' "$MOCK_STATE/polybar-events" ||
  fail "peeked bar was not hidden"
if grep -Fqx 'get_tree' "$MOCK_STATE/i3-events"; then
  fail "transient peek unexpectedly ran resnap.sh"
fi

# A standalone-Super hold stays visible beyond the normal deadline and hides
# immediately when its matching listener releases it.
reset_case hidden
"$ROOT/polybar-peek.sh" --hold-start "$$"
assert_state visible
sleep 0.35
assert_state visible
"$ROOT/polybar-peek.sh" --hold-end "$$"
assert_state hidden
wait_for_peek_exit

# A different/stale listener is not allowed to end the current hold.
reset_case hidden
"$ROOT/polybar-peek.sh" --hold-start "$$"
"$ROOT/polybar-peek.sh" --hold-end "$(($$ + 1))"
sleep 0.05
assert_state visible
"$ROOT/polybar-peek.sh" --hold-end "$$"
assert_state hidden
wait_for_peek_exit

# Turning a hold into a chord starts the ordinary 250ms inactivity deadline.
reset_case hidden
"$ROOT/polybar-peek.sh" --hold-start "$$"
sleep 0.3
assert_state visible
"$ROOT/polybar-peek.sh" --hold-cancel "$$"
assert_state visible
wait_for_state hidden
wait_for_peek_exit

# A bar that was visible before the binding remains untouched.
reset_case visible
"$ROOT/workspace-action.sh" switch 4
sleep 0.3
assert_state visible
[ ! -s "$MOCK_STATE/polybar-events" ] ||
  fail "an already-visible bar received an IPC visibility command"

# A Super hold also leaves an already-visible bar untouched.
reset_case visible
"$ROOT/polybar-peek.sh" --hold-start "$$"
sleep 0.3
"$ROOT/polybar-peek.sh" --hold-end "$$"
assert_state visible
[ ! -s "$MOCK_STATE/polybar-events" ] ||
  fail "a Super hold changed an already-visible bar"

# A second workspace press renews the single inactivity deadline.
reset_case hidden
"$ROOT/workspace-action.sh" switch 1
sleep 0.14
"$ROOT/workspace-action.sh" switch 2
sleep 0.14
assert_state visible
wait_for_state hidden
wait_for_peek_exit
[ "$(grep -Fc 'cmd show' "$MOCK_STATE/polybar-events")" -eq 1 ] ||
  fail "repeated keypress launched more than one show"
[ "$(grep -Fc 'cmd hide' "$MOCK_STATE/polybar-events")" -eq 1 ] ||
  fail "repeated keypress launched more than one hide"

# Concurrent i3 exec processes also converge on one owned show/hide cycle.
reset_case hidden
for workspace in 1 2 3 4 5 6; do
  "$ROOT/workspace-action.sh" switch "$workspace" &
done
wait
assert_state visible
wait_for_state hidden
wait_for_peek_exit
[ "$(grep -Fc 'cmd show' "$MOCK_STATE/polybar-events")" -eq 1 ] ||
  fail "concurrent keypresses launched more than one show"
[ "$(grep -Fc 'cmd hide' "$MOCK_STATE/polybar-events")" -eq 1 ] ||
  fail "concurrent keypresses launched more than one hide"

# Previous/next workspace actions use the same transient feedback.
reset_case hidden
"$ROOT/workspace-action.sh" prev
grep -Fqx 'workspace prev' "$MOCK_STATE/i3-events" ||
  fail "previous-workspace action was not sent to i3"
wait_for_state hidden
wait_for_peek_exit

reset_case hidden
"$ROOT/workspace-action.sh" next
grep -Fqx 'workspace next' "$MOCK_STATE/i3-events" ||
  fail "next-workspace action was not sent to i3"
wait_for_state hidden
wait_for_peek_exit

# Relative actions select the exact numeric neighbor even when the target is
# absent from i3's current workspace list.
reset_case hidden
printf '5\n' > "$MOCK_STATE/current-workspace"
"$ROOT/workspace-action.sh" relative -1
grep -Fqx 'get_workspaces' "$MOCK_STATE/i3-events" ||
  fail "relative workspace action did not inspect the focused workspace"
grep -Fqx 'workspace number 4' "$MOCK_STATE/i3-events" ||
  fail "relative -1 did not select the exact numeric workspace on the left"
assert_state visible
wait_for_state hidden
wait_for_peek_exit

reset_case hidden
printf '5\n' > "$MOCK_STATE/current-workspace"
"$ROOT/workspace-action.sh" relative 1
grep -Fqx 'workspace number 6' "$MOCK_STATE/i3-events" ||
  fail "relative +1 did not select the exact numeric workspace on the right"
assert_state visible
wait_for_state hidden
wait_for_peek_exit

# Numeric navigation stops at the configured 1-10 boundaries. Re-selecting the
# current workspace would trigger workspace_auto_back_and_forth.
reset_case hidden
printf '1\n' > "$MOCK_STATE/current-workspace"
"$ROOT/workspace-action.sh" relative -1
if grep -Fq 'workspace number' "$MOCK_STATE/i3-events"; then
  fail "relative -1 moved past workspace 1"
fi
if [ -s "$MOCK_STATE/polybar-events" ]; then
  fail "relative -1 peeked Polybar at workspace 1"
fi

reset_case hidden
printf '10\n' > "$MOCK_STATE/current-workspace"
"$ROOT/workspace-action.sh" relative 1
if grep -Fq 'workspace number' "$MOCK_STATE/i3-events"; then
  fail "relative +1 moved past workspace 10"
fi
if [ -s "$MOCK_STATE/polybar-events" ]; then
  fail "relative +1 peeked Polybar at workspace 10"
fi

# Relative moves follow the focused window to the adjacent numbered workspace
# and wrap across the configured 1-10 boundary.
reset_case hidden
printf '5\n' > "$MOCK_STATE/current-workspace"
"$ROOT/workspace-action.sh" move-relative -1
grep -Fqx 'move container to workspace number 4; workspace number 4' \
  "$MOCK_STATE/i3-events" ||
  fail "move-relative -1 did not move to workspace 4"
wait_for_state hidden
wait_for_peek_exit

reset_case hidden
printf '5\n' > "$MOCK_STATE/current-workspace"
"$ROOT/workspace-action.sh" move-relative 1
grep -Fqx 'move container to workspace number 6; workspace number 6' \
  "$MOCK_STATE/i3-events" ||
  fail "move-relative +1 did not move to workspace 6"
wait_for_state hidden
wait_for_peek_exit

reset_case hidden
printf '1\n' > "$MOCK_STATE/current-workspace"
"$ROOT/workspace-action.sh" move-relative -1
grep -Fqx 'move container to workspace number 10; workspace number 10' \
  "$MOCK_STATE/i3-events" ||
  fail "move-relative -1 did not wrap workspace 1 to 10"
wait_for_state hidden
wait_for_peek_exit

reset_case hidden
printf '10\n' > "$MOCK_STATE/current-workspace"
"$ROOT/workspace-action.sh" move-relative 1
grep -Fqx 'move container to workspace number 1; workspace number 1' \
  "$MOCK_STATE/i3-events" ||
  fail "move-relative +1 did not wrap workspace 10 to 1"
wait_for_state hidden
wait_for_peek_exit

# The move path delegates to the validated move command and also peeks.
reset_case hidden
"$ROOT/workspace-action.sh" move 2
grep -Fqx 'move container to workspace number 2; workspace number 2' \
  "$MOCK_STATE/i3-events" ||
  fail "move action did not delegate to move-to-workspace.sh"
wait_for_state hidden
wait_for_peek_exit

# External-preferred workspaces remain valid move targets when xrandr reports
# only the laptop output.
reset_case hidden
"$ROOT/workspace-action.sh" move 7
grep -Fqx 'move container to workspace number 7; workspace number 7' \
  "$MOCK_STATE/i3-events" ||
  fail "move to workspace 7 was blocked without an external output"
wait_for_state hidden
wait_for_peek_exit

# An explicit toggle cancels ownership, so its hide is not repeated later.
reset_case hidden
"$ROOT/workspace-action.sh" switch 5
assert_state visible
"$ROOT/toggle-polybar-resnap.sh"
assert_state hidden
[ ! -e "$XDG_RUNTIME_DIR/i3-polybar-peek.owner" ] ||
  fail "explicit toggle did not cancel peek ownership"
sleep 0.35
[ "$(grep -Fc 'cmd hide' "$MOCK_STATE/polybar-events")" -eq 1 ] ||
  fail "peek worker hid the bar after the explicit toggle"

# Entering kill-workspace mode promotes a current peek to persistent visibility.
reset_case hidden
"$ROOT/workspace-action.sh" switch 6
assert_state visible
"$ROOT/show-polybar-or-kill-workspace.sh"
assert_state visible
[ ! -e "$XDG_RUNTIME_DIR/i3-polybar-peek.owner" ] ||
  fail "kill-workspace mode did not cancel peek ownership"
grep -Fqx 'get_tree' "$MOCK_STATE/i3-events" ||
  fail "promoting a peek to persistent visibility did not resnap"
sleep 0.35
assert_state visible

printf 'PASS: Polybar workspace peek behavior\n'
