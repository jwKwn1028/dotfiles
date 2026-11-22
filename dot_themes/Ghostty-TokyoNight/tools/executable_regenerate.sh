#!/bin/sh
# Rebuild theme CSS and assets from native GTK 3, avoiding i386 on multiarch.

set -e
T="$(cd "$(dirname "$0")/.." && pwd)"
TRIPLET=$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo "$(uname -m)-linux-gnu")
LIB=$(find "/usr/lib/$TRIPLET" -maxdepth 1 -name 'libgtk-3.so.0.*' -print 2>/dev/null | sort -V | tail -1)
[ -n "$LIB" ] || LIB=$(find /usr/lib -mindepth 2 -maxdepth 2 -name 'libgtk-3.so.0.*' -print 2>/dev/null | sort -V | tail -1)
[ -n "$LIB" ] || { echo "libgtk-3.so not found" >&2; exit 1; }
echo "using $LIB"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
gresource extract "$LIB" /org/gtk/libgtk/theme/Adwaita/gtk-contained-dark.css > "$TMP/adw-dark.css"
/usr/bin/python3 "$T/tools/recolor.py" "$TMP/adw-dark.css" "$T/gtk-3.0/_adwaita-recolored.css"

mkdir -p "$T/gtk-3.0/assets"
for r in $(gresource list "$LIB" | grep "^/org/gtk/libgtk/theme/Adwaita/assets/"); do
  gresource extract "$LIB" "$r" > "$T/gtk-3.0/assets/$(basename "$r")"
done
# Decode inline GdkPixdata resources to PNG for CSS file URLs.
/usr/bin/python3 "$T/tools/export-pixbufs.py" "$T/gtk-3.0/assets"
echo "done; reopen GTK 3 applications to load the regenerated theme"
