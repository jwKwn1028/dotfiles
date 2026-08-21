#!/usr/bin/env bash
# Transient Polybar peek, and the workspace navigation that triggers it.
#
# Each failure message names what its case pins down. The mock keeps three
# pieces of state a real session has: `visibility` (what X maps), `belief`
# (polybar's own flag, drivable apart from visibility the way i3 does for a
# fullscreen dock), and `parent` (i3's grip -- reparented means i3 still holds
# the dock, root means polybar really withdrew it).

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

# `-tree` names the root on every window, so Root and Parent stay separate lines.
cat > "$MOCK_BIN/xwininfo" <<'EOF'
#!/usr/bin/env bash
if [ "$(cat "$POLYBAR_TEST_STATE_DIR/visibility")" = visible ]; then
  printf 'Map State: IsViewable\n'
else
  printf 'Map State: IsUnMapped\n'
fi
case " $* " in
  *" -tree "*)
    printf '  Root window id: 0x3c9 (the root window)\n'
    if [ "$(cat "$POLYBAR_TEST_STATE_DIR/parent")" = reparented ]; then
      printf '  Parent window id: 0x4002ba "[i3 con] container"\n'
    else
      printf '  Parent window id: 0x3c9 (the root window)\n'
    fi
    ;;
esac
EOF

# Stands in for the Xlib withdraw: i3 lets go of the dock it was holding.
cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'withdraw %s\n' "$*" >> "$POLYBAR_TEST_STATE_DIR/x-events"
printf 'root\n' > "$POLYBAR_TEST_STATE_DIR/parent"
printf 'hidden\n' > "$POLYBAR_TEST_STATE_DIR/visibility"
EOF

# A command matching the flag is a no-op, exactly as in polybar.
cat > "$MOCK_BIN/polybar-msg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$POLYBAR_TEST_STATE_DIR/polybar-events"
belief=$(cat "$POLYBAR_TEST_STATE_DIR/belief")
case "${2:-}" in
  show) [ "$belief" = visible ] && exit 0
        printf 'visible\n' | tee "$POLYBAR_TEST_STATE_DIR/belief" \
          > "$POLYBAR_TEST_STATE_DIR/visibility" ;;
  hide) [ "$belief" = hidden ] && exit 0
        printf 'hidden\n' | tee "$POLYBAR_TEST_STATE_DIR/belief" \
          > "$POLYBAR_TEST_STATE_DIR/visibility" ;;
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
  "$MOCK_BIN/polybar-msg" "$MOCK_BIN/i3-msg" "$MOCK_BIN/xrandr" \
  "$MOCK_BIN/python3"
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
  printf '%s\n' "$initial" > "$MOCK_STATE/belief"
  printf 'root\n' > "$MOCK_STATE/parent"
  : > "$MOCK_STATE/polybar-events"
  : > "$MOCK_STATE/i3-events"
  : > "$MOCK_STATE/x-events"
}

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

reset_case hidden
"$ROOT/polybar-peek.sh" --hold-start "$$"
assert_state visible
sleep 0.35
assert_state visible
"$ROOT/polybar-peek.sh" --hold-end "$$"
assert_state hidden
wait_for_peek_exit

reset_case hidden
"$ROOT/polybar-peek.sh" --hold-start "$$"
"$ROOT/polybar-peek.sh" --hold-end "$(($$ + 1))"
sleep 0.05
assert_state visible
"$ROOT/polybar-peek.sh" --hold-end "$$"
assert_state hidden
wait_for_peek_exit

reset_case hidden
"$ROOT/polybar-peek.sh" --hold-start "$$"
sleep 0.3
assert_state visible
"$ROOT/polybar-peek.sh" --hold-cancel "$$"
assert_state visible
wait_for_state hidden
wait_for_peek_exit

reset_case visible
"$ROOT/workspace-action.sh" switch 4
sleep 0.3
assert_state visible
[ ! -s "$MOCK_STATE/polybar-events" ] ||
  fail "an already-visible bar received an IPC visibility command"

reset_case visible
"$ROOT/polybar-peek.sh" --hold-start "$$"
sleep 0.3
"$ROOT/polybar-peek.sh" --hold-end "$$"
assert_state visible
[ ! -s "$MOCK_STATE/polybar-events" ] ||
  fail "a Super hold changed an already-visible bar"

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

reset_case hidden
"$ROOT/workspace-action.sh" move 2
grep -Fqx 'move container to workspace number 2; workspace number 2' \
  "$MOCK_STATE/i3-events" ||
  fail "move action did not delegate to move-to-workspace.sh"
wait_for_state hidden
wait_for_peek_exit

reset_case hidden
"$ROOT/workspace-action.sh" move 7
grep -Fqx 'move container to workspace number 7; workspace number 7' \
  "$MOCK_STATE/i3-events" ||
  fail "move to workspace 7 was blocked without an external output"
wait_for_state hidden
wait_for_peek_exit

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

grep -Fq \
  'bindsym Shift+k exec --no-startup-id ~/.config/i3/kill-all-windows-and-hide-polybar.sh' \
  "$ROOT/config" || fail "Shift+K is not bound to the kill-and-hide helper"
"$ROOT/kill-all-windows-and-hide-polybar.sh"
assert_state hidden
mapfile -t final_kill_events < <(tail -n 2 "$MOCK_STATE/i3-events")
[ "${final_kill_events[0]:-}" = '[all] kill; mode "default"' ] ||
  fail "Shift+K helper did not kill every window and leave kill-workspace mode"
[ "${final_kill_events[1]:-}" = 'get_tree' ] ||
  fail "Shift+K helper did not hide Polybar after the global kill"

# Hiding a bar i3 already unmapped for fullscreen: polybar clears its flag
# without unmapping, so the withdraw has to take the dock away now.
reset_case visible
printf 'reparented\n' > "$MOCK_STATE/parent"
"$ROOT/toggle-polybar-resnap.sh"
assert_state hidden
grep -q '^withdraw ' "$MOCK_STATE/x-events" ||
  fail "a dock i3 still held after the hide was not withdrawn"
[ "$(cat "$MOCK_STATE/parent")" = root ] ||
  fail "i3 still holds the dock after the withdraw"

# An ordinary hide leaves nothing reparented, so it must not reach the withdraw.
reset_case visible
"$ROOT/toggle-polybar-resnap.sh"
assert_state hidden
if grep -q '^withdraw ' "$MOCK_STATE/x-events"; then
  fail "an ordinary hide withdrew a dock i3 had already released"
fi

printf 'PASS: Polybar workspace peek behavior\n'
