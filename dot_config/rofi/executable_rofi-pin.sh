#!/usr/bin/env bash
# Pin apps to the top of rofi's drun list.
#
# rofi orders drun by launch count in ~/.cache/rofi3.druncache ("<count> <id>",
# highest first), so pinning writes counts far above anything organic; typing
# re-ranks by fzf. Launching a pin increments its count, so STEP is the launches
# needed to pass one pin; every write subtracts the lowest count from all
# entries, so FLOOR is an inert entry holding the minimum. Desktop files beside
# this script are installed so rofi can resolve their IDs.
#
#   ./rofi-pin.sh                            # apply the PINS list below
#   ./rofi-pin.sh foo.desktop bar.desktop    # pin these instead (first is top)

set -euo pipefail

PINS=(
  app.zen_browser.zen.desktop
  micro.desktop
  com.mitchellh.ghostty.desktop
  dev.zed.Zed.desktop
  helium.desktop
  org.kde.okular.desktop
  spotify.desktop
  mintupdate.desktop
)

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/rofi3.druncache"
BASE=1000000
STEP=1000
FLOOR=zz-rofi-pin-floor.desktop

[ $# -gt 0 ] && PINS=("$@")

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
APPLICATIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

for app in "${PINS[@]}"; do
  source="$SCRIPT_DIR/$app"
  if [ -f "$source" ]; then
    install -D -m 0644 "$source" "$APPLICATIONS_DIR/$app"
  fi
done

tmp=$(mktemp)
n=$BASE
for app in "${PINS[@]}"; do
  printf '%d %s\n' "$n" "$app"
  n=$((n - STEP))
done > "$tmp"

if [ -f "$CACHE" ]; then
  awk 'NR==FNR { pin[$0]=1; next }
       { name = $0; sub(/^[0-9]+ /, "", name); if (!(name in pin)) print }' \
      <(printf '%s\n' "${PINS[@]}" "$FLOOR") "$CACHE" >> "$tmp"
fi
printf '0 %s\n' "$FLOOR" >> "$tmp"

mv "$tmp" "$CACHE"
printf 'pinned %d app(s) -> %s\n' "${#PINS[@]}" "$CACHE"
