#!/usr/bin/env bash

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
WATCHER="$ROOT/snap-watcher.sh"
[ -r "$WATCHER" ] || WATCHER="$ROOT/executable_snap-watcher.sh"
COMMON="$ROOT/_snap-common.sh"
[ -r "$COMMON" ] || COMMON="$ROOT/executable__snap-common.sh"

TEST_TMP="$(mktemp -d)"
WPID=""
cleanup() {
    [ -n "$WPID" ] && kill "$WPID" 2>/dev/null
    rm -rf -- "$TEST_TMP"
}
trap cleanup EXIT

MOCK_BIN="$TEST_TMP/bin"
I3_DIR="$TEST_TMP/i3"
mkdir -p "$MOCK_BIN" "$I3_DIR" "$TEST_TMP/runtime" "$TEST_TMP/state" "$TEST_TMP/home"

cp -p -- "$WATCHER" "$I3_DIR/snap-watcher.sh"
cp -p -- "$COMMON" "$I3_DIR/_snap-common.sh"
chmod +x "$I3_DIR/snap-watcher.sh"

export XDG_RUNTIME_DIR="$TEST_TMP/runtime"
export XDG_STATE_HOME="$TEST_TMP/state"
export HOME="$TEST_TMP/home"
export PATH="$MOCK_BIN:/usr/bin:/bin"

export SNAP_TEST_TREE="$TEST_TMP/tree.json"
export SNAP_TEST_EVENT="$TEST_TMP/event.json"
export SNAP_TEST_SUBSCRIBED="$TEST_TMP/subscribed"
export SNAP_TEST_CMDS="$TEST_TMP/cmds"
export SNAP_TEST_SNAPS="$TEST_TMP/tile-snap-calls"
SNAP_LOG="$TEST_TMP/state/i3/snap.log"

fail() {
    echo "FAIL: $1" >&2
    echo "      tile-snap calls:" >&2
    sed 's/^/        /' "$SNAP_TEST_SNAPS" >&2
    [ -s "$SNAP_LOG" ] && sed 's/^/        log: /' "$SNAP_LOG" >&2
    exit 1
}

cat >"$MOCK_BIN/i3-msg" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-t" ]; then
    case "${2:-}" in
        get_tree) cat "$SNAP_TEST_TREE"; exit 0 ;;
        subscribe)
            if [ -f "$SNAP_TEST_SUBSCRIBED" ]; then exec sleep 30; fi
            : >"$SNAP_TEST_SUBSCRIBED"
            cat "$SNAP_TEST_EVENT"
            exit 0
            ;;
    esac
fi
printf '%s\n' "$*" >>"$SNAP_TEST_CMDS"
printf '[{"success":true}]\n'
EOF

cat >"$I3_DIR/tile-snap.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SNAP_TEST_SNAPS"
EOF

chmod +x "$MOCK_BIN/i3-msg" "$I3_DIR/tile-snap.sh"

make_tree() {
    python3 - "$SNAP_TEST_TREE" "$@" <<'PY'
import json, sys

path, specs = sys.argv[1], sys.argv[2:]


def win(wid, region):
    marks = [f"_snap_{part}" for part in region.split("+")] if region else []
    return {
        "id": wid, "type": "con", "window": 9000 + wid, "name": f"w{wid}",
        "layout": "splith", "floating": "user_off", "fullscreen_mode": 0,
        "marks": marks, "nodes": [], "floating_nodes": [],
        "rect": {"x": 0, "y": 0, "width": 640, "height": 480},
    }


kids = []
for spec in specs:
    wid, _, region = spec.partition(":")
    kids.append(win(int(wid), region))

other = {
    "id": 900, "type": "workspace", "name": "2", "num": 2, "output": "eDP-1",
    "layout": "splith", "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
    "nodes": [win(901, "full")], "floating_nodes": [],
}
tree = {
    "id": 1, "type": "root", "layout": "splith", "floating_nodes": [], "nodes": [{
        "id": 2, "type": "output", "name": "eDP-1", "layout": "output",
        "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
        "floating_nodes": [],
        "nodes": [{
            "id": 3, "type": "workspace", "name": "1", "num": 1,
            "output": "eDP-1", "layout": "splith",
            "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
            "nodes": kids, "floating_nodes": [],
        }, other],
    }],
}
with open(path, "w") as fh:
    json.dump(tree, fh)
PY
}

new_event() {
    local wid="$1" floating="${2:-user_off}"
    printf '{"change":"new","container":{"id":%s,"window":%s,"floating":"%s","marks":[]}}\n' \
        "$wid" "$((9000 + wid))" "$floating" >"$SNAP_TEST_EVENT"
}

close_event() {
    local wid="$1" marks="${2:-[]}"
    printf '{"change":"close","container":{"id":%s,"window":%s,"marks":%s}}\n' \
        "$wid" "$((9000 + wid))" "$marks" >"$SNAP_TEST_EVENT"
}

run_watcher() {
    : >"$SNAP_TEST_CMDS"
    : >"$SNAP_TEST_SNAPS"
    rm -f "$SNAP_TEST_SUBSCRIBED" "$SNAP_LOG" "$XDG_RUNTIME_DIR/i3-snap-watcher.lock"
    "$I3_DIR/snap-watcher.sh" >/dev/null 2>&1 &
    WPID=$!
    local waited
    for waited in $(seq 1 400); do
        grep -q 'subscription ended' "$SNAP_LOG" 2>/dev/null && break
        sleep 0.02
    done
    [ "$waited" -lt 400 ] || true
    kill "$WPID" 2>/dev/null
    wait "$WPID" 2>/dev/null || true
    WPID=""
    grep -q 'subscription ended' "$SNAP_LOG" 2>/dev/null ||
        fail 'the watcher never finished its event batch'
}

expect_snaps() {
    local want="$1" desc="$2" got
    got=$(tr '\n' '|' <"$SNAP_TEST_SNAPS")
    [ "$got" = "$want" ] || fail "$desc (tile-snap got [$got], wanted [$want])"
}

make_tree 101:left 102:
new_event 102
run_watcher
expect_snaps 'right 102|' 'a new window did not fill the free half'

make_tree 101:left 102:ur 103:
new_event 103
run_watcher
expect_snaps 'dr 103|' 'a new window did not fall back to the free quadrant'

make_tree 101:ur 102:
new_event 102
run_watcher
expect_snaps 'left 102|' 'a free half lost to a free quadrant'

make_tree 101:up 102:
new_event 102
run_watcher
expect_snaps 'down 102|' 'a new window did not fill the free bottom half'

make_tree 101:full 102:
new_event 102
run_watcher
expect_snaps 'left 101|right 102|' 'a full workspace was not split for the newcomer'

make_tree 101:full 102:down 103:
new_event 103
run_watcher
expect_snaps 'left 101|right 103|' 'the biggest region was not the one split'

make_tree 101:left 102:ur 103:dr 104:
new_event 104
run_watcher
expect_snaps 'ul 101|dl 104|' 'the largest region was not the one split'

make_tree 101:ul 102:ur 103:dl 104:dr 105:
new_event 105
run_watcher
expect_snaps 'unsnap 101|unsnap 102|unsnap 103|unsnap 104|' \
    'a workspace with no splittable region did not fall back to tiling'
grep -q 'no snap space remains' "$SNAP_LOG" ||
    fail 'the fallback to tiling was not logged'
grep -q '\[con_id=105\] floating disable, focus' "$SNAP_TEST_CMDS" ||
    fail 'the new window was not returned to tiling'

make_tree 101: 102:
new_event 102
run_watcher
expect_snaps '' 'a workspace with no snapped windows was snapped anyway'
grep -q 'no snap space remains' "$SNAP_LOG" &&
    fail 'an unsnapped workspace fell through to the tiling fallback'
grep -q 'floating disable' "$SNAP_TEST_CMDS" &&
    fail 'an unsnapped workspace had its new window forced back to tiling'

make_tree 101:left 102:
new_event 102 user_on
run_watcher
expect_snaps '' 'an already-floating new window was snapped'

make_tree 101: 102:
new_event 102
run_watcher
expect_snaps '' 'the watcher read snapped windows from another workspace'

make_tree 101: 102:
new_event 102
printf 'on\n' >"$TEST_TMP/runtime/i3-titles.state"
run_watcher
grep -q '\[con_id=102\] border normal' "$SNAP_TEST_CMDS" ||
    fail 'title bars on did not give a new window the normal border'
rm -f "$TEST_TMP/runtime/i3-titles.state"

make_tree 101: 102:
new_event 102
run_watcher
grep -q '\[con_id=102\] border pixel 1' "$SNAP_TEST_CMDS" ||
    fail 'title bars off did not give a new window the pixel border'

make_tree 101:left
close_event 102 '["_snap_right"]'
run_watcher
expect_snaps 'full 101|' 'the survivor did not expand into the freed space'
grep -q '\[con_id=101\] unmark _snap_left' "$SNAP_TEST_CMDS" ||
    fail 'the old region mark was not removed before resnapping'

make_tree 101:ul 102:right
close_event 103 '["_snap_dl"]'
run_watcher
expect_snaps 'left 101|' 'the wrong window expanded, or it expanded too far'

make_tree 101:dr 102:ur
close_event 103 '["_snap_left"]'
run_watcher
expect_snaps 'down 101|up 102|' 'a window grew into a region that excludes its own quadrant'

make_tree 101:left 102:right
close_event 103 '["_snap_full"]'
run_watcher
expect_snaps '' 'a window with nowhere to grow was resnapped anyway'

make_tree 101:left
close_event 102
run_watcher
expect_snaps '' 'closing an unsnapped window triggered a rebalance'

make_tree 101:left
close_event 102 '["_snap_next_101"]'
run_watcher
expect_snaps '' 'closing a tiled window holding a restore anchor triggered a rebalance'

make_tree 101:prev_103+left 102:
new_event 102
run_watcher
expect_snaps 'right 102|' 'a restore anchor hid the region of the window holding it'

echo 'PASS: snap-watcher fills, splits, and rebalances snapped workspaces'
