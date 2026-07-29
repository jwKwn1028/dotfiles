#!/usr/bin/env bash
# Keep XFCE's global shortcut daemon from claiming chords reserved by i3.

set -u

command -v xfconf-query >/dev/null 2>&1 || exit 0

CHANNEL="xfce4-keyboard-shortcuts"
PROPERTY="/commands/custom/<Primary><Super>l"

# XFCE assigns Ctrl+Super+L to xflock4 as a custom shortcut. This i3 profile
# uses the same chord for numeric workspace navigation; remove only that custom
# override and leave XFCE's default Ctrl+Alt+L lock binding untouched.
if xfconf-query -c "$CHANNEL" -p "$PROPERTY" >/dev/null 2>&1; then
    xfconf-query -c "$CHANNEL" -p "$PROPERTY" -r >/dev/null 2>&1 || true
    xfconf-query -c "$CHANNEL" -p "$PROPERTY" >/dev/null 2>&1 && exit 0

    # xfsettingsd keeps the old X11 passive grab after xfconf removes the
    # property. Replace the daemon so it rebuilds its shortcut table without
    # this chord before asking i3 to acquire it.
    if command -v xfsettingsd >/dev/null 2>&1 &&
       pgrep -x xfsettingsd >/dev/null 2>&1; then
        xfsettingsd --replace --daemon >/dev/null 2>&1 || true
        sleep 0.2
    fi

    # i3 could not own the passive key grab while XFCE held it. Reload once so
    # i3 acquires the newly released chord. On the reload the property is
    # already absent, so this script does not reload recursively.
    i3-msg reload >/dev/null 2>&1 || true
fi
