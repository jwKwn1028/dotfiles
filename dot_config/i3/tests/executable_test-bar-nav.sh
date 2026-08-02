#!/usr/bin/env bash
# Cursor bookkeeping for bar-nav.sh. The cursor is module visibility, so the
# assertions are on the IPC actions it emits. X11 is mocked far enough that
# polybar_show_persistent finds the bar already up and does nothing.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export XDG_RUNTIME_DIR="$TEST_TMP"
export PATH="$TEST_TMP/bin:$PATH"
mkdir -p "$TEST_TMP/bin"

IPC_LOG="$TEST_TMP/ipc"
STATE="$TEST_TMP/i3-polybar-nav.idx"
RESTORE="$TEST_TMP/i3-polybar-nav.restore-hidden"
PEEK_OWNER="$TEST_TMP/i3-polybar-peek.owner"
NAV="$ROOT/bar-nav.sh"

# Record IPC instead of talking to a bar, and make sure a stray action never
# reaches the real session.
cat > "$TEST_TMP/bin/polybar-msg" <<EOF
#!/bin/sh
printf '%s\n' "\$2" >> "$IPC_LOG"
EOF
cat > "$TEST_TMP/bin/i3-msg" <<EOF
#!/bin/sh
printf 'i3:%s\n' "\$1" >> "$IPC_LOG"
EOF
printf '#!/bin/sh\nprintf "pactl %%s\\n" "\$*" >> "%s"\n' "$IPC_LOG" \
  > "$TEST_TMP/bin/pactl"

# Enough of X11 for polybar_show_persistent to conclude the bar is already
# visible, so it takes no action of its own.
# shellcheck disable=SC2016  # $1 belongs to the mock, not to this script
printf '#!/bin/sh\n[ "$1" = search ] && printf "4242\\n"\nexit 0\n' \
  > "$TEST_TMP/bin/xdotool"
printf '#!/bin/sh\nprintf "Map State: IsViewable\\n"\n' > "$TEST_TMP/bin/xwininfo"

# bar-nav `eval`s these. Without stand-ins the "opens a window" case below
# launches the real settings window onto the live session and leaves it there,
# and a stop that reaches rofi would block the test on a real menu.
for cmd in xfce4-power-manager-settings nm-connection-editor blueman-manager \
  pavucontrol brightnessctl rofi i3lock i3-nagbar; do
  printf '#!/bin/sh\nprintf "%s\\n" >> "%s"\n' "$cmd" "$IPC_LOG" \
    > "$TEST_TMP/bin/$cmd"
done

chmod +x "$TEST_TMP"/bin/*

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  printf -- '--- ipc log ---\n' >&2
  cat "$IPC_LOG" >&2 2>/dev/null || true
  exit 1
}

reset_log() {
  : > "$IPC_LOG"
}

logged() {
  grep -Fqx "$1" "$IPC_LOG"
}

# Opening selects the first stop, and must not reset that stop on the way. It
# used to: resetting all six and then selecting the first sent hide+show and
# show+hide to the same pair back to back, polybar collapsed them, and the first
# stop stayed unhighlighted until the cursor moved off it and back.
rm -f "$STATE"
reset_log
"$NAV" open
[ "$(cat "$STATE")" = 0 ] || fail "open did not select the first stop"
logged '#date-sel.module_show' || fail "open did not show the first stop's twin"
logged '#date.module_show' && fail "open reset the stop it was about to select"
logged '#date-sel.module_hide' && fail "open hid the twin it was about to show"
logged '#powermenu.module_show' || fail "open did not reset the other stops"

# Leaving the mode restores the bar's previous visibility, so entering it is
# never a way to strand a hidden bar on screen. The mocked X11 reports the bar
# as already visible, so opening must not arm the restore.
[ -e "$RESTORE" ] && fail "open armed the restore with the bar already visible"

# A bar that is up only for a transient workspace peek was on its way out, so
# it counts as hidden even though X11 says it is viewable.
rm -f "$STATE"
: > "$PEEK_OWNER"
"$NAV" open
[ -e "$RESTORE" ] || fail "open treated a transient peek as a persistent bar"
rm -f "$PEEK_OWNER"
reset_log
"$NAV" close
[ -e "$RESTORE" ] && fail "close left the restore armed"
logged 'hide' || fail "close did not put the bar back to hidden"

# Selecting a module hides the plain one and shows its twin, so the pair is
# never on screen together and never both missing.
printf '0\n' > "$STATE"
reset_log
"$NAV" next
[ "$(cat "$STATE")" = 1 ] || fail "next did not advance the index"
logged '#date-sel.module_hide' || fail "leaving a stop did not hide its twin"
logged '#date.module_show' || fail "leaving a stop did not restore the module"
logged '#pulseaudio.module_hide' || fail "entering a stop did not hide the module"
logged '#pulseaudio-sel.module_show' || fail "entering a stop did not show its twin"

reset_log
"$NAV" prev
"$NAV" prev
[ "$(cat "$STATE")" = 5 ] || fail "prev did not wrap past the first stop"
"$NAV" next
[ "$(cat "$STATE")" = 0 ] || fail "next did not wrap past the last stop"

# A stale or corrupt index must not break the cursor.
printf 'x\n' > "$STATE"
"$NAV" next
[ "$(cat "$STATE")" = 1 ] || fail "a non-numeric index was not reset"
printf '99\n' > "$STATE"
"$NAV" next
[ "$(cat "$STATE")" = 1 ] || fail "an out-of-range index was not reset"

# An in-place toggle keeps the mode; only a stop that opens a window leaves it.
printf '1\n' > "$STATE"
reset_log
"$NAV" click
logged 'i3:mode "default"' && fail "mute toggle left the mode"
[ -e "$STATE" ] || fail "mute toggle closed the cursor"

printf '2\n' > "$STATE"
reset_log
"$NAV" click
logged 'xfce4-power-manager-settings' || fail "the stop's window was never opened"
logged 'i3:mode "default"' || fail "a stop that opens a window stayed in the mode"
[ -e "$STATE" ] && fail "a stop that opens a window left the cursor up"

# Buttons a module has no handler for do nothing at all.
printf '0\n' > "$STATE"
reset_log
"$NAV" click-right || fail "right-click on a module without one returned failure"
[ -s "$IPC_LOG" ] && fail "right-click on a module without one still acted"
"$NAV" down || fail "j on a module without a scroll handler returned failure"
"$NAV" up || fail "k on a module without a scroll handler returned failure"

# Closing restores every pair, not just the selected one.
printf '2\n' > "$STATE"
reset_log
"$NAV" close
[ -e "$STATE" ] && fail "close left the state file behind"
for m in date pulseaudio battery network bluetooth powermenu; do
  logged "#$m.module_show" || fail "close did not restore $m"
  logged "#$m-sel.module_hide" || fail "close did not hide the $m twin"
done

printf 'PASS: bar-nav cursor\n'
