#!/usr/bin/env bash

set -euo pipefail

TESTS_DIR="$(dirname "$(readlink -f "$0")")"
I3_ROOT="$(dirname "$TESTS_DIR")"
POLYBAR_ROOT="$(dirname "$I3_ROOT")/polybar"
DUNST_OVERRIDE="$(dirname "$I3_ROOT")/systemd/user/dunst.service.d/override.conf"
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

# Sections run in parallel (TEST_JOBS=1: one at a time); results print in order.
JOBS="${TEST_JOBS:-$(nproc 2>/dev/null || echo 4)}"
SECTIONS="$WORK_ROOT/sections"
mkdir -p "$SECTIONS"
LABELS=()
NEXT=0
FAILED=0

section() {
    local index="$1"
    shift
    local status=0
    mkdir -m 700 "$SECTIONS/runtime-$index" || status=$?
    # set -e would exit before the status is written.
    if [ "$status" = 0 ]; then
        XDG_RUNTIME_DIR="$SECTIONS/runtime-$index" "$@" </dev/null >"$SECTIONS/$index.out" 2>&1 || status=$?
    fi
    printf '%s\n' "$status" >"$SECTIONS/$index.status.tmp" &&
        mv -- "$SECTIONS/$index.status.tmp" "$SECTIONS/$index.status"
}

report() {
    local status last extra
    while [ "$NEXT" -lt "${#LABELS[@]}" ] && [ -e "$SECTIONS/$NEXT.status" ]; do
        if ! read -r status extra <"$SECTIONS/$NEXT.status" || [[ ! $status =~ ^[0-9]+$ || -n $extra ]]; then
            status='invalid result'
        fi
        last="$(grep -v '^[[:space:]]*$' "$SECTIONS/$NEXT.out" | tail -n 1 || true)"
        if [ "$status" != 0 ]; then
            printf '%-34s FAIL (exit %s)\n' "${LABELS[NEXT]}" "$status"
            tail -n 15 "$SECTIONS/$NEXT.out" | sed 's/^/    | /'
            FAILED=$((FAILED + 1))
        elif grep -qE 'SKIP:|skipped=[1-9]' "$SECTIONS/$NEXT.out"; then
            printf '%-34s %s\n' "${LABELS[NEXT]}" "$(grep -m1 -E 'SKIP:|skipped=[1-9]' "$SECTIONS/$NEXT.out")"
        else
            printf '%-34s %s\n' "${LABELS[NEXT]}" "${last:-PASS}"
        fi
        NEXT=$((NEXT + 1))
    done
}

run() {
    local label="$1"
    shift
    while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
        wait -n || true
        report
    done
    LABELS+=("$label")
    section "$((${#LABELS[@]} - 1))" "$@" &
    report
}

bash_syntax() {
    local shell_file
    for shell_file in "$@"; do
        bash -n "$shell_file" || return
    done
}

mapfile -d '' SHELL_FILES < <(
    find "$I3_ROOT" "$POLYBAR_ROOT" -type f -name '*.sh' -print0
)
run 'Bash syntax' bash_syntax "${SHELL_FILES[@]}"

if command -v shellcheck >/dev/null 2>&1; then
    run 'ShellCheck warnings/errors' \
        shellcheck -x --severity=warning -P "$I3_ROOT" "${SHELL_FILES[@]}"
fi

if command -v i3 >/dev/null 2>&1; then
    run 'i3 config parse' i3 -C -c "$I3_ROOT/config"
fi

run 'workspace groups tests' /usr/bin/python3 "$I3_ROOT/tests/test-workspace-groups.py"
run 'scratch terminal tests' /usr/bin/python3 "$I3_ROOT/tests/test-scratch-terminal.py"
run 'overflow watcher unit tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-overflow-watcher.py"
run 'Super listener unit tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-super-polybar-listener.py"
run 'top-edge peek unit tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-top-edge-peek.py"
run 'quit key unit tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-quit-key.py"
run 'zen URL state unit tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-zen-url-state.py"
run 'crash log unit tests' /usr/bin/python3 "$I3_ROOT/tests/test-i3-crash-log.py"
run 'resurrect snapshot tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-resurrect-state.py"
run 'all-groups snapshot tests' \
    /usr/bin/python3 "$I3_ROOT/tests/test-i3-resurrect-session.py"
run 'config consistency tests' \
    env I3_POLYBAR_CONFIG="$POLYBAR_ROOT/config.ini" \
    /usr/bin/python3 "$I3_ROOT/tests/test-config-consistency.py"
run 'provisioning contract tests' \
    env CHEZMOI_PACKAGE_MANIFEST="$PACKAGE_MANIFEST" \
    /usr/bin/python3 "$I3_ROOT/tests/test-provisioning-contract.py"

run 'bar navigation tests' bash "$I3_ROOT/tests/test-bar-nav.sh"
run 'bar marker notification tests' /usr/bin/python3 "$I3_ROOT/tests/test_bar_nav_marker.py"
run 'Polybar peek tests' bash "$I3_ROOT/tests/test-polybar-peek.sh"
run 'resurrect Polybar tests' \
    bash "$I3_ROOT/tests/test-i3-resurrect-polybar.sh"
run 'resurrect Ghostty session tests' \
    bash "$I3_ROOT/tests/test-i3-resurrect-ghostty.sh"
run 'RandR hotplug tests' bash "$I3_ROOT/tests/test-randr-hotplug.sh"
run 'display setup tests' bash "$I3_ROOT/tests/test-display-setup.sh"
run 'USB hotplug tests' bash "$I3_ROOT/tests/test-usb-hotplug.sh"
run 'Dunst monitor selection tests' \
    env DUNST_SYSTEMD_OVERRIDE="$DUNST_OVERRIDE" \
    bash "$I3_ROOT/tests/test-dunst-start.sh"
run 'validated i3 restart tests' bash "$I3_ROOT/tests/test-i3-restart.sh"
run 'session reload tests' bash "$I3_ROOT/tests/test-session-reload.sh"
run 'xfsettingsd start tests' bash "$I3_ROOT/tests/test-xfsettingsd-start.sh"
run 'window-mode tests' bash "$I3_ROOT/tests/test-window-mode.sh"
run 'lock wrapper tests' bash "$I3_ROOT/tests/test-lock.sh"
run 'resnap duplicate-mark tests' bash "$I3_ROOT/tests/test-resnap.sh"
run 'tile-snap geometry tests' bash "$I3_ROOT/tests/test-tile-snap.sh"
run 'snap watcher tests' bash "$I3_ROOT/tests/test-snap-watcher.sh"
run 'Polybar launcher tests' bash "$POLYBAR_ROOT/tests/test-launch.sh"
run 'power confirmation tests' \
    bash "$POLYBAR_ROOT/tests/test-confirm-poweroff.sh"
run 'volume watcher tests' /usr/bin/python3 "$POLYBAR_ROOT/tests/test-volume.py"

wait
report
[ "$NEXT" -eq "${#LABELS[@]}" ] || { printf 'FAIL: missing result for %s\n' "${LABELS[NEXT]}" >&2; exit 1; }
[ "$FAILED" -eq 0 ] || { printf 'FAIL: %d of %d i3/Polybar checks\n' "$FAILED" "${#LABELS[@]}"; exit 1; }
printf 'PASS: all fast i3/Polybar checks\n'
