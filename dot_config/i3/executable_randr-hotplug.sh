#!/usr/bin/env bash
# Re-run display-setup.sh on monitor hotplug, keyed on the connected-output set
# rather than the raw i3 `output` event -- display-setup.sh drives xrandr itself.

set -u
DIR="$(dirname "$(readlink -f "$0")")"

DISPLAY_SETUP="${I3_DISPLAY_SETUP:-$DIR/display-setup.sh}"
# Coalesces one hotplug's event burst; display-setup.sh adds its own settle.
QUIET_SECONDS="${I3_RANDR_HOTPLUG_QUIET:-0.7}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
lid_files=(/proc/acpi/button/lid/*/state)
LID_STATE="${I3_LID_STATE:-${lid_files[0]}}"

command -v xrandr >/dev/null 2>&1 || exit 0
command -v i3-msg >/dev/null 2>&1 || exit 0
[ -x "$DISPLAY_SETUP" ] || exit 0

# Wait, not `flock -n`: exec_always pkills the old watcher, which must release it.
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
exec 200>"$RUNTIME_DIR/i3-randr-hotplug.lock"
flock -w 5 200 || exit 0

lid_closed() {
    local _label state=""
    [ -r "$LID_STATE" ] && read -r _label state <"$LID_STATE"
    [ "$state" = closed ]
}

connected_signature() {
    local outputs
    outputs="$(xrandr --query 2>/dev/null |
        awk '$2 == "connected" { print $1 }' |
        LC_ALL=C sort |
        tr '\n' ' ')"
    # 2+ outputs: xfsettingsd disables a closed lid's still-connected panel.
    case "$outputs" in *' '*' '*) lid_closed && outputs+="lid:closed" ;; esac
    printf '%s' "$outputs"
}

# Only the lid moved: the panel toggled, so skip the settle and toast.
lid_only_change() {
    [ "$1" != "$2" ] && [ "${1%lid:closed}" = "${2%lid:closed}" ]
}

change_toast() {
    local before_count after_count
    before_count="$(awk '{ print NF }' <<<"${1%lid:closed}")"
    after_count="$(awk '{ print NF }' <<<"${2%lid:closed}")"

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
    while IFS= read -r -t "${1:-$QUIET_SECONDS}" -u 3 _discard; do :; done
}

LAST_SIGNATURE="$(connected_signature)"

while true; do
    while IFS= read -r -u 3 _event; do
        if lid_only_change "$(connected_signature)" "$LAST_SIGNATURE"; then
            drain_events 0.15
        else
            drain_events
        fi

        # Looped: a monitor plugged in mid-run emits its events into the drain.
        while :; do
            signature="$(connected_signature)"
            [ "$signature" = "$LAST_SIGNATURE" ] && break
            setup_delay="${I3_DISPLAY_SETUP_DELAY-}"
            if lid_only_change "$signature" "$LAST_SIGNATURE"; then
                toast_text="" setup_delay=0
            else
                toast_text="$(change_toast "$LAST_SIGNATURE" "$signature")"
            fi
            LAST_SIGNATURE="$signature"

            I3_DISPLAY_SETUP_DELAY="$setup_delay" I3_DISPLAY_TOAST="$toast_text" \
                "$DISPLAY_SETUP" 3<&- 200>&-
            drain_events
        done
    done 3< <(i3-msg -t subscribe -m '["output"]' 200>&- 2>/dev/null)

    # exec_always respawns us on an i3 restart; this covers a transient socket drop.
    sleep 1
done
