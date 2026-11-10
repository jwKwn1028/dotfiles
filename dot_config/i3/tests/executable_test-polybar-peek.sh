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
export I3_SYSTEM_PYTHON="$MOCK_BIN/python3"
export I3_GROUP_HELPER="$MOCK_BIN/groups.py"
: > "$I3_GROUP_HELPER"

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

cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
cat > /dev/null
printf 'withdraw %s\n' "$*" >> "$POLYBAR_TEST_STATE_DIR/x-events"
printf 'root\n' > "$POLYBAR_TEST_STATE_DIR/parent"
printf 'hidden\n' > "$POLYBAR_TEST_STATE_DIR/visibility"
EOF

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
"$ROOT/polybar-peek.sh"
assert_state visible
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
"$ROOT/polybar-peek.sh"
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
"$ROOT/polybar-peek.sh"
sleep 0.14
"$ROOT/polybar-peek.sh"
sleep 0.14
assert_state visible
wait_for_state hidden
wait_for_peek_exit
[ "$(grep -Fc 'cmd show' "$MOCK_STATE/polybar-events")" -eq 1 ] ||
  fail "repeated keypress launched more than one show"
[ "$(grep -Fc 'cmd hide' "$MOCK_STATE/polybar-events")" -eq 1 ] ||
  fail "repeated keypress launched more than one hide"

reset_case hidden
for _ in 1 2 3 4 5 6; do
  "$ROOT/polybar-peek.sh" &
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
"$ROOT/polybar-peek.sh"
assert_state visible
"$ROOT/toggle-polybar-resnap.sh"
assert_state hidden
[ ! -e "$XDG_RUNTIME_DIR/i3-polybar-peek.owner" ] ||
  fail "explicit toggle did not cancel peek ownership"
sleep 0.35
[ "$(grep -Fc 'cmd hide' "$MOCK_STATE/polybar-events")" -eq 1 ] ||
  fail "peek worker hid the bar after the explicit toggle"

reset_case hidden
"$ROOT/polybar-peek.sh"
assert_state visible
"$ROOT/kill-workspace-mode.sh" open
assert_state visible
[ ! -e "$XDG_RUNTIME_DIR/i3-polybar-peek.owner" ] ||
  fail "kill-workspace mode did not cancel peek ownership"
grep -Fqx 'get_tree' "$MOCK_STATE/i3-events" ||
  fail "promoting a peek to persistent visibility did not resnap"
sleep 0.35
assert_state visible

[ -e "$XDG_RUNTIME_DIR/i3-kill-workspace.restore-hidden" ] ||
  fail "a peek promoted by kill-workspace mode was not marked for restore"
"$ROOT/kill-workspace-mode.sh" close
assert_state hidden
[ ! -e "$XDG_RUNTIME_DIR/i3-kill-workspace.restore-hidden" ] ||
  fail "aborting kill-workspace mode left its restore marker behind"

reset_case visible
"$ROOT/kill-workspace-mode.sh" open
assert_state visible
[ ! -e "$XDG_RUNTIME_DIR/i3-kill-workspace.restore-hidden" ] ||
  fail "kill-workspace mode marked an already-persistent bar for restore"
"$ROOT/kill-workspace-mode.sh" close
assert_state visible

reset_case hidden
"$ROOT/kill-workspace-mode.sh" open
assert_state visible
[ -e "$XDG_RUNTIME_DIR/i3-kill-workspace.restore-hidden" ] ||
  fail "kill-workspace mode did not mark a hidden bar for restore"
"$ROOT/kill-workspace-mode.sh" open
[ ! -e "$XDG_RUNTIME_DIR/i3-kill-workspace.restore-hidden" ] ||
  fail "a second open did not rewrite the marker from the live bar state"
"$ROOT/kill-workspace-mode.sh" close
assert_state visible

# shellcheck disable=SC2016
grep -Fqx \
  'bindsym $mod+x exec --no-startup-id ~/.config/i3/kill-workspace-mode.sh open' \
  "$ROOT/config" || fail "Super+X is not bound to the kill-workspace mode helper"
for exit_key in Return Escape; do
  grep -Fqx \
    "    bindsym $exit_key exec --no-startup-id ~/.config/i3/kill-workspace-mode.sh close, mode \"default\"" \
    "$ROOT/config" || fail "kill-workspace mode's $exit_key does not restore Polybar"
done
# shellcheck disable=SC2016
grep -Fq 'bindsym 1 exec --no-startup-id ~/.config/i3/workspace-action.sh kill 1' "$ROOT/config" ||
  fail "a kill-workspace number key no longer exits straight to default mode"

reset_case hidden

"$ROOT/kill-workspace-mode.sh" open
assert_state visible
grep -Fq \
  'bindsym Shift+k exec --no-startup-id ~/.config/i3/kill-group-windows.sh' \
  "$ROOT/config" || fail "Shift+K is not bound to the group-kill helper"
grep -Fq \
  'bindsym Shift+a exec --no-startup-id ~/.config/i3/kill-group-windows.sh all' \
  "$ROOT/config" || fail "Shift+A is not bound to the all-groups kill helper"
"$ROOT/kill-group-windows.sh"
assert_state hidden
[ ! -e "$XDG_RUNTIME_DIR/i3-kill-workspace.restore-hidden" ] ||
  fail "the group kill left kill-workspace mode's restore marker behind"
mapfile -t final_kill_events < <(tail -n 2 "$MOCK_STATE/i3-events")
[ "${final_kill_events[0]:-}" = 'mode "default"' ] ||
  fail "Shift+K helper did not leave kill-workspace mode"
[ "${final_kill_events[1]:-}" = 'get_tree' ] ||
  fail "Shift+K helper did not restore Polybar after the group kill"

reset_case visible
"$ROOT/kill-workspace-mode.sh" open
assert_state visible
"$ROOT/kill-group-windows.sh"
assert_state visible
grep -Fqx 'mode "default"' "$MOCK_STATE/i3-events" ||
  fail "the group kill did not run against an already-persistent bar"

reset_case visible
printf 'reparented\n' > "$MOCK_STATE/parent"
"$ROOT/toggle-polybar-resnap.sh"
assert_state hidden
grep -q '^withdraw ' "$MOCK_STATE/x-events" ||
  fail "a dock i3 still held after the hide was not withdrawn"
[ "$(cat "$MOCK_STATE/parent")" = root ] ||
  fail "i3 still holds the dock after the withdraw"

reset_case visible
"$ROOT/toggle-polybar-resnap.sh"
assert_state hidden
if grep -q '^withdraw ' "$MOCK_STATE/x-events"; then
  fail "an ordinary hide withdrew a dock i3 had already released"
fi

printf 'PASS: Polybar workspace peek behavior\n'
