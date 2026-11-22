#!/usr/bin/env bash

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export XDG_RUNTIME_DIR="$TEST_TMP"
export PATH="$TEST_TMP/bin:$PATH"
mkdir -p "$TEST_TMP/bin"

TOGGLE_LOG="$TEST_TMP/toggle"
RESTORE_HIDDEN="$TEST_TMP/i3-window-mode.restore-hidden"
PEEK_OWNER="$TEST_TMP/i3-polybar-peek.owner"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

resolve() {
  if [ -f "$ROOT/$1" ]; then
    printf '%s\n' "$ROOT/$1"
  else
    printf '%s\n' "$ROOT/executable_$1"
  fi
}

cp "$(resolve window-mode.sh)"     "$TEST_TMP/window-mode.sh"
cp "$(resolve _polybar-common.sh)" "$TEST_TMP/_polybar-common.sh"
cp "$(resolve _snap-common.sh)"    "$TEST_TMP/_snap-common.sh"
chmod +x "$TEST_TMP/window-mode.sh"

printf '%s\n' '#!/bin/sh' "printf 'toggle\\n' >> '$TOGGLE_LOG'" \
  > "$TEST_TMP/toggle-polybar-resnap.sh"
printf '#!/bin/sh\nexit 0\n' > "$TEST_TMP/resnap.sh"
chmod +x "$TEST_TMP/toggle-polybar-resnap.sh" "$TEST_TMP/resnap.sh"

printf '%s\n' '#!/bin/sh' 'printf "1111\n"' > "$TEST_TMP/bin/xdotool"
printf '%s\n' '#!/bin/sh' \
  "if [ \"\$(cat '$TEST_TMP/bar-visible')\" = 1 ]; then" \
  '  printf "Map State: IsViewable\n"' \
  'else' \
  '  printf "Map State: IsUnmapped\n"' \
  'fi' \
  'printf "Parent window id: 0x1 (the root window)\n"' \
  > "$TEST_TMP/bin/xwininfo"
printf '#!/bin/sh\nexit 0\n' > "$TEST_TMP/bin/polybar-msg"
chmod +x "$TEST_TMP/bin/xdotool" "$TEST_TMP/bin/xwininfo" \
  "$TEST_TMP/bin/polybar-msg"

wm() { "$TEST_TMP/window-mode.sh" "$@"; }

reset() {
  : > "$TOGGLE_LOG"
  rm -f "$RESTORE_HIDDEN" "$PEEK_OWNER"
  printf '%s' "$1" > "$TEST_TMP/bar-visible"
}

toggled() { [ -s "$TOGGLE_LOG" ]; }

reset 1
wm open
[ -e "$RESTORE_HIDDEN" ] && fail "open claimed a restore marker for a bar that was already up"

reset 0
wm open
[ -e "$RESTORE_HIDDEN" ] || fail "open did not record that the bar had been hidden"
toggled || fail "open did not raise a hidden bar"

reset 1
: > "$PEEK_OWNER"
wm open
[ -e "$RESTORE_HIDDEN" ] || fail "open treated a peek's bar as one the user had raised"

reset 1
: > "$RESTORE_HIDDEN"
wm close
toggled || fail "close did not restore bar visibility when the marker was set"
[ -e "$RESTORE_HIDDEN" ] && fail "close left its restore marker behind"

reset 1
wm close
toggled && fail "close hid a bar the user had raised themselves"

printf 'PASS: window-mode bar contract\n'
