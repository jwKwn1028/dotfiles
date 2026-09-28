#!/usr/bin/env bash
# Which udev records deserve a toast and what it says. udev is a FIFO the test
# holds open, sysfs a fixture tree, rofi a log of the strings it was handed.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"

QUIET=0.15
# Past one drain window, so a step expecting no toast really gave it the chance.
SETTLE=0.8

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

# Fields are joined with a no-break space; expectations use the same character.
NB=$'\u00a0'

SYS="$TEST_TMP/sys"
TOAST_LOG="$TEST_TMP/toasts"
ARGS_LOG="$TEST_TMP/rofi-args"
FIFO="$TEST_TMP/events"
: > "$TOAST_LOG"
: > "$ARGS_LOG"
mkfifo "$FIFO"
mkdir -p "$SYS/bus/usb/devices" "$SYS/class/typec"

WATCHER="$ROOT/usb-hotplug.sh"
[ -f "$WATCHER" ] || WATCHER="$ROOT/executable_usb-hotplug.sh"
I3_CONFIG="$ROOT/config"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

# --- mocks ---------------------------------------------------------------
# show_toast runs `rofi -e <text> -theme reload-toast`.
printf '%s\n' '#!/bin/sh' \
  "printf '%s\\n' \"\$2\" >> '$TOAST_LOG'" \
  "printf '%s\\n' \"\$*\" >> '$ARGS_LOG'" \
  > "$TEST_TMP/bin/rofi"
chmod +x "$TEST_TMP/bin/rofi"

# --- sysfs fixture -------------------------------------------------------
mk_hub() {
  mkdir -p "$SYS/devices/pci/usb$1/$1-0:1.0"
  ln -sfn "../../../devices/pci/usb$1" "$SYS/bus/usb/devices/usb$1"
}

mk_port() { # bus port connect_type
  local dir="$SYS/devices/pci/usb$1/$1-0:1.0/usb$1-port$2"
  mkdir -p "$dir"
  printf '%s\n' "$3" > "$dir/connect_type"
}

mk_typec_port() { # port
  mkdir -p "$SYS/class/typec/port$1"
}

mk_device() { # bus name rootport speed manufacturer product class
  local dir="$SYS/devices/pci/usb$1/$2"
  mkdir -p "$dir"
  printf '%s\n' "$3" > "$dir/devpath"
  printf '%s\n' "$4" > "$dir/speed"
  printf '%s\n' "$1" > "$dir/busnum"
  printf '%s\n' "${5:-}" > "$dir/manufacturer"
  printf '%s\n' "${6:-}" > "$dir/product"
  printf '%s\n' "${7:-00}" > "$dir/bDeviceClass"
  printf '1234\n' > "$dir/idVendor"
  ln -sfn "../../../devices/pci/usb$1/$2" "$SYS/bus/usb/devices/$2"
}

mk_interface() { # bus name number class subclass protocol
  local dir="$SYS/devices/pci/usb$1/$2/$2:1.$3"
  mkdir -p "$dir"
  printf '%s\n' "$4" > "$dir/bInterfaceClass"
  printf '%s\n' "$5" > "$dir/bInterfaceSubClass"
  printf '%s\n' "$6" > "$dir/bInterfaceProtocol"
}

devpath_of() { # bus name
  printf '/devices/pci/usb%s/%s' "$1" "$2"
}

mk_partner() { # port alt_mode watts
  local dir="$SYS/class/typec/port$1-partner" pd
  mkdir -p "$dir"
  if [ -n "${2:-}" ]; then
    mkdir -p "$dir/port$1-partner.0"
    printf 'yes\n' > "$dir/port$1-partner.0/active"
    printf '%s\n' "$2" > "$dir/port$1-partner.0/description"
    printf '1\n' > "$dir/number_of_alternate_modes"
  fi
  if [ -n "${3:-}" ]; then
    pd="$SYS/class/usb_power_delivery/pd$1"
    mkdir -p "$pd/source-capabilities/4:fixed_supply"
    printf '20000mV\n' > "$pd/source-capabilities/4:fixed_supply/voltage"
    printf '%smA\n' "$3" > "$pd/source-capabilities/4:fixed_supply/maximum_current"
    ln -sfn "../../usb_power_delivery/pd$1" "$dir/usb_power_delivery"
  fi
}

# Two USB-A ports on one controller, one port each on four Type-C root hubs.
mk_hub 3; mk_port 3 1 hotplug; mk_port 3 2 hotplug
mk_hub 4; mk_port 4 1 hotplug; mk_port 4 2 hotplug
mk_hub 5; mk_port 5 1 hotplug
mk_hub 6; mk_port 6 1 hotplug
mk_hub 7; mk_port 7 1 hotplug
mk_hub 8; mk_port 8 1 hotplug
mk_hub 1; mk_port 1 1 hardwired
mk_typec_port 0
mk_typec_port 1

# Already attached when the watcher starts. Its class lives on the interfaces,
# as it does on every composite device.
mk_device 3 3-2 2 12 Keychron 'Keychron Receiver' 00
mk_interface 3 3-2 0 03 01 01

export I3_USB_SYSFS_ROOT="$SYS"

# --- events --------------------------------------------------------------
emit_usb() { # action devpath busnum interfaces vendor model
  {
    printf 'UDEV  [1.0] %-8s %s (usb)\n' "$1" "$2"
    printf 'ACTION=%s\nDEVPATH=%s\nDEVTYPE=usb_device\nSUBSYSTEM=usb\n' "$1" "$2"
    printf 'BUSNUM=%03d\n' "$3"
    [ -n "${4:-}" ] && printf 'ID_USB_INTERFACES=%s\n' "$4"
    [ -n "${5:-}" ] && printf 'ID_VENDOR=%s\n' "$5"
    [ -n "${6:-}" ] && printf 'ID_MODEL=%s\n' "$6"
    printf '\n'
  } >&4
}

emit_interface() { # noise that must never reach a toast
  {
    printf 'ACTION=add\nDEVPATH=%s:1.0\nDEVTYPE=usb_interface\nSUBSYSTEM=usb\n' "$1"
    printf '\n'
  } >&4
}

emit_partner() { # action port
  local base="/devices/platform/USBC000:00/typec/port$2"
  {
    printf 'ACTION=%s\nDEVPATH=%s/port%s-partner\n' "$1" "$base" "$2"
    printf 'DEVTYPE=typec_partner\nSUBSYSTEM=typec\n\n'
  } >&4
}

toasts() { wc -l < "$TOAST_LOG" | tr -d ' '; }
last_toast() { tail -n 1 "$TOAST_LOG"; }

# --- topology ------------------------------------------------------------
TOPOLOGY="$(I3_USB_SYSFS_ROOT="$SYS" bash "$WATCHER" --dump)"
[ "$(printf '%s\n' "$TOPOLOGY" | awk '$1 == "usb3" { print $2 }')" = usb-a ] ||
  fail "a two-port hotplug controller was not classified USB-A"
[ "$(printf '%s\n' "$TOPOLOGY" | awk '$1 == "usb5" { print $2 }')" = typec ] ||
  fail "a single-port root hub paired with a Type-C connector was not classified typec"
[ "$(printf '%s\n' "$TOPOLOGY" | awk '$1 == "usb1" { print $2 }')" = internal ] ||
  fail "a hardwired-only root hub was not classified internal"

# One connector too few for the single-port hubs: refuse to guess.
mv "$SYS/class/typec/port1" "$SYS/class/typec/.port1"
[ "$(I3_USB_SYSFS_ROOT="$SYS" bash "$WATCHER" --dump |
  awk '$1 == "usb5" { print $2 }')" = unknown ] ||
  fail "a topology that does not match the Type-C count still claimed a connector"
mv "$SYS/class/typec/.port1" "$SYS/class/typec/port1"

# --- run -----------------------------------------------------------------
I3_USB_MONITOR="cat $FIFO" \
  I3_USB_HOTPLUG_QUIET="$QUIET" \
  I3_USB_TYPEC_WINDOW=1 \
  I3_TOAST_SECONDS=0.02 \
  I3_TOAST_WRAP=999 \
  bash "$WATCHER" &
DAEMON_PID=$!

# Held open all test, so the daemon keeps one monitor instead of respawning.
exec 4>"$FIFO"
sleep "$SETTLE"

[ "$(toasts)" = 0 ] || fail "the watcher toasted before any event arrived"

# Login and resume re-enumerate what is already attached; that is not an arrival.
emit_usb add "$(devpath_of 3 3-2)" 3 ':030101:' Keychron Keychron_Receiver
sleep "$SETTLE"
[ "$(toasts)" = 0 ] || fail "a re-enumeration of an attached device produced a toast"

# A device attached before the watcher started still detaches by its real kind.
rm -rf "$SYS/devices/pci/usb3/3-2" "$SYS/bus/usb/devices/3-2"
emit_usb remove "$(devpath_of 3 3-2)" 3
sleep "$SETTLE"
[ "$(last_toast)" = "USB-A keyboard disconnected${NB}· Keychron Receiver" ] ||
  fail "a pre-attached device detached as: $(last_toast)"

# A USB-A plug: the interface records that follow it are not separate arrivals.
mk_device 3 3-1 1 480 Generic 'Flash Drive' 00
emit_usb add "$(devpath_of 3 3-1)" 3 ':080650:' Generic Flash_Drive
emit_interface "$(devpath_of 3 3-1)"
sleep "$SETTLE"
[ "$(toasts)" = 2 ] || fail "a USB-A plug produced $(toasts) toasts, want 2"
[ "$(last_toast)" = "USB-A storage connected${NB}· 480${NB}Mbps" ] ||
  fail "USB-A plug said: $(last_toast)"

# Detach describes what left from the cache; its sysfs is already gone.
rm -rf "$SYS/devices/pci/usb3/3-1" "$SYS/bus/usb/devices/3-1"
emit_usb remove "$(devpath_of 3 3-1)" 3
sleep "$SETTLE"
[ "$(toasts)" = 3 ] || fail "a USB-A unplug produced $(toasts) toasts, want 3"
[ "$(last_toast)" = "USB-A storage disconnected${NB}· Generic Flash Drive" ] ||
  fail "USB-A unplug said: $(last_toast)"

# A Type-C dock: one partner, one device, one toast carrying both.
mk_partner 1 DisplayPort 3000
mk_device 6 6-1 1 10000 Samsung 'Portable SSD' 00
emit_partner add 1
emit_usb add "$(devpath_of 6 6-1)" 6 ':080650:' Samsung Portable_SSD
sleep "$SETTLE"
[ "$(toasts)" = 4 ] || fail "a Type-C plug produced $(toasts) toasts, want 4"
[ "$(last_toast)" = "USB-C storage connected${NB}· 10${NB}Gbps${NB}· 60${NB}W${NB}· DP" ] ||
  fail "Type-C plug said: $(last_toast)"

# Detaching the device names it from the cache.
rm -rf "$SYS/devices/pci/usb6/6-1" "$SYS/bus/usb/devices/6-1"
emit_usb remove "$(devpath_of 6 6-1)" 6
sleep "$SETTLE"
[ "$(last_toast)" = "USB-C storage disconnected${NB}· Samsung Portable SSD" ] ||
  fail "Type-C unplug said: $(last_toast)"

# The partner leaving is its own notice, described from the cached detail.
rm -rf "$SYS/class/typec/port1-partner"
emit_partner remove 1
sleep "$SETTLE"
[ "$(last_toast)" = "USB-C dock disconnected${NB}· 60${NB}W${NB}· DP" ] ||
  fail "Type-C partner unplug said: $(last_toast)"

# A charger announces itself with no USB device behind it at all.
mk_partner 0 '' 3000
emit_partner add 0
sleep "$SETTLE"
[ "$(last_toast)" = "USB-C charger connected${NB}· 60${NB}W" ] ||
  fail "charger-only partner said: $(last_toast)"

# With no partner attached a Type-C device carries no partner detail.
rm -rf "$SYS/class/typec/port0-partner"
emit_partner remove 0
sleep "$SETTLE"
BEFORE="$(toasts)"
mk_device 5 5-1 1 5000 Logitech 'Webcam' 00
emit_usb add "$(devpath_of 5 5-1)" 5 ':0e0100:' Logitech Webcam
sleep "$SETTLE"
[ "$(toasts)" = "$((BEFORE + 1))" ] || fail "an uncorrelated Type-C plug produced no toast"
[ "$(last_toast)" = "USB-C camera connected${NB}· 5${NB}Gbps" ] ||
  fail "uncorrelated Type-C plug said: $(last_toast)"

# A device that enumerates long after its partner is not part of that plug.
mk_partner 1 '' 3000
emit_partner add 1
sleep 2.2
mk_device 7 7-1 1 10000 Generic 'Late Disk' 00
emit_usb add "$(devpath_of 7 7-1)" 7 ':080650:' Generic Late_Disk
sleep "$SETTLE"
[ "$(last_toast)" = "USB-C storage connected${NB}· 10${NB}Gbps" ] ||
  fail "a plug past the correlation window carried partner detail: $(last_toast)"

# A hub and its children are one arrival.
mk_device 3 3-3 1 480 Generic 'USB Hub' 09
mk_device 3 3-3.1 1 480 Generic 'Mouse' 00
mk_device 3 3-3.2 1 480 Generic 'Keyboard' 00
mk_device 3 3-3.3 1 480 Generic 'Audio' 00
BEFORE="$(toasts)"
emit_usb add "$(devpath_of 3 3-3)" 3 ':090000:' Generic USB_Hub
emit_usb add "$(devpath_of 3 3-3.1)" 3 ':030102:' Generic Mouse
emit_usb add "$(devpath_of 3 3-3.2)" 3 ':030101:' Generic Keyboard
emit_usb add "$(devpath_of 3 3-3.3)" 3 ':010100:' Generic Audio
sleep "$SETTLE"
[ "$(toasts)" = "$((BEFORE + 1))" ] ||
  fail "a hub and three children produced $(( $(toasts) - BEFORE )) toasts, want 1"
[ "$(last_toast)" = "USB-A hub connected${NB}· 480${NB}Mbps${NB}· +3${NB}devices" ] ||
  fail "hub burst said: $(last_toast)"

# A detach and reattach inside one burst is a bounce, not news.
BEFORE="$(toasts)"
emit_usb remove "$(devpath_of 3 3-3.1)" 3
emit_usb add "$(devpath_of 3 3-3.1)" 3 ':030102:' Generic Mouse
sleep "$SETTLE"
[ "$(toasts)" = "$BEFORE" ] || fail "a bounce inside one burst produced a toast"

# --- restart handover ----------------------------------------------------
# Its monitor inherits the lock fd; a survivor silently blocks the next watcher.
kill "$DAEMON_PID"
wait "$DAEMON_PID" 2>/dev/null || true
DAEMON_PID=""
sleep 0.5

flock -n "$TEST_TMP/i3-usb-hotplug.lock" true ||
  fail "the killed watcher's monitor still holds the lock, so a restart cannot take over"
pgrep -f "cat $FIFO" >/dev/null &&
  fail "the killed watcher left its monitor running"

I3_USB_MONITOR="cat $FIFO" \
  I3_USB_HOTPLUG_QUIET="$QUIET" \
  I3_USB_TYPEC_WINDOW=1 \
  I3_TOAST_SECONDS=0.02 \
  I3_TOAST_WRAP=999 \
  bash "$WATCHER" &
DAEMON_PID=$!
sleep "$SETTLE"

BEFORE="$(toasts)"
mk_device 3 3-4 1 480 Generic 'Second Disk' 00
emit_usb add "$(devpath_of 3 3-4)" 3 ':080650:' Generic Second_Disk
sleep "$SETTLE"
[ "$(toasts)" = "$((BEFORE + 1))" ] ||
  fail "a watcher started after the old one was killed never toasted"

# --- toast wrapping ------------------------------------------------------
# rofi 1.7.5 under-measures what it wraps itself past two lines, so lines are
# made explicit first. The watcher above runs unwrapped, so its toasts are one line.
wrapped() { # width text
  ( I3_TOAST_WRAP="$1"; . "$ROOT/_toast-common.sh"; wrap_toast "$2" )
}

check_wrap() { # width text want_lines
  local out line count=0
  out="$(wrapped "$1" "$2")"
  while IFS= read -r line || [ -n "$line" ]; do
    count=$((count + 1))
    [ "${#line}" -le "$1" ] ||
      fail "a wrapped line is ${#line} chars, over $1: $line"
    case "$line" in
      "·"*) fail "a wrap started a line with the separator: $line" ;;
    esac
  done <<<"$out"
  [ "$count" = "$3" ] || fail "wrapping gave $count lines, want $3: $2"
}

check_wrap 27 "i3 reloaded" 1
check_wrap 27 "USB-C storage connected${NB}· 10${NB}Gbps${NB}· 60${NB}W${NB}· DP" 2
check_wrap 27 "USB-A keyboard disconnected${NB}· Keychron Receiver${NB}· 480${NB}Mbps${NB}· +3${NB}devices" 4
# A token with no space in it still has to be broken, or rofi wraps it again.
check_wrap 27 "USB-A storage connected${NB}· ExtremelyLongProductNameWithoutSpaces" 3

[ "$(wrapped 27 "i3 reloaded")" = "i3 reloaded" ] ||
  fail "wrapping altered a message that already fits"

# The default has to match the theme, or the box is mis-sized again.
[ "$( . "$ROOT/_toast-common.sh"; printf '%s' "$TOAST_WRAP" )" = 27 ] ||
  fail "the default wrap width no longer matches the 320px theme"

# --- presentation --------------------------------------------------------
# Notices go to the laptop, not to whichever monitor holds the mouse.
grep -q -- '-m primary' "$ARGS_LOG" ||
  fail "the toast was not pinned to the primary output"

# An ASCII space before a unit would let the 320px toast wrap mid-value.
grep -qE ' (Gbps|Mbps|W)([^A-Za-z]|$)' "$TOAST_LOG" &&
  fail "a unit is separated by a breakable space, so a toast can wrap mid-value"

# --- wiring --------------------------------------------------------------
LAUNCHER="$(grep -F 'usb-hotplug.sh' "$I3_CONFIG")" ||
  fail "config does not start usb-hotplug.sh"
PATTERN="$(printf '%s\n' "$LAUNCHER" | sed -n 's/.*pkill -f "\([^"]*\)".*/\1/p')"
[ -n "$PATTERN" ] || fail "the watcher's exec_always line has no pkill pattern"
printf '%s\n' "$LAUNCHER" | grep -qE "$PATTERN" &&
  fail "the watcher's pkill pattern also kills its own launcher"
printf 'bash /example/.config/i3/usb-hotplug.sh\n' | grep -qE "$PATTERN" ||
  fail "the watcher's pkill pattern does not match the running watcher"

printf 'PASS: usb-hotplug connector, detail, coalescing, and detach behavior\n'
