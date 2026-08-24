#!/usr/bin/env bash
# Bar visibility contract for window-mode.sh (Super+R): leave the bar as you
# found it. open() writes or clears a restore marker, close() acts on it, so the
# assertions are on that marker and on whether the toggle script ran. X11 is
# mocked to one Polybar window whose mapped state the test flips.

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

# Source state carries chezmoi's executable_ prefix; an applied tree does not.
resolve() {
  if [ -f "$ROOT/$1" ]; then
    printf '%s\n' "$ROOT/$1"
  else
    printf '%s\n' "$ROOT/executable_$1"
  fi
}

# Always copied: $DIR must be a dir where the sibling scripts open() and
# close() shell out to can be mocked.
cp "$(resolve window-mode.sh)"     "$TEST_TMP/window-mode.sh"
cp "$(resolve _polybar-common.sh)" "$TEST_TMP/_polybar-common.sh"
cp "$(resolve _snap-common.sh)"    "$TEST_TMP/_snap-common.sh"
chmod +x "$TEST_TMP/window-mode.sh"

printf '%s\n' '#!/bin/sh' "printf 'toggle\\n' >> '$TOGGLE_LOG'" \
  > "$TEST_TMP/toggle-polybar-resnap.sh"
printf '#!/bin/sh\nexit 0\n' > "$TEST_TMP/resnap.sh"
chmod +x "$TEST_TMP/toggle-polybar-resnap.sh" "$TEST_TMP/resnap.sh"

# --- mocks ---------------------------------------------------------------
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

# --- helpers -------------------------------------------------------------
wm() { "$TEST_TMP/window-mode.sh" "$@"; }

reset() {
  : > "$TOGGLE_LOG"
  rm -f "$RESTORE_HIDDEN" "$PEEK_OWNER"
  printf '%s' "$1" > "$TEST_TMP/bar-visible"   # 1 = bar up, 0 = hidden
}

toggled() { [ -s "$TOGGLE_LOG" ]; }

# --- open() decides what exit owes ---------------------------------------
# Bar already up: exit leaves it up, so no marker.
reset 1
wm open
[ -e "$RESTORE_HIDDEN" ] && fail "open claimed a restore marker for a bar that was already up"

# Bar hidden: exit owes a hide, and open raises it first.
reset 0
wm open
[ -e "$RESTORE_HIDDEN" ] || fail "open did not record that the bar had been hidden"
toggled || fail "open did not raise a hidden bar"

# A peek's bar counts as hidden, or exiting would strand it on screen.
reset 1
: > "$PEEK_OWNER"
wm open
[ -e "$RESTORE_HIDDEN" ] || fail "open treated a peek's bar as one the user had raised"

# --- close() settles it --------------------------------------------------
# Marker set: hide it again and drop the marker.
reset 1
: > "$RESTORE_HIDDEN"
wm close
toggled || fail "close did not restore bar visibility when the marker was set"
[ -e "$RESTORE_HIDDEN" ] && fail "close left its restore marker behind"

# No marker: the bar was already the user's, so leave it.
reset 1
wm close
toggled && fail "close hid a bar the user had raised themselves"

printf 'PASS: window-mode bar contract\n'
