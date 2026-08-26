#!/usr/bin/env bash
# Run the fast i3/Polybar checks from either chezmoi source state or the applied
# ~/.config tree. Source-state executable_ names are mapped into a temporary
# applied-shaped tree so every test exercises the files being edited.

set -euo pipefail

TESTS_DIR="$(dirname "$(readlink -f "$0")")"
I3_ROOT="$(dirname "$TESTS_DIR")"
POLYBAR_ROOT="$(dirname "$I3_ROOT")/polybar"
PACKAGE_MANIFEST="$(dirname "$(dirname "$I3_ROOT")")/.chezmoidata/packages.toml"
[ -r "$PACKAGE_MANIFEST" ] || PACKAGE_MANIFEST=""
WORK_ROOT="$(mktemp -d)"
export PYTHONDONTWRITEBYTECODE=1

cleanup() {
    rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

copy_flat_files() {
    local source="$1"
    local destination="$2"
    local path base target

    mkdir -p "$destination"
    for path in "$source"/*; do
        [ -f "$path" ] || continue
        base="${path##*/}"
        target="${base#executable_}"
        cp -p -- "$path" "$destination/$target"
    done
}

if [ -e "$I3_ROOT/executable_overflow-watcher.py" ]; then
    RENDER_ROOT="$WORK_ROOT/rendered"
    copy_flat_files "$I3_ROOT" "$RENDER_ROOT/i3"
    copy_flat_files "$I3_ROOT/tests" "$RENDER_ROOT/i3/tests"
    copy_flat_files "$POLYBAR_ROOT" "$RENDER_ROOT/polybar"
    copy_flat_files "$POLYBAR_ROOT/scripts" "$RENDER_ROOT/polybar/scripts"
    copy_flat_files "$POLYBAR_ROOT/tests" "$RENDER_ROOT/polybar/tests"
    find "$RENDER_ROOT" -type f \( -name '*.sh' -o -name '*.py' \) \
        -exec chmod +x {} +
    I3_ROOT="$RENDER_ROOT/i3"
    POLYBAR_ROOT="$RENDER_ROOT/polybar"
fi

run() {
    local label="$1"
    shift
    printf '%-34s' "$label"
    "$@"
}

mapfile -d '' SHELL_FILES < <(
    find "$I3_ROOT" "$POLYBAR_ROOT" -type f -name '*.sh' -print0
)
run 'Bash syntax' bash -n "${SHELL_FILES[@]}"
printf 'PASS\n'

if command -v shellcheck >/dev/null 2>&1; then
    run 'ShellCheck warnings/errors' \
        shellcheck -x --severity=warning -P "$I3_ROOT" "${SHELL_FILES[@]}"
    printf 'PASS\n'
fi

if command -v i3 >/dev/null 2>&1; then
    mkdir -p "$WORK_ROOT/runtime"
    run 'i3 config parse' env XDG_RUNTIME_DIR="$WORK_ROOT/runtime" \
        i3 -C -c "$I3_ROOT/config"
    printf 'PASS\n'
fi

run 'overflow watcher unit tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-overflow-watcher.py"
run 'Super listener unit tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-super-polybar-listener.py"
run 'top-edge peek unit tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-top-edge-peek.py"
run 'config consistency tests' \
    env I3_POLYBAR_CONFIG="$POLYBAR_ROOT/config.ini" \
    /usr/bin/python3 "$I3_ROOT/tests/test-config-consistency.py"
run 'provisioning contract tests' \
    env CHEZMOI_PACKAGE_MANIFEST="$PACKAGE_MANIFEST" \
    /usr/bin/python3 "$I3_ROOT/tests/test-provisioning-contract.py"

run 'bar navigation tests' bash "$I3_ROOT/tests/test-bar-nav.sh"
run 'Polybar peek tests' bash "$I3_ROOT/tests/test-polybar-peek.sh"
run 'resurrect Polybar tests' \
    bash "$I3_ROOT/tests/test-i3-resurrect-polybar.sh"
run 'RandR hotplug tests' bash "$I3_ROOT/tests/test-randr-hotplug.sh"
run 'window-mode tests' bash "$I3_ROOT/tests/test-window-mode.sh"
run 'resnap duplicate-mark tests' bash "$I3_ROOT/tests/test-resnap.sh"
run 'Polybar launcher tests' bash "$POLYBAR_ROOT/tests/test-launch.sh"
run 'power confirmation tests' \
    bash "$POLYBAR_ROOT/tests/test-confirm-poweroff.sh"

printf 'PASS: all fast i3/Polybar checks\n'
