#!/usr/bin/env bash

command -v feh > /dev/null 2>&1 || exit 0

feh --no-fehbg --bg-fill "$HOME/.wallpaper-laptop.png" "$HOME/.wallpaper-external.png"
