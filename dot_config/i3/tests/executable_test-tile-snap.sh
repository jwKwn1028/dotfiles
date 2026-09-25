#!/usr/bin/env bash

# Geometry and mark protocol for tile-snap.sh, the XFWM-style snapper documented
# in MANUAL.md, "XFWM-Style Snap System".
#
# The i3 mock is stateful because tile-snap polls: stage 1 waits for `floating`
# to flip before placing, and stage 2 re-reads the rect and shrinks by the
# reported overflow until it fits. A mock that answered from a fixed fixture
# would let a broken convergence loop pass.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
SNAP="$ROOT/tile-snap.sh"
[ -r "$SNAP" ] || SNAP="$ROOT/executable_tile-snap.sh"
COMMON="$ROOT/_snap-common.sh"
[ -r "$COMMON" ] || COMMON="$ROOT/executable__snap-common.sh"

TEST_TMP="$(mktemp -d)"
trap 'rm -rf -- "$TEST_TMP"' EXIT
MOCK_BIN="$TEST_TMP/bin"
I3_DIR="$TEST_TMP/i3"
mkdir -p "$MOCK_BIN" "$I3_DIR" "$TEST_TMP/runtime" "$TEST_TMP/state" "$TEST_TMP/home"

cp -p -- "$SNAP" "$I3_DIR/tile-snap.sh"
cp -p -- "$COMMON" "$I3_DIR/_snap-common.sh"
chmod +x "$I3_DIR/tile-snap.sh"

export XDG_RUNTIME_DIR="$TEST_TMP/runtime"
export XDG_STATE_HOME="$TEST_TMP/state"
export HOME="$TEST_TMP/home"
export PATH="$MOCK_BIN:/usr/bin:/bin"

export SNAP_TEST_TREE="$TEST_TMP/tree.json"
export SNAP_TEST_OUTPUTS="$TEST_TMP/outputs.json"
export SNAP_TEST_CMDS="$TEST_TMP/cmds"
export SNAP_TEST_APPLY="$TEST_TMP/apply.py"
export SNAP_TEST_POLYBARS="$TEST_TMP/polybars"
export SNAP_TEST_HINT="$TEST_TMP/hint"
SNAP_LOG="$TEST_TMP/state/i3/snap.log"

fail() {
    echo "FAIL: $1" >&2
    [ -s "$SNAP_TEST_CMDS" ] && sed 's/^/      i3-msg: /' "$SNAP_TEST_CMDS" >&2
    exit 1
}

# --- the fake i3 -----------------------------------------------------------
# Applies the commands tile-snap sends, so a later poll sees their effect.
cat >"$SNAP_TEST_APPLY" <<'PY'
import json, os, re, sys

tree_path, cmd = sys.argv[1], sys.argv[2]
with open(tree_path) as fh:
    tree = json.load(fh)

m = re.search(r"\[con_id=(\d+)\]", cmd)
if not m:
    sys.exit(0)
target = int(m.group(1))


def walk(node):
    yield node
    for key in ("nodes", "floating_nodes"):
        for child in node.get(key, []):
            yield from walk(child)


node = next((n for n in walk(tree) if n.get("id") == target), None)
if node is None:
    sys.exit(0)

# Size hints, three shapes. "grow N": the window comes back N larger than asked,
# so the rect overflows and tile-snap must shrink by the reported excess.
# "cell N": the window quantises up to a multiple of N, the way a terminal rounds
# to its character cell. "min N": it refuses to go below N, so nothing fits.
hint_kind, hint_n = "", 0
hint_file = os.environ.get("SNAP_TEST_HINT", "")
if hint_file and os.path.exists(hint_file):
    text = open(hint_file).read().split()
    if len(text) == 2:
        hint_kind, hint_n = text[0], int(text[1])

for part in cmd.split(","):
    part = part.strip()
    if part.startswith("[con_id="):
        part = part.split("]", 1)[1].strip()
    if part == "floating enable":
        node["floating"] = "user_on"
    elif part == "floating disable":
        node["floating"] = "user_off"
    elif part.startswith("border "):
        node["border"] = part[len("border "):]
    elif part == "fullscreen disable":
        node["fullscreen_mode"] = 0
    elif part.startswith("mark --add "):
        node.setdefault("marks", []).append(part[len("mark --add "):])
    elif part.startswith("unmark "):
        mark = part[len("unmark "):]
        node["marks"] = [x for x in node.get("marks", []) if x != mark]
    elif part.startswith("resize set "):
        w, h = (int(x) for x in part[len("resize set "):].split())
        if hint_kind == "grow":
            w, h = w + hint_n, h + hint_n
        elif hint_kind == "cell":
            w = -(-w // hint_n) * hint_n
            h = -(-h // hint_n) * hint_n
        elif hint_kind == "min":
            w, h = max(w, hint_n), max(h, hint_n)
        node["rect"]["width"] = w
        node["rect"]["height"] = h
    elif part.startswith("move position "):
        x, y = (int(x) for x in part[len("move position "):].split())
        node["rect"]["x"] = x
        node["rect"]["y"] = y

with open(tree_path, "w") as fh:
    json.dump(tree, fh)
PY

cat >"$MOCK_BIN/i3-msg" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$SNAP_TEST_CMDS"
if [ "${1:-}" = "-t" ]; then
    case "${2:-}" in
        get_tree) cat "$SNAP_TEST_TREE"; exit 0 ;;
        get_outputs) cat "$SNAP_TEST_OUTPUTS"; exit 0 ;;
    esac
fi
/usr/bin/python3 "$SNAP_TEST_APPLY" "$SNAP_TEST_TREE" "$*"
printf '[{"success":true}]\n'
EOF

# One line per fake Polybar: "x y w h", read by both xdotool and xwininfo.
cat >"$MOCK_BIN/xdotool" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = "search" ] || exit 0
[ -s "$SNAP_TEST_POLYBARS" ] || exit 0
n=0
while IFS= read -r _; do n=$((n + 1)); printf '%d\n' "$n"; done <"$SNAP_TEST_POLYBARS"
EOF

cat >"$MOCK_BIN/xwininfo" <<'EOF'
#!/usr/bin/env bash
id="$2"
line=$(sed -n "${id}p" "$SNAP_TEST_POLYBARS" 2>/dev/null) || exit 1
[ -n "$line" ] || exit 1
read -r px py pw ph <<<"$line"
printf 'Map State: IsViewable\n'
printf '  Absolute upper-left X:  %s\n' "$px"
printf '  Absolute upper-left Y:  %s\n' "$py"
printf '  Width: %s\n' "$pw"
printf '  Height: %s\n' "$ph"
EOF

chmod +x "$MOCK_BIN/i3-msg" "$MOCK_BIN/xdotool" "$MOCK_BIN/xwininfo"

# --- fixtures --------------------------------------------------------------
# ws_rect and out_rect are given separately so a pseudo-output can disagree.
make_tree() {
    local ws_x="$1" ws_y="$2" ws_w="$3" ws_h="$4" floating="${5:-user_off}"
    local marks="${6:-[]}" siblings="${7:-0}"
    python3 - "$SNAP_TEST_TREE" "$ws_x" "$ws_y" "$ws_w" "$ws_h" "$floating" \
        "$marks" "$siblings" <<'PY'
import json, sys
path, wx, wy, ww, wh, floating, marks, siblings = sys.argv[1:]
wx, wy, ww, wh, siblings = int(wx), int(wy), int(ww), int(wh), int(siblings)


def win(i, wid):
    return {
        "id": i, "type": "con", "window": wid, "name": f"w{i}",
        "layout": "splith", "floating": "user_off", "fullscreen_mode": 0,
        "marks": [], "nodes": [], "floating_nodes": [],
        "rect": {"x": 100, "y": 200, "width": 640, "height": 480},
    }


target = win(101, 9001)
target["floating"] = floating
target["marks"] = json.loads(marks)
kids = [target] + [win(200 + n, 9100 + n) for n in range(siblings)]
tree = {
    "id": 1, "type": "root", "layout": "splith", "nodes": [{
        "id": 2, "type": "output", "name": "eDP-1", "layout": "output",
        "rect": {"x": 0, "y": 0, "width": 1920, "height": 1080},
        "nodes": [{
            "id": 3, "type": "workspace", "name": "1", "num": 1,
            "output": "eDP-1", "layout": "splith",
            "rect": {"x": wx, "y": wy, "width": ww, "height": wh},
            "nodes": kids, "floating_nodes": [],
        }],
        "floating_nodes": [],
    }],
    "floating_nodes": [],
}
with open(path, "w") as fh:
    json.dump(tree, fh)
PY
}

make_outputs() {
    printf '[{"name":"eDP-1","active":true,"rect":{"x":%s,"y":%s,"width":%s,"height":%s}}]\n' \
        "$1" "$2" "$3" "$4" >"$SNAP_TEST_OUTPUTS"
}

reset() {
    : >"$SNAP_TEST_CMDS"
    : >"$SNAP_TEST_POLYBARS"
    : >"$SNAP_TEST_HINT"
    rm -f "$SNAP_LOG" "$XDG_RUNTIME_DIR"/tile-snap-*.lock "$TEST_TMP/runtime/i3-titles.state"
}

snap() {
    local rc=0
    "$I3_DIR/tile-snap.sh" "$@" >"$TEST_TMP/out" 2>"$TEST_TMP/err" || rc=$?
    echo "$rc"
}

# "w h x y" from the placement tile-snap settled on.
placed() {
    local last
    last=$(grep -o 'resize set [0-9-]* [0-9-]*, move position [0-9-]* [0-9-]*' \
        "$SNAP_TEST_CMDS" | tail -1)
    [ -n "$last" ] || { echo "none"; return; }
    echo "$last" | sed -E 's/resize set ([0-9-]+) ([0-9-]+), move position ([0-9-]+) ([0-9-]+)/\1 \2 \3 \4/'
}

expect_placed() {
    local region="$1" want="$2" got
    reset
    make_tree 0 0 1920 1080
    make_outputs 0 0 1920 1080
    [ "$(snap "$region" 101)" = 0 ] || fail "$region exited nonzero"
    got=$(placed)
    [ "$got" = "$want" ] || fail "$region placed [$got], wanted [$want]"
}

# --- the nine regions on an even workspace ---------------------------------
expect_placed full  '1920 1080 0 0'
expect_placed left  '960 1080 0 0'
expect_placed right '960 1080 960 0'
expect_placed up    '1920 540 0 0'
expect_placed down  '1920 540 0 540'
expect_placed ul    '960 540 0 0'
expect_placed ur    '960 540 960 0'
expect_placed dl    '960 540 0 540'
expect_placed dr    '960 540 960 540'

# --- odd sizes must still tile exactly, with no 1px seam -------------------
# The halves are computed as W/2 and W-W/2 precisely so this holds.
declare -A R=()
for region in full left right up down ul ur dl dr; do
    reset
    make_tree 0 0 1921 1081
    make_outputs 0 0 1921 1081
    [ "$(snap "$region" 101)" = 0 ] || fail "$region on an odd workspace exited nonzero"
    R[$region]="$(placed)"
done

check_tiling() {
    python3 - "$1" "$2" "$3" "$4" <<'PY' || fail "$5"
import sys
a, b, w, h = sys.argv[1:5]
aw, ah, ax, ay = (int(v) for v in a.split())
bw, bh, bx, by = (int(v) for v in b.split())
w, h = int(w), int(h)
covered = aw * ah + bw * bh
overlap_w = max(0, min(ax + aw, bx + bw) - max(ax, bx))
overlap_h = max(0, min(ay + ah, by + bh) - max(ay, by))
sys.exit(0 if covered == w * h and overlap_w * overlap_h == 0 else 1)
PY
}

check_tiling "${R[left]}" "${R[right]}" 1921 1081 \
    'left+right leave a seam or overlap on an odd width'
check_tiling "${R[up]}" "${R[down]}" 1921 1081 \
    'up+down leave a seam or overlap on an odd height'
[ "${R[full]}" = '1921 1081 0 0' ] || fail "full on an odd workspace gave ${R[full]}"

quad_msg='the four quadrants do not tile an odd workspace exactly'
python3 - "${R[ul]}" "${R[ur]}" "${R[dl]}" "${R[dr]}" <<'PY' || fail "$quad_msg"
import sys
rects = [tuple(int(v) for v in a.split()) for a in sys.argv[1:5]]
area = sum(w * h for w, h, _, _ in rects)
cells = set()
for w, h, x, y in rects:
    for cx in (x, x + w - 1):
        for cy in (y, y + h - 1):
            cells.add((cx, cy))
ok = area == 1921 * 1081 and len(cells) == 16
sys.exit(0 if ok else 1)
PY

# --- a workspace rect outside its output falls back to the output ----------
reset
make_tree -100 -100 4000 4000
make_outputs 0 0 1920 1080
[ "$(snap full 101)" = 0 ] || fail 'a pseudo-output workspace exited nonzero'
[ "$(placed)" = '1920 1080 0 0' ] ||
    fail "a workspace rect larger than its output was not clamped: $(placed)"

# --- Polybar insets --------------------------------------------------------
# i3 has reserved nothing, so the whole bar height comes off the top.
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
printf '0 0 1920 30\n' >"$SNAP_TEST_POLYBARS"
[ "$(snap full 101)" = 0 ] || fail 'a top Polybar exited nonzero'
[ "$(placed)" = '1920 1050 0 30' ] ||
    fail "a top Polybar was not inset: $(placed)"

# i3 already reserved the strut, so nothing further comes off.
reset
make_tree 0 30 1920 1050
make_outputs 0 0 1920 1080
printf '0 0 1920 30\n' >"$SNAP_TEST_POLYBARS"
[ "$(snap full 101)" = 0 ] || fail 'a strutted Polybar exited nonzero'
[ "$(placed)" = '1920 1050 0 30' ] ||
    fail "a strutted Polybar was inset twice: $(placed)"

# i3 reserved only part of the bar's height, so just the remainder comes off and
# the total inset still equals the bar. This is the case the RESERVED_TOP
# subtraction exists for; a full-strut bar is skipped by the overlap test above
# and never reaches it.
reset
make_tree 0 10 1920 1070
make_outputs 0 0 1920 1080
printf '0 0 1920 30\n' >"$SNAP_TEST_POLYBARS"
[ "$(snap full 101)" = 0 ] || fail 'a partly strutted Polybar exited nonzero'
[ "$(placed)" = '1920 1050 0 30' ] ||
    fail "a partly strutted Polybar was not inset by the remainder: $(placed)"

# A bar below the output midpoint is a bottom bar.
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
printf '0 1050 1920 30\n' >"$SNAP_TEST_POLYBARS"
[ "$(snap full 101)" = 0 ] || fail 'a bottom Polybar exited nonzero'
[ "$(placed)" = '1920 1050 0 0' ] ||
    fail "a bottom Polybar was not inset: $(placed)"

# The same remainder arithmetic on the bottom edge.
reset
make_tree 0 0 1920 1070
make_outputs 0 0 1920 1080
printf '0 1050 1920 30\n' >"$SNAP_TEST_POLYBARS"
[ "$(snap full 101)" = 0 ] || fail 'a partly strutted bottom Polybar exited nonzero'
[ "$(placed)" = '1920 1050 0 0' ] ||
    fail "a partly strutted bottom Polybar was not inset by the remainder: $(placed)"

# A bar on another monitor must not shrink this workspace.
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
printf '2000 0 1920 30\n' >"$SNAP_TEST_POLYBARS"
[ "$(snap full 101)" = 0 ] || fail 'an off-monitor Polybar exited nonzero'
[ "$(placed)" = '1920 1080 0 0' ] ||
    fail "a Polybar on another monitor was counted: $(placed)"

# --- size hints: shrink by the reported overflow until it fits -------------
# The window overshoots by 40px, so the first placement overflows the region and
# the second, shrunk by exactly that, fits inside it.
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
printf 'grow 40\n' >"$SNAP_TEST_HINT"
[ "$(snap ul 101)" = 0 ] || fail 'an overshooting window exited nonzero'
grep -q 'resize set 920 500' "$SNAP_TEST_CMDS" ||
    fail 'the shrink did not subtract the reported overflow'
grep -qE 'snap 101 ul 960x540\+0\+0 \(attempts=2\)' "$SNAP_LOG" ||
    fail 'shrinking by the overflow did not land the region exactly'
[ "$(grep -c 'resize set' "$SNAP_TEST_CMDS")" = 2 ] ||
    fail "the shrink took $(grep -c 'resize set' "$SNAP_TEST_CMDS") placements, wanted 2"

# A window that quantises to a 120px cell cannot hit 540 exactly, so the fit it
# settles for is the largest one inside the region.
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
printf 'cell 120\n' >"$SNAP_TEST_HINT"
[ "$(snap ul 101)" = 0 ] || fail 'a cell-quantised window exited nonzero'
grep -q 'snap 101 ul inside 960x480+0+0' "$SNAP_LOG" ||
    fail 'a cell-quantised window did not settle as an inside fit'

# A window whose minimum exceeds the region can never fit; say so and stop.
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
printf 'min 700\n' >"$SNAP_TEST_HINT"
[ "$(snap ul 101)" = 0 ] || fail 'an oversized-minimum window exited nonzero'
grep -q 'rect did not converge' "$SNAP_LOG" ||
    fail 'a window that cannot fit its region was not reported'
[ "$(grep -c 'resize set' "$SNAP_TEST_CMDS")" -le 10 ] ||
    fail 'the convergence loop ran past its attempt cap'

# --- marks -----------------------------------------------------------------
# First snap records the pre-snap geometry, float flag included.
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
[ "$(snap left 101)" = 0 ] || fail 'the first snap exited nonzero'
grep -q 'mark --add _presnap_100_200_640_480_0' "$SNAP_TEST_CMDS" ||
    fail 'the first snap did not record the pre-snap geometry'
grep -q 'mark --add _snap_left' "$SNAP_TEST_CMDS" ||
    fail 'the first snap did not add its region mark'

reset
make_tree 0 0 1920 1080 user_on
make_outputs 0 0 1920 1080
[ "$(snap left 101)" = 0 ] || fail 'snapping an already-floating window exited nonzero'
grep -q 'mark --add _presnap_100_200_640_480_1' "$SNAP_TEST_CMDS" ||
    fail 'a floating window was recorded with float=0'

# A resnap must not overwrite the geometry the first snap recorded.
reset
make_tree 0 0 1920 1080 user_off '["_presnap_5_6_7_8_0","_snap_left"]'
make_outputs 0 0 1920 1080
[ "$(snap right 101)" = 0 ] || fail 'a resnap exited nonzero'
grep -q 'mark --add _presnap_' "$SNAP_TEST_CMDS" &&
    fail 'a resnap overwrote the original _presnap_ mark'
grep -q 'unmark _snap_left' "$SNAP_TEST_CMDS" ||
    fail 'a resnap did not strip the previous region mark'
grep -q 'mark --add _snap_right' "$SNAP_TEST_CMDS" ||
    fail 'a resnap did not add the new region mark'

# A tiled window with a sibling gets the marks unsnap needs to rebuild its slot.
reset
make_tree 0 0 1920 1080 user_off '[]' 2
make_outputs 0 0 1920 1080
[ "$(snap left 101)" = 0 ] || fail 'snapping a tiled window with siblings exited nonzero'
grep -qE 'mark --add _pretiling_3_splith_0_200' "$SNAP_TEST_CMDS" ||
    fail 'a tiled window did not record its tiling slot'
grep -q 'mark --add _snap_parent_101' "$SNAP_TEST_CMDS" ||
    fail 'the slot parent was not marked'
grep -q 'mark --add _snap_next_101' "$SNAP_TEST_CMDS" ||
    fail 'the following sibling was not marked'

# An only child has no slot to rebuild, so no tiling marks.
reset
make_tree 0 0 1920 1080 user_off '[]' 0
make_outputs 0 0 1920 1080
[ "$(snap left 101)" = 0 ] || fail 'snapping an only child exited nonzero'
grep -q '_pretiling_' "$SNAP_TEST_CMDS" &&
    fail 'an only child recorded a tiling slot it cannot restore'

# --- border follows the workspace title-bar state --------------------------
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
printf 'on\n' >"$TEST_TMP/runtime/i3-titles.state"
[ "$(snap left 101)" = 0 ] || fail 'snapping with title bars on exited nonzero'
grep -q 'border normal' "$SNAP_TEST_CMDS" ||
    fail 'title bars on did not select the normal border'

reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
[ "$(snap left 101)" = 0 ] || fail 'snapping with title bars off exited nonzero'
grep -q 'border pixel 1' "$SNAP_TEST_CMDS" ||
    fail 'title bars off did not select the pixel border'

# --- unsnap ----------------------------------------------------------------
reset
make_tree 0 0 1920 1080 user_on '["_presnap_11_22_333_444_1","_snap_left"]'
make_outputs 0 0 1920 1080
[ "$(snap unsnap 101)" = 0 ] || fail 'unsnapping a formerly floating window exited nonzero'
grep -q 'resize set 333 444, move position 11 22' "$SNAP_TEST_CMDS" ||
    fail 'unsnap did not restore the recorded floating geometry'
grep -q 'unmark _presnap_11_22_333_444_1' "$SNAP_TEST_CMDS" ||
    fail 'unsnap left the _presnap_ mark behind'
grep -q 'unmark _snap_left' "$SNAP_TEST_CMDS" ||
    fail 'unsnap left the region mark behind'

reset
make_tree 0 0 1920 1080 user_on '["_snap_left"]'
make_outputs 0 0 1920 1080
[ "$(snap unsnap 101)" = 0 ] || fail 'unsnapping without a _presnap_ mark exited nonzero'
grep -q 'floating disable' "$SNAP_TEST_CMDS" ||
    fail 'unsnap without a _presnap_ mark did not fall back to floating disable'

reset
make_tree 0 0 1920 1080 user_on '["_presnap_bogus_junk_x_y_1","_snap_left"]'
make_outputs 0 0 1920 1080
[ "$(snap unsnap 101)" = 1 ] ||
    fail 'a malformed _presnap_ mark did not fail the unsnap'
grep -q 'unmark _presnap_bogus_junk_x_y_1' "$SNAP_TEST_CMDS" ||
    fail 'a malformed _presnap_ mark was not cleared'
grep -q 'malformed mark' "$SNAP_LOG" ||
    fail 'a malformed _presnap_ mark was not logged'

# --- argument validation ---------------------------------------------------
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
[ "$(snap left 'nope; rm -rf /')" = 1 ] || fail 'a non-numeric con_id was accepted'
grep -q 'invalid con_id' "$TEST_TMP/err" ||
    fail 'a non-numeric con_id was rejected without a message'
[ -s "$SNAP_TEST_CMDS" ] && fail 'a non-numeric con_id still talked to i3'

reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
[ "$(snap sideways 101)" = 1 ] || fail 'an unknown region was accepted'
# Not stderr: the `exec {LOCK_FD}> ... 2>/dev/null` that takes the per-window
# lock sends the rest of this script's stderr to /dev/null, so the snap log is
# the only channel a bad region can report on.
grep -q 'unknown region: sideways' "$SNAP_LOG" ||
    fail 'an unknown region was not logged'
[ "$(grep -c 'resize set' "$SNAP_TEST_CMDS")" = 0 ] ||
    fail 'an unknown region still placed the window'

# A workspace i3 cannot resolve must not be guessed at.
reset
printf '{"id":1,"type":"root","nodes":[],"floating_nodes":[]}\n' >"$SNAP_TEST_TREE"
make_outputs 0 0 1920 1080
[ "$(snap left 101)" = 1 ] || fail 'an unresolvable workspace rect did not fail'
grep -q 'could not resolve workspace rect' "$SNAP_LOG" ||
    fail 'an unresolvable workspace rect was not logged'

# --- the per-window lock serialises concurrent snaps ----------------------
reset
make_tree 0 0 1920 1080
make_outputs 0 0 1920 1080
exec 9>"$XDG_RUNTIME_DIR/tile-snap-101.lock"
flock -n 9 || fail 'the test could not take the lock it means to hold'
[ "$(snap left 101)" = 0 ] || fail 'a lock-contended snap did not exit cleanly'
exec 9>&-
grep -q 'another tile-snap holds the lock' "$SNAP_LOG" ||
    fail 'a lock-contended snap did not log the skip'
grep -q 'resize set' "$SNAP_TEST_CMDS" &&
    fail 'a lock-contended snap placed the window anyway'

echo 'PASS: tile-snap geometry, insets, marks, and unsnap'
