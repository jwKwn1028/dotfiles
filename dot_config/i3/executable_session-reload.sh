#!/bin/sh

set -u

failures=

record_failure() {
    if [ -n "$failures" ]; then
        failures="$failures, $1"
    else
        failures=$1
    fi
}

units_stamp=${XDG_RUNTIME_DIR:-/tmp}/i3-units-reloaded
units_changed=1
if [ -e "$units_stamp" ]; then
    units_changed=$(find "$HOME/.config/systemd/user" /etc/systemd/user /usr/lib/systemd/user \
        -newer "$units_stamp" -print -quit 2>/dev/null)
fi
if [ -n "$units_changed" ]; then
    touch "$units_stamp" 2>/dev/null
    if ! systemctl --user daemon-reload; then
        rm -f "$units_stamp"
        record_failure "systemd units"
    fi
fi

conf=$HOME/.config/dunst/dunstrc
if [ -r "$conf" ]; then
    started=$(systemctl --user show -P ActiveEnterTimestamp dunst.service 2>/dev/null || true)
    started_epoch=$(date -d "$started" +%s 2>/dev/null || echo 0)
    conf_epoch=$(stat -c %Y "$conf" 2>/dev/null || echo 0)
    if [ "$conf_epoch" -gt "$started_epoch" ]; then
        if ! systemctl --user try-restart dunst.service; then
            record_failure "dunst"
        fi
    fi
fi

if ! systemctl --user try-restart task-notify.timer; then
    record_failure "task timer"
fi

if pgrep -x picom >/dev/null 2>&1; then
    if ! pkill -USR1 -x picom; then
        record_failure "picom"
    fi
fi

display_setup=${I3_DISPLAY_SETUP:-$HOME/.config/i3/display-setup.sh}
if [ -e "${XDG_RUNTIME_DIR:-/tmp}/i3-reload-toast" ]; then
    I3_DISPLAY_SETUP_DELAY=${I3_DISPLAY_SETUP_DELAY:-0}
    export I3_DISPLAY_SETUP_DELAY
fi
display_succeeded=0
if [ -x "$display_setup" ]; then
    if [ -n "$failures" ]; then
        if I3_RELOAD_TOAST=1 \
            I3_DISPLAY_TOAST="i3 reload partial: $failures" \
            "$display_setup"; then
            display_succeeded=1
        else
            record_failure "display setup"
        fi
    elif I3_RELOAD_TOAST=1 "$display_setup"; then
        display_succeeded=1
    else
        record_failure "display setup"
    fi
else
    record_failure "display setup"
fi

if [ "$display_succeeded" -eq 0 ] && [ -n "$failures" ]; then
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u critical "i3 reload partial" "$failures" || true
    fi
fi
