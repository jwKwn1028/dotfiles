#!/usr/bin/env bash

command -v feh > /dev/null 2>&1 || exit 0

# Both PNGs are unmanaged local files; restore them from backup.
feh --no-fehbg --bg-fill "$HOME/.wallpaper-laptop.png" "$HOME/.wallpaper-external.png"
