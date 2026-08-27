#!/usr/bin/env bash
# Re-run display-setup.sh on monitor hotplug. Source is i3's `output` event:
# Debian's xrandr has no `--listen` and srandrd is not packaged for Mint 22.3.
# Trigger is the connected-output set, not the raw event -- display-setup.sh
# drives xrandr, so acting on events directly would loop.

set -u
DIR="$(dirname "$(readlink -f "$0")")"

DISPLAY_SETUP="${I3_DISPLAY_SETUP:-$DIR/display-setup.sh}"
# Coalesces one hotplug's event burst; display-setup.sh adds its own settle.
QUIET_SECONDS="${I3_RANDR_HOTPLUG_QUIET:-0.7}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"

command -v xrandr >/dev/null 2>&1 || exit 0
command -v i3-msg >/dev/null 2>&1 || exit 0
[ -x "$DISPLAY_SETUP" ] || exit 0

# Wait, not `flock -n`: exec_always pkills the old watcher, which must release it.
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
exec 200>"$RUNTIME_DIR/i3-randr-hotplug.lock"
flock -w 5 200 || exit 0

# `connected` covers a plugged-in-but-unconfigured monitor, the state that needs it.
connected_signature() {
    xrandr --query 2>/dev/null |
        awk '$2 == "connected" { print $1 }' |
        LC_ALL=C sort |
        tr '\n' ' '
}

change_toast() {
    local before_count after_count
    before_count="$(awk '{ print NF }' <<<"$1")"
    after_count="$(awk '{ print NF }' <<<"$2")"

    if [ "$after_count" -gt "$before_count" ]; then
        printf '%s\n' "Display connected"
    elif [ "$after_count" -lt "$before_count" ]; then
        printf '%s\n' "Display disconnected"
    else
        # A disconnect and connect can collapse into one debounced event burst.
        printf '%s\n' "Display changed"
    fi
}

drain_events() {
    local _discard
    while IFS= read -r -t "$QUIET_SECONDS" -u 3 _discard; do :; done
}

LAST_SIGNATURE="$(connected_signature)"

while true; do
    while IFS= read -r -u 3 _event; do
        drain_events

        # Looped, not checked once: a monitor plugged in during the run emits
        # its events into the drain.
        while :; do
            signature="$(connected_signature)"
            [ "$signature" = "$LAST_SIGNATURE" ] && break
            toast_text="$(change_toast "$LAST_SIGNATURE" "$signature")"
            LAST_SIGNATURE="$signature"

            I3_DISPLAY_TOAST="$toast_text" "$DISPLAY_SETUP"
            drain_events
        done
    done 3< <(i3-msg -t subscribe -m '["output"]' 2>/dev/null)

    # exec_always respawns us on an i3 restart; this covers a transient socket drop.
    sleep 1
done
