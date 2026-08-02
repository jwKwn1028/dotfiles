#!/usr/bin/env bash
# Cursor bookkeeping for bar-nav.sh. The cursor is module visibility, so the
# assertions are on the IPC actions it emits. `open` is not exercised: it
# touches X11 through polybar_show_persistent.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"
trap 'rm -rf "$TEST_TMP"' EXIT

export XDG_RUNTIME_DIR="$TEST_TMP"
export PATH="$TEST_TMP/bin:$PATH"
mkdir -p "$TEST_TMP/bin"

IPC_LOG="$TEST_TMP/ipc"
STATE="$TEST_TMP/i3-polybar-nav.idx"
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
chmod +x "$TEST_TMP/bin/polybar-msg" "$TEST_TMP/bin/i3-msg" "$TEST_TMP/bin/pactl"

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
[ "$(cat "$STATE")" = 3 ] || fail "prev did not wrap past the first stop"
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
"$NAV" click >/dev/null 2>&1
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
for m in date pulseaudio battery powermenu; do
  logged "#$m.module_show" || fail "close did not restore $m"
  logged "#$m-sel.module_hide" || fail "close did not hide the $m twin"
done

printf 'PASS: bar-nav cursor\n'
