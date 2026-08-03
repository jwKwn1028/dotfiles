#!/usr/bin/env bash
# Cursor bookkeeping for bar-nav.sh. The cursor is module visibility, so the
# assertions are on the IPC actions it emits. X11 is mocked far enough that
# polybar_show_persistent finds the bar already up and does nothing.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export XDG_RUNTIME_DIR="$TEST_TMP"
export XDG_STATE_HOME="$TEST_TMP/state"
export PATH="$TEST_TMP/bin:$PATH"
mkdir -p "$TEST_TMP/bin"

IPC_LOG="$TEST_TMP/ipc"
STATE="$TEST_TMP/i3-polybar-nav.idx"
RESTORE="$TEST_TMP/i3-polybar-nav.restore-hidden"
PEEK_OWNER="$TEST_TMP/i3-polybar-peek.owner"
MARKER="$TEST_TMP/i3-polybar-nav.marker"
NAV="$ROOT/bar-nav.sh"
if [ ! -f "$NAV" ]; then
  cp "$ROOT/executable_bar-nav.sh" "$TEST_TMP/bar-nav.sh"
  cp "$ROOT/_polybar-common.sh" "$TEST_TMP/_polybar-common.sh"
  cp "$ROOT/executable__snap-common.sh" "$TEST_TMP/_snap-common.sh"
  NAV="$TEST_TMP/bar-nav.sh"
fi

nav() {
  bash "$NAV" "$@"
}

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
# shellcheck disable=SC2016  # $1 and $* belong to the mock, not to this script
# Polybar's window is 1111, everything else is a 22x22 tray icon at 1500,4.
# shellcheck disable=SC2016  # $* belongs to the mock, not to this script
printf '%s\n' '#!/bin/sh' \
  "printf 'xdotool %s\\n' \"\$*\" >> '$IPC_LOG'" \
  'case "$1 $3" in' \
  '  "search ^[Pp]olybar$") printf "1111\n" ;;' \
  '  search*) printf "4242\n" ;;' \
  'esac' \
  'exit 0' > "$TEST_TMP/bin/xdotool"
# The block must span the bar (1920x28 at 0,0), not hug the 22x22 icon.
# shellcheck disable=SC2016  # $2 belongs to the mock, not to this script
printf '%s\n' '#!/bin/sh' \
  'if [ "$2" = 1111 ]; then' \
  '  printf "Absolute upper-left X:  0\nAbsolute upper-left Y:  0\nWidth: 1920\nHeight: 28\nMap State: IsViewable\n"' \
  'else' \
  '  printf "Absolute upper-left X:  1500\nAbsolute upper-left Y:  4\nWidth: 22\nHeight: 22\nMap State: IsViewable\n"' \
  'fi' > "$TEST_TMP/bin/xwininfo"
# The painter is a long-lived background process; record the launch instead.
# shellcheck disable=SC2016  # $* belongs to the mock, not to this script
printf '#!/bin/sh\nprintf "setsid %%s\\n" "$*" >> "%s"\n' "$IPC_LOG" \
  > "$TEST_TMP/bin/setsid"
printf '#!/bin/sh\nprintf "hide\\n" >> "%s"\n' "$IPC_LOG" \
  > "$TEST_TMP/toggle-polybar-resnap.sh"
printf '#!/bin/sh\nexit 0\n' > "$TEST_TMP/resnap.sh"

# bar-nav `eval`s these. Without stand-ins the "opens a window" case below
# launches the real settings window onto the live session and leaves it there,
# and a stop that reaches rofi would block the test on a real menu.
for cmd in xfce4-power-manager-settings pavucontrol brightnessctl rofi \
  i3lock i3-nagbar notify-send; do
  printf '#!/bin/sh\nprintf "%s\\n" >> "%s"\n' "$cmd" "$IPC_LOG" \
    > "$TEST_TMP/bin/$cmd"
done

chmod +x "$TEST_TMP"/bin/*
chmod +x "$TEST_TMP"/toggle-polybar-resnap.sh "$TEST_TMP"/resnap.sh

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
# used to: resetting every stop and then selecting the first sent hide+show and
# show+hide to the same pair back to back, polybar collapsed them, and the first
# stop stayed unhighlighted until the cursor moved off it and back.
rm -f "$STATE"
reset_log
nav open
[ "$(cat "$STATE")" = 0 ] || fail "open did not select the first stop"
logged '#date-sel.module_show' || fail "open did not show the first stop's twin"
logged '#date.module_show' && fail "open reset the stop it was about to select"
logged '#date-sel.module_hide' && fail "open hid the twin it was about to show"
logged '#powermenu.module_show' || fail "open did not reset the other stops"
grep -q 'bar-nav-marker.py' "$IPC_LOG" || fail "open did not start the painter"

# Leaving the mode restores the bar's previous visibility, so entering it is
# never a way to strand a hidden bar on screen. The mocked X11 reports the bar
# as already visible, so opening must not arm the restore.
[ -e "$RESTORE" ] && fail "open armed the restore with the bar already visible"

# A bar that is up only for a transient workspace peek was on its way out, so
# it counts as hidden even though X11 says it is viewable.
rm -f "$STATE"
: > "$PEEK_OWNER"
nav open
[ -e "$RESTORE" ] || fail "open treated a transient peek as a persistent bar"
rm -f "$PEEK_OWNER"
reset_log
nav close
[ -e "$RESTORE" ] && fail "close left the restore armed"
logged 'hide' || fail "close did not put the bar back to hidden"

# Selecting a module hides the plain one and shows its twin, so the pair is
# never on screen together and never both missing.
printf '0\n' > "$STATE"
reset_log
nav next
[ "$(cat "$STATE")" = 1 ] || fail "next did not advance the index"
logged '#date-sel.module_hide' || fail "leaving a stop did not hide its twin"
logged '#date.module_show' || fail "leaving a stop did not restore the module"
logged '#pulseaudio.module_hide' || fail "entering a stop did not hide the module"
logged '#pulseaudio-sel.module_show' || fail "entering a stop did not show its twin"

# A tray stop's block is drawn by bar-nav-marker.py, not by Polybar: no module
# may be swapped for it, or the tray re-lays out its embedded icons on every
# keypress. The block covers the icon and spans the bar, not the icon's height.
printf '2\n' > "$STATE"
reset_log
nav next
[ "$(cat "$STATE")" = 3 ] || fail "next did not reach the Wi-Fi stop"
logged 'xdotool search --class ^Nm-applet$' || \
  fail "the Wi-Fi stop did not look for nm-applet"
[ "$(cat "$MARKER")" = '1500 0 22 28' ] || \
  fail "the Wi-Fi stop aimed the block at $(cat "$MARKER")"
grep -qE '#(wifi|tray)' "$IPC_LOG" && fail "the Wi-Fi stop swapped a bar module"
grep -q 'xdotool mousemove' "$IPC_LOG" && \
  fail "selecting a tray stop moved the mouse"
reset_log
nav next
[ "$(cat "$STATE")" = 4 ] || fail "next did not reach the Bluetooth stop"
logged 'xdotool search --class ^Blueman-tray$' || \
  fail "the Bluetooth stop did not look for blueman-tray"
[ -s "$MARKER" ] || fail "the Bluetooth stop left no block"
grep -qE '#(wifi|bluetooth|tray)' "$IPC_LOG" && \
  fail "moving between tray stops swapped a bar module"

# Stepping off the tray takes the block with it.
reset_log
nav next
[ "$(cat "$STATE")" = 5 ] || fail "next did not leave the Bluetooth stop"
[ -s "$MARKER" ] && fail "leaving the tray left its block painted"

# So does leaving the mode, and it does so before the painter's own stop signal.
printf '2\n' > "$STATE"
nav next
[ -s "$MARKER" ] || fail "next did not reach a tray stop"
nav close
[ -s "$MARKER" ] && fail "close left the block painted"

reset_log
printf '1\n' > "$STATE"
nav prev
nav prev
[ "$(cat "$STATE")" = 5 ] || fail "prev did not wrap past the first stop"
nav next
[ "$(cat "$STATE")" = 0 ] || fail "next did not wrap past the last stop"

# A stale or corrupt index must not break the cursor.
printf 'x\n' > "$STATE"
nav next
[ "$(cat "$STATE")" = 1 ] || fail "a non-numeric index was not reset"
printf '99\n' > "$STATE"
nav next
[ "$(cat "$STATE")" = 1 ] || fail "an out-of-range index was not reset"

# An in-place toggle keeps the mode; only a stop that opens a window leaves it.
printf '1\n' > "$STATE"
reset_log
nav click
logged 'i3:mode "default"' && fail "mute toggle left the mode"
[ -e "$STATE" ] || fail "mute toggle closed the cursor"

printf '2\n' > "$STATE"
reset_log
nav click
logged 'xfce4-power-manager-settings' || fail "the stop's window was never opened"
logged 'i3:mode "default"' || fail "a stop that opens a window stayed in the mode"
[ -e "$STATE" ] && fail "a stop that opens a window left the cursor up"

# Polybar's click handlers cannot reach an icon it does not own, so both buttons
# on a tray stop are the mouse's own gesture: onto the icon, then a real press.
for stop in 3 4; do
  for button in 1 3; do
    [ "$button" = 1 ] && action=click || action=click-right
    printf '%s\n' "$stop" > "$STATE"
    reset_log
    nav "$action"
    logged 'xdotool mousemove --sync --window 4242 11 11' || \
      fail "tray stop $stop did not put the pointer on its icon for $action"
    logged "xdotool click $button" || \
      fail "tray stop $stop did not send button $button"
    logged 'i3:mode "default"' || \
      fail "$action on tray stop $stop left bar mode active"
    [ -e "$STATE" ] && fail "$action on tray stop $stop left the cursor up"
    [ -s "$MARKER" ] && fail "$action on tray stop $stop left its block painted"
  done
done

# Buttons a module has no handler for do nothing at all.
printf '0\n' > "$STATE"
reset_log
nav click-right || fail "right-click on a module without one returned failure"
[ -s "$IPC_LOG" ] && fail "right-click on a module without one still acted"
nav down || fail "j on a module without a scroll handler returned failure"
nav up || fail "k on a module without a scroll handler returned failure"

# Closing restores every pair, not just the selected one.
printf '2\n' > "$STATE"
reset_log
nav close
[ -e "$STATE" ] && fail "close left the state file behind"
for m in date pulseaudio battery powermenu; do
  logged "#$m.module_show" || fail "close did not restore $m"
  logged "#$m-sel.module_hide" || fail "close did not hide the $m twin"
done
for m in wifi bluetooth tray; do
  grep -q "#$m" "$IPC_LOG" && fail "close sent an IPC action for the $m stop"
done

printf 'PASS: bar-nav cursor\n'
