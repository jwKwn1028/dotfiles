#!/bin/sh
# Rebuild _adwaita-recolored.css and the bundled assets from the GTK3 installed.
# Run this after a libgtk-3-0 upgrade if widgets start looking like stock Adwaita
# again -- a new GTK ships new Adwaita rules this theme has not recolored yet.
#
# The native GTK is resolved explicitly: a bare /usr/lib/*/ glob sorts i386
# ahead of x86_64 on a multiarch box, rebuilding from the wrong library.

set -e
T="$(cd "$(dirname "$0")/.." && pwd)"
TRIPLET=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "$(uname -m)-linux-gnu")
LIB=$(ls "/usr/lib/$TRIPLET"/libgtk-3.so.0.* 2>/dev/null | sort -V | tail -1)
[ -n "$LIB" ] || LIB=$(ls /usr/lib/*/libgtk-3.so.0.* 2>/dev/null | sort -V | tail -1)
[ -n "$LIB" ] || { echo "libgtk-3.so not found" >&2; exit 1; }
echo "using $LIB"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
gresource extract "$LIB" /org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css > "$TMP/adw-dark.css"
python3 "$T/tools/recolor.py" "$TMP/adw-dark.css" "$T/gtk-3.0/_adwaita-recolored.css"

mkdir -p "$T/gtk-3.0/assets"
for r in $(gresource list "$LIB" | grep "^/org/gtk/libgtk/theme/Adwaita/assets/"); do
  gresource extract "$LIB" "$r" > "$T/gtk-3.0/assets/$(basename "$r")"
done
echo "done; restart Thunar with: systemctl --user restart thunar.service"
