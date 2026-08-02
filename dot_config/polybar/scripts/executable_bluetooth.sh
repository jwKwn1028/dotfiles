#!/usr/bin/env bash
# Bluetooth state as one Nerd Font glyph. Polybar has no internal bluetooth
# module, and this replaces blueman's tray icon.

set -u

# rfkill first: a soft-blocked adapter reports "Powered: no" just like one that
# is merely switched off.
if rfkill list bluetooth 2>/dev/null | grep -q 'Soft blocked: yes'; then
  printf '\U000f00b2\n'   # nf-md-bluetooth_off
  exit 0
fi

if ! bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then
  printf '\U000f00b2\n'
  exit 0
fi

# `devices Connected` prints nothing rather than failing when none are up.
if [ -n "$(bluetoothctl devices Connected 2>/dev/null)" ]; then
  printf '\U000f00b1\n'   # nf-md-bluetooth_connect
else
  printf '\U000f00af\n'   # nf-md-bluetooth
fi
