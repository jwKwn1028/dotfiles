#!/usr/bin/env bash
# Keep XFCE's global shortcut daemon from claiming chords reserved by i3.
#
# XFCE binds Ctrl+Super+L to xflock4, the chord this profile uses for numeric
# workspace navigation. Only that override goes; the default Ctrl+Alt+L stays.
#
# xfsettingsd keeps the X11 passive grab after xfconf drops the property, so the
# daemon is replaced to rebuild its table before i3 reloads to claim the chord.
# On that reload the property is already absent, so this does not recurse.

set -u

command -v xfconf-query >/dev/null 2>&1 || exit 0

CHANNEL="xfce4-keyboard-shortcuts"
PROPERTY="/commands/custom/<Primary><Super>l"

if xfconf-query -c "$CHANNEL" -p "$PROPERTY" >/dev/null 2>&1; then
    xfconf-query -c "$CHANNEL" -p "$PROPERTY" -r >/dev/null 2>&1 || true
    xfconf-query -c "$CHANNEL" -p "$PROPERTY" >/dev/null 2>&1 && exit 0

    if command -v xfsettingsd >/dev/null 2>&1 &&
       pgrep -x xfsettingsd >/dev/null 2>&1; then
        xfsettingsd --replace --daemon >/dev/null 2>&1 || true
        sleep 0.2
    fi

    i3-msg reload >/dev/null 2>&1 || true
fi
