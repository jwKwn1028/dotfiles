#!/bin/sh
# Start dunst 1.9 with the current internal-panel index.

set -eu

monitor_index() {
    preferred=${I3_LAPTOP_OUTPUT:-eDP}
    if command -v xrandr >/dev/null 2>&1; then
        monitors=$(xrandr --listmonitors 2>/dev/null || true)
    else
        monitors=
    fi

    printf '%s\n' "$monitors" | awk -v preferred="$preferred" '
        NR == 1 && $1 == "Monitors:" { next }
        NF >= 2 {
            idx = $1
            sub(/:$/, "", idx)
            if (idx !~ /^[0-9]+$/) next

            name = $NF
            flags = $2
            if (name == preferred) {
                print idx
                exact = 1
                exit
            }
            if (internal == "" && name ~ /^(eDP|LVDS)/) internal = idx
            if (primary == "" && flags ~ /\*/) primary = idx
            if (first == "") first = idx
        }
        END {
            if (!exact) {
                if (internal != "") print internal
                else if (primary != "") print primary
                else if (first != "") print first
                else print 0
            }
        }
    '
}

if [ "${1:-}" = --monitor-index ]; then
    monitor_index
    exit 0
fi

umask 077
if [ -n "${DUNST_RUNTIME_DIR:-}" ]; then
    runtime_dir=$DUNST_RUNTIME_DIR
elif [ -n "${XDG_RUNTIME_DIR:-}" ]; then
    runtime_dir=$XDG_RUNTIME_DIR/dunst
else
    printf 'dunst-start: XDG_RUNTIME_DIR or DUNST_RUNTIME_DIR is required\n' >&2
    exit 1
fi
mkdir -p "$runtime_dir"

index_file=$runtime_dir/monitor-index
index=$(monitor_index)
case $index in
    ''|*[!0-9]*) index=0 ;;
esac

if [ "${1:-}" = --sync ]; then
    current=
    if [ -r "$index_file" ]; then
        IFS= read -r current <"$index_file" || true
    fi
    if [ "$index" != "$current" ] && command -v systemctl >/dev/null 2>&1; then
        systemctl --user try-restart dunst.service || true
    fi
    exit 0
fi

source_conf=${DUNST_CONFIG_FILE:-$HOME/.config/dunst/dunstrc}
[ -r "$source_conf" ] || {
    printf 'dunst-start: cannot read %s\n' "$source_conf" >&2
    exit 1
}

runtime_conf=$runtime_dir/dunstrc
conf_tmp=$(mktemp "$runtime_dir/dunstrc.XXXXXX")
index_tmp=$(mktemp "$runtime_dir/monitor-index.XXXXXX")
trap 'rm -f -- "$conf_tmp" "$index_tmp"' EXIT HUP INT TERM

awk -v monitor="$index" '
    /^[[:space:]]*\[/ {
        in_global = ($0 ~ /^[[:space:]]*\[global\][[:space:]]*$/)
    }
    in_global && /^[[:space:]]*monitor[[:space:]]*=/ {
        sub(/=.*/, "= " monitor)
        replaced = 1
    }
    { print }
    END { if (!replaced) exit 2 }
' "$source_conf" >"$conf_tmp" || {
    printf 'dunst-start: no monitor setting in [global] of %s\n' "$source_conf" >&2
    exit 1
}

printf '%s\n' "$index" >"$index_tmp"
mv -f "$conf_tmp" "$runtime_conf"
mv -f "$index_tmp" "$index_file"
trap - EXIT HUP INT TERM

exec "${DUNST_BIN:-/usr/bin/dunst}" -conf "$runtime_conf" "$@"
