#!/usr/bin/env bash
# Bluetooth state for the polybar module, as one Nerd Font glyph.
# Polybar has no internal bluetooth module, so this stands in for the
# blueman-applet tray icon, which only the tray-owning bar can show.

set -u

# rfkill first: a soft-blocked adapter answers "Powered: no" the same way one
# that is merely switched off does, and the blocked case is the one worth
# showing differently.
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
