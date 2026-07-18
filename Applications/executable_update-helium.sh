#!/usr/bin/env bash
#
# update-helium.sh — automatically update the Helium browser AppImage.
#
# Checks the latest release of imputnet/helium-linux on GitHub, and if it is
# newer than the locally installed AppImage, downloads it, swaps it in, and
# updates helium.desktop to point at the new version.
#
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="imputnet/helium-linux"
ARCH="x86_64"
# Desktop files to keep in sync (local copy + the one installed in the app menu).
DESKTOP_FILES=(
    "$APP_DIR/helium.desktop"
    "$HOME/.local/share/applications/helium.desktop"
)

log() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

# Re-assert Helium preferences that updates tend to reset. Helium updates
# occasionally re-pin the zen-mode top chrome (the URL panel), undoing the
# "hidden by default, reveal on hover / Ctrl+L" behavior. Skipped while Helium
# is running, since it rewrites Preferences on exit and would clobber the change.
enforce_helium_prefs() {
    local pref="$HOME/.config/net.imput.helium/Default/Preferences"
    [[ -f "$pref" ]] || return 0
    command -v python3 >/dev/null 2>&1 || { log "python3 not found; skipping Helium preference enforcement"; return 0; }
    if pgrep -f 'helium-.*\.AppImage|\.mount_[Hh]elium' >/dev/null 2>&1; then
        log "Helium is running; skipping preference enforcement (applies next launch)"
        return 0
    fi
    local result
    result="$(python3 - "$pref" <<'PY'
import json, sys
path = sys.argv[1]
try:
    prefs = json.load(open(path))
except (OSError, ValueError):
    print("error"); sys.exit(0)
browser = prefs.setdefault("helium", {}).setdefault("browser", {})
if browser.get("zen_mode_top_chrome_pinned") is False:
    print("ok"); sys.exit(0)
browser["zen_mode_top_chrome_pinned"] = False
json.dump(prefs, open(path, "w"), separators=(",", ":"))
print("fixed")
PY
)"
    case "$result" in
        fixed) log "Re-asserted Helium pref: zen_mode_top_chrome_pinned=false" ;;
        ok)    log "Helium pref already correct: zen_mode_top_chrome_pinned=false" ;;
        *)     log "warning: could not enforce Helium preferences" ;;
    esac
}

for cmd in curl grep; do
    command -v "$cmd" >/dev/null 2>&1 || { err "missing required command: $cmd"; exit 1; }
done

# --- Find the currently installed AppImage and its version -------------------
current_appimage="$(ls -1 "$APP_DIR"/helium-*-"$ARCH".AppImage 2>/dev/null | sort -V | tail -n1 || true)"
if [[ -n "$current_appimage" ]]; then
    current_version="$(basename "$current_appimage" | sed -E "s/^helium-(.*)-$ARCH\.AppImage$/\1/")"
else
    current_version="none"
fi
log "Installed version: $current_version"

# --- Query GitHub for the latest release tag --------------------------------
api_url="https://api.github.com/repos/$REPO/releases/latest"
auth=()
[[ -n "${GITHUB_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GITHUB_TOKEN")

api_response="$(curl -fsSL "${auth[@]}" "$api_url")"
latest_version="$(printf '%s' "$api_response" \
    | grep '"tag_name"' \
    | head -n1 \
    | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')"

if [[ -z "$latest_version" ]]; then
    err "could not determine latest version from GitHub API"
    exit 1
fi
log "Latest version:    $latest_version"

# --- Compare versions -------------------------------------------------------
if [[ "$current_version" == "$latest_version" ]]; then
    log "Already up to date. Nothing to do."
    exit 0
fi

# If the "newest" of the two equals the installed one, the installed is newer/equal.
if [[ "$current_version" != "none" ]]; then
    newest="$(printf '%s\n%s\n' "$current_version" "$latest_version" | sort -V | tail -n1)"
    if [[ "$newest" == "$current_version" ]]; then
        log "Installed version is newer than or equal to the latest release. Nothing to do."
        exit 0
    fi
fi

# --- Download the new AppImage ----------------------------------------------
new_name="helium-$latest_version-$ARCH.AppImage"
new_path="$APP_DIR/$new_name"
url="https://github.com/$REPO/releases/download/$latest_version/$new_name"
tmp_path="$new_path.part"

log "Downloading $new_name ..."
curl -fL --progress-bar "${auth[@]}" -o "$tmp_path" "$url"
chmod +x "$tmp_path"
mv -f "$tmp_path" "$new_path"
log "Saved to $new_path"

# --- Update helium.desktop files --------------------------------------------
# Match any previous version (handles files that were out of sync).
for desktop in "${DESKTOP_FILES[@]}"; do
    [[ -f "$desktop" ]] || continue
    sed -i \
        -e "s|helium-[^/]*-$ARCH\.AppImage|$new_name|g" \
        -e "s|^X-AppImage-Version=.*|X-AppImage-Version=$latest_version|" \
        "$desktop"
    log "Updated $desktop"
done
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi

# --- Remove the old AppImage ------------------------------------------------
if [[ -n "$current_appimage" && "$current_appimage" != "$new_path" ]]; then
    rm -f "$current_appimage"
    log "Removed old AppImage: $(basename "$current_appimage")"
fi

# --- Re-assert preferences the update may have reset ------------------------
enforce_helium_prefs

log "Helium updated: $current_version -> $latest_version"
