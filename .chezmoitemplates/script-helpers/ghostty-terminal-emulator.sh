#!/bin/sh
set -eu

launcher=${HOME:-}/.local/bin/ghostty
# A system launcher must never run a home-directory executable as root.
if [ "$(/usr/bin/id -u)" = 0 ] || [ ! -x "$launcher" ]; then
    exec /usr/bin/xfce4-terminal.wrapper "$@"
fi

if [ "${1:-}" = -T ]; then
    if [ "$#" -lt 2 ]; then
        echo 'x-terminal-emulator: -T requires a title' >&2
        exit 2
    fi
    title=$2
    shift 2
    set -- "--title=$title" "$@"
fi
exec "$launcher" "$@"
