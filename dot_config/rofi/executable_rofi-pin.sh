#!/usr/bin/env bash
# Pin apps to the top of rofi's drun list.
#
# rofi orders drun by launch count in ~/.cache/rofi3.druncache
# ("<count> <desktop-id>", highest first), so pinning writes counts far above
# anything organic. Only the empty-query list is ordered; typing re-ranks by fzf.
#
# Two rofi 1.7 behaviours constrain the numbers below:
#   - Launching a pin increments its count, so pins must be spaced or they
#     reorder each other. STEP is the launches needed to pass one pin.
#   - Every write subtracts the lowest count from all entries, so the lowest pin
#     would normalise to 0 and unpin. FLOOR is an inert entry matching no real
#     app that holds the minimum, evicted once history fills max-history-size.
#
#   ./rofi-pin.sh                            # apply the PINS list below
#   ./rofi-pin.sh foo.desktop bar.desktop    # pin these instead (first is top)
#
# Desktop files stored beside this script are installed into the user's
# applications directory so rofi can resolve their desktop IDs. Real history is
# kept below the pins, dropping any entry just pinned.

set -euo pipefail

PINS=(
  app.zen_browser.zen.desktop    # Zen Browser
  micro.desktop                  # micro
  com.mitchellh.ghostty.desktop  # Ghostty
  dev.zed.Zed.desktop            # Zed
  helium.desktop                 # Helium
  org.kde.okular.desktop         # Okular
  spotify.desktop                # Spotify
  mintupdate.desktop             # Update Manager
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
