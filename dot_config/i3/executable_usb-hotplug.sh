#!/usr/bin/env bash
# Toast USB attach and detach, naming the connector where it is knowable.
# `udevadm monitor --udev` is unprivileged, so this needs no udev rule.

set -u
DIR="$(dirname "$(readlink -f "$0")")"
# shellcheck source=_toast-common.sh
. "$DIR/_toast-common.sh"

SYSFS="${I3_USB_SYSFS_ROOT:-/sys}"
# One plug's burst: a hub arrives with all of its children.
QUIET_SECONDS="${I3_USB_HOTPLUG_QUIET:-0.7}"
# A Type-C partner and a USB enumeration this close together are one plug.
TYPEC_WINDOW="${I3_USB_TYPEC_WINDOW:-3}"
# full adds speed, wattage, and alternate modes; compact omits them.
DETAIL="${I3_USB_TOAST_DETAIL:-full}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
MONITOR="${I3_USB_MONITOR:-udevadm monitor --udev --property --subsystem-match=usb --subsystem-match=typec}"

# Keeps a value with its unit, and a wrap from starting on the dot.
NB=$'\u00a0'
SEP="$NB· "

declare -A REC=()           # the udev record being read
declare -A BUS_KIND=()      # bus number -> typec | usb-a | internal | unknown
declare -A KNOWN=()         # devpath -> cached fields, for the detach toast
declare -A ADDED=()         # devpath -> fields, this burst
declare -A REMOVED=()       # devpath -> fields, this burst
declare -A PARTNER_DESC=()  # typec port -> detail, for the detach toast
PARTNER_PORT=""
PARTNER_AT=0
PARTNER_ADDED=""
PARTNER_REMOVED=""
HAVE_PENDING=0

# --- topology -------------------------------------------------------------
# A Type-C connector gets its own single-port xHCI, high and super speed.
# Counting that is the only mapping: usbN-portM/connector needs an ACPI _PLD
# match this machine does not provide.
classify_buses() {
    local hub bus port total hotplug typec_ports=0
    local -a singles=() hotplugged=() typec=()

    for port in "$SYSFS"/class/typec/port[0-9]; do
        [ -d "$port" ] && typec_ports=$((typec_ports + 1))
    done

    for hub in "$SYSFS"/bus/usb/devices/usb*; do
        [ -d "$hub" ] || continue
        bus="${hub##*/usb}"
        total=0
        hotplug=0
        for port in "$hub"/*/"usb$bus-port"*; do
            [ -d "$port" ] || continue
            total=$((total + 1))
            [ "$(cat "$port/connect_type" 2>/dev/null)" = hotplug ] &&
                hotplug=$((hotplug + 1))
        done

        if [ "$hotplug" -eq 0 ]; then
            BUS_KIND[$bus]=internal
            continue
        fi
        BUS_KIND[$bus]=unknown
        hotplugged+=("$bus")
        [ "$total" -eq 1 ] && singles+=("$bus")
    done

    if [ -n "${I3_USB_TYPEC_BUSES:-}" ]; then
        read -r -a typec <<<"$I3_USB_TYPEC_BUSES"
    elif [ "$typec_ports" -gt 0 ] &&
        [ "${#singles[@]}" -eq "$((typec_ports * 2))" ]; then
        typec=("${singles[@]}")
    else
        # Unrecognized shape: stay unknown rather than mislabel half the ports.
        return 0
    fi

    for bus in ${hotplugged[@]+"${hotplugged[@]}"}; do
        BUS_KIND[$bus]=usb-a
    done
    for bus in ${typec[@]+"${typec[@]}"}; do
        BUS_KIND[$bus]=typec
    done
}

# Silences login and resume, and still lets a detach name what left.
seed_known() {
    local dev real devpath
    for dev in "$SYSFS"/bus/usb/devices/*-*; do
        [ -r "$dev/idVendor" ] || continue
        real="$(readlink -f "$dev" 2>/dev/null)" || continue
        devpath="${real#"$SYSFS"}"
        KNOWN[$devpath]="$(seed_fields "$dev")"
    done
}

# bDeviceClass is 00 on composite devices; the class lives on the interfaces.
seed_interfaces() {
    local iface out=""
    for iface in "$1"/*:*.*; do
        [ -r "$iface/bInterfaceClass" ] || continue
        out="$out:$(cat "$iface/bInterfaceClass" 2>/dev/null)"
        out="$out$(cat "$iface/bInterfaceSubClass" 2>/dev/null)"
        out="$out$(cat "$iface/bInterfaceProtocol" 2>/dev/null)"
    done
    [ -n "$out" ] || out=":$(cat "$1/bDeviceClass" 2>/dev/null)0000"
    printf '%s:' "$out"
}

seed_fields() {
    local dev="$1" bus conn kind name
    bus="$(cat "$dev/busnum" 2>/dev/null)"
    bus="${bus#"${bus%%[!0]*}"}"
    conn="${BUS_KIND[${bus:-0}]:-unknown}"
    kind="$(kind_label "$(seed_interfaces "$dev")")"
    name="$(join_name "$(cat "$dev/manufacturer" 2>/dev/null)" \
        "$(cat "$dev/product" 2>/dev/null)")"
    printf '%s|%s|%s|' "$conn" "$kind" "$name"
}

# --- labels ---------------------------------------------------------------
connector_label() {
    case "$1" in
        typec) printf 'USB-C' ;;
        usb-a) printf 'USB-A' ;;
        *) printf 'USB' ;;
    esac
}

# :CCSSPP: triples, most specific first: keyboard 030101, mouse 030102.
kind_label() {
    case "$1" in
        *:03??01*) printf 'keyboard' ;;
        *:03??02*) printf 'mouse' ;;
        *:08*) printf 'storage' ;;
        *:0e*) printf 'camera' ;;
        *:01*) printf 'audio' ;;
        *:03*) printf 'input device' ;;
        *:02*|*:0a*) printf 'network adapter' ;;
        *:07*) printf 'printer' ;;
        *:e0*) printf 'wireless adapter' ;;
        *:09*) printf 'hub' ;;
        *) printf 'device' ;;
    esac
}

# Below 480 the number is noise, not news.
speed_label() {
    case "$1" in
        20000) printf '20%sGbps' "$NB" ;;
        10000) printf '10%sGbps' "$NB" ;;
        5000) printf '5%sGbps' "$NB" ;;
        480) printf '480%sMbps' "$NB" ;;
        *) printf '' ;;
    esac
}

join_name() {
    local vendor="${1//_/ }" model="${2//_/ }"
    case "$model" in "$vendor "*) vendor="" ;; esac
    printf '%s' "${vendor:+$vendor }$model"
}

device_name() {
    join_name "${REC[ID_VENDOR]:-}" "${REC[ID_MODEL]:-}"
}

# --- Type-C detail --------------------------------------------------------
partner_live() {
    [ -n "$PARTNER_PORT" ] || return 1
    [ "$((EPOCHSECONDS - PARTNER_AT))" -le "$TYPEC_WINDOW" ]
}

# The alternate-mode and power-delivery objects land just after the partner.
typec_settle() {
    local partner="$1" want got mode _
    want="$(cat "$partner/number_of_alternate_modes" 2>/dev/null)"
    [ -n "$want" ] || return 0
    for _ in $(seq 1 10); do
        got=0
        for mode in "$partner"/*.[0-9]; do
            [ -d "$mode" ] && got=$((got + 1))
        done
        [ "$got" -ge "$want" ] && return 0
        sleep 0.1
    done
}

typec_watts() {
    local pd="$1" pdo volt cur watt best=0
    for pdo in "$pd"/source-capabilities/*:fixed_supply; do
        [ -d "$pdo" ] || continue
        volt="$(cat "$pdo/voltage" 2>/dev/null)"
        cur="$(cat "$pdo/maximum_current" 2>/dev/null)"
        volt="${volt%mV}"
        cur="${cur%mA}"
        [ -n "$volt" ] && [ -n "$cur" ] || continue
        watt=$((volt * cur / 1000000))
        [ "$watt" -gt "$best" ] && best="$watt"
    done
    [ "$best" -gt 0 ] && printf '%s%sW' "$best" "$NB"
}

typec_altmode() {
    local partner="$1" mode
    for mode in "$partner"/*.[0-9]; do
        [ -d "$mode" ] || continue
        [ "$(cat "$mode/active" 2>/dev/null)" = yes ] || continue
        case "$(cat "$mode/description" 2>/dev/null)" in
            DisplayPort*) printf 'DP' ;;
            Thunderbolt*) printf 'TBT' ;;
        esac
    done
}

typec_extras() {
    local port="$1"
    local partner="$SYSFS/class/typec/port$port-partner"
    local pd watts modes
    [ -d "$partner" ] || return 0
    [ "$DETAIL" = full ] || return 0

    typec_settle "$partner"
    pd="$(readlink -f "$partner/usb_power_delivery" 2>/dev/null)"
    [ -n "$pd" ] && [ -d "$pd" ] && watts="$(typec_watts "$pd")"
    modes="$(typec_altmode "$partner")"
    join_fields "${watts:-}" "${modes:-}"
}

# --- rendering ------------------------------------------------------------
join_fields() {
    local field out=""
    for field in "$@"; do
        [ -n "$field" ] || continue
        out="${out:+$out$SEP}$field"
    done
    printf '%s' "$out"
}

pick_primary() {
    local -n bucket="$1"
    local devpath best=""
    [ "${#bucket[@]}" -eq 0 ] && return 0
    while IFS= read -r devpath; do
        case "${bucket[$devpath]}" in
            *"|hub|"*)
                printf '%s' "${bucket[$devpath]}"
                return 0
                ;;
        esac
        [ -z "$best" ] && best="${bucket[$devpath]}"
    done < <(printf '%s\n' "${!bucket[@]}" | LC_ALL=C sort)
    printf '%s' "$best"
}

render_device() {
    local record="$1" verb="$2" others="$3"
    local conn kind name speed extras=""

    IFS='|' read -r conn kind name speed <<<"$record"
    if [ "$verb" = connected ]; then
        [ "$DETAIL" = full ] && extras="$speed"
        if [ "$conn" = typec ] && partner_live; then
            extras="$(join_fields "$extras" "${PARTNER_DESC[$PARTNER_PORT]:-}")"
        fi
    else
        extras="$name"
    fi
    [ "$others" -gt 0 ] &&
        extras="$(join_fields "$extras" "+$others${NB}devices")"

    join_fields "$(connector_label "$conn") $kind $verb" "$extras"
}

render_partner() {
    local port="$1" verb="$2" extras kind
    extras="${PARTNER_DESC[$port]:-}"
    [ "$verb" = connected ] || unset "PARTNER_DESC[$port]"

    case "$extras" in
        *DP*|*TBT*) kind=dock ;;
        *W*) kind=charger ;;
        *) kind=device ;;
    esac
    case "$extras" in *W*) ;; *) [ "$kind" = dock ] && kind=display ;; esac

    join_fields "USB-C $kind $verb" "$extras"
}

flush_burst() {
    local devpath text="" others=0

    # Once per burst; the device toast and a later detach both use it.
    if [ -n "$PARTNER_ADDED" ]; then
        PARTNER_DESC[$PARTNER_ADDED]="$(typec_extras "$PARTNER_ADDED")"
    fi

    # A device that left and returned inside one burst is a bounce, not news.
    for devpath in "${!ADDED[@]}"; do
        if [ -n "${REMOVED[$devpath]+set}" ]; then
            unset "ADDED[$devpath]" "REMOVED[$devpath]"
        fi
    done

    if [ "${#ADDED[@]}" -gt 0 ]; then
        others=$((${#ADDED[@]} - 1))
        text="$(render_device "$(pick_primary ADDED)" connected "$others")"
    elif [ "${#REMOVED[@]}" -gt 0 ]; then
        others=$((${#REMOVED[@]} - 1))
        text="$(render_device "$(pick_primary REMOVED)" disconnected "$others")"
    elif [ -n "$PARTNER_ADDED" ]; then
        text="$(render_partner "$PARTNER_ADDED" connected)"
    elif [ -n "$PARTNER_REMOVED" ]; then
        text="$(render_partner "$PARTNER_REMOVED" disconnected)"
    fi

    ADDED=()
    REMOVED=()
    PARTNER_ADDED=""
    PARTNER_REMOVED=""
    HAVE_PENDING=0

    show_toast "$text"
}

# --- event handling -------------------------------------------------------
handle_usb() {
    local action="$1" devpath="$2" bus conn kind speed fields

    case "$action" in
        add)
            # A re-enumeration of something already attached is not an arrival.
            [ -n "${KNOWN[$devpath]+set}" ] && return 0
            bus="${REC[BUSNUM]:-0}"
            bus="${bus#"${bus%%[!0]*}"}"
            conn="${BUS_KIND[${bus:-0}]:-unknown}"
            kind="$(kind_label "${REC[ID_USB_INTERFACES]:-}")"
            speed="$(speed_label "$(cat "$SYSFS$devpath/speed" 2>/dev/null)")"
            fields="$conn|$kind|$(device_name)|$speed"
            KNOWN[$devpath]="$fields"
            ADDED[$devpath]="$fields"
            ;;
        remove)
            fields="${KNOWN[$devpath]:-unknown|device||}"
            unset "KNOWN[$devpath]"
            REMOVED[$devpath]="$fields"
            ;;
        *) return 0 ;;
    esac
    HAVE_PENDING=1
}

handle_partner() {
    local action="$1" devpath="$2" port
    port="${devpath##*/port}"
    port="${port%%-partner}"

    case "$action" in
        add)
            PARTNER_PORT="$port"
            PARTNER_AT="$EPOCHSECONDS"
            PARTNER_ADDED="$port"
            ;;
        remove)
            PARTNER_REMOVED="$port"
            [ "$PARTNER_PORT" = "$port" ] && PARTNER_PORT=""
            ;;
        *) return 0 ;;
    esac
    HAVE_PENDING=1
}

dispatch_record() {
    local action="${REC[ACTION]:-}" devtype="${REC[DEVTYPE]:-}"
    local devpath="${REC[DEVPATH]:-}"

    if [ -n "$action" ] && [ -n "$devpath" ]; then
        case "$devtype" in
            usb_device) handle_usb "$action" "$devpath" ;;
            typec_partner) handle_partner "$action" "$devpath" ;;
        esac
    fi
    REC=()
}

# The banner and per-event header lines carry no KEY=VALUE, so they fall through.
collect() {
    case "$1" in
        '') dispatch_record ;;
        ACTION=*|DEVPATH=*|DEVTYPE=*|BUSNUM=*|ID_VENDOR=*|ID_MODEL=*|\
        ID_VENDOR_ID=*|ID_MODEL_ID=*|ID_USB_INTERFACES=*)
            REC[${1%%=*}]="${1#*=}"
            ;;
    esac
}

dump_topology() {
    local bus
    [ "${#BUS_KIND[@]}" -eq 0 ] && return 0
    for bus in $(printf '%s\n' "${!BUS_KIND[@]}" | sort -n); do
        printf 'usb%-3s %s\n' "$bus" "${BUS_KIND[$bus]}"
    done
}

# --- main -----------------------------------------------------------------
classify_buses

if [ "${1:-}" = --dump ]; then
    dump_topology
    exit 0
fi

command -v udevadm >/dev/null 2>&1 || exit 0

# Wait, not `flock -n`: exec_always pkills the old watcher, which must release it.
mkdir -p "$RUNTIME_DIR" 2>/dev/null || true
exec 200>"$RUNTIME_DIR/i3-usb-hotplug.lock"
flock -w 5 200 || exit 0

seed_known

# udevadm outlives its parent. A survivor would hold the
# inherited lock fd and silently block every later watcher.
stop_monitor() {
    [ -n "${MONITOR_PID:-}" ] && kill "$MONITOR_PID" 2>/dev/null
    return 0
}
trap stop_monitor EXIT
trap 'stop_monitor; exit 0' TERM INT HUP

while true; do
    # `exec` in the child so MONITOR_PID is the monitor itself, not a wrapper.
    exec 3< <(exec 200>&-; exec $MONITOR 2>/dev/null)
    MONITOR_PID=$!

    while IFS= read -r -u 3 line; do
        collect "$line"
        [ "$HAVE_PENDING" = 1 ] || continue

        # Read to the end of the burst, then announce it once.
        while IFS= read -r -t "$QUIET_SECONDS" -u 3 line; do
            collect "$line"
        done
        flush_burst
    done

    exec 3<&-
    stop_monitor
    wait "$MONITOR_PID" 2>/dev/null || true

    # exec_always respawns us on an i3 restart; this covers a transient failure.
    sleep 1
done
