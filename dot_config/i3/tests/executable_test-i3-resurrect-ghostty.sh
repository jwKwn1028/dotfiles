#!/usr/bin/env bash
# A save keeps each Ghostty window's shell directory, slot, and first remote
# session; a restore brings the lab route up before those sessions reattach.
# Mocks stand in for i3, i3-resurrect, /proc, and the remote helpers.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
FIXTURES="$TEST_TMP/fixtures"
PROC="$TEST_TMP/proc"
STATE_DIR="$TEST_TMP/resurrect"
META_DIR="$TEST_TMP/resurrect-meta"

cleanup() {
    rm -rf "$TEST_TMP"
}
trap cleanup EXIT

managed() {
    if [ -r "$ROOT/$1" ]; then
        printf '%s\n' "$ROOT/$1"
    else
        printf '%s\n' "$ROOT/executable_$1"
    fi
}

SAVE="$(managed i3-resurrect-save-all.sh)"
RESTORE="$(managed i3-resurrect-restore-all.sh)"
HELPER="$(managed ghostty-session-state.py)"
if [ ! -r "$ROOT/_snap-common.sh" ]; then
    APPLIED_ROOT="$TEST_TMP/i3"
    mkdir -p "$APPLIED_ROOT"
    cp -p -- "$RESTORE" "$APPLIED_ROOT/i3-resurrect-restore-all.sh"
    cp -p -- "$ROOT/_polybar-common.sh" "$APPLIED_ROOT/_polybar-common.sh"
    cp -p -- "$ROOT/executable__snap-common.sh" "$APPLIED_ROOT/_snap-common.sh"
    RESTORE="$APPLIED_ROOT/i3-resurrect-restore-all.sh"
fi

mkdir -p "$MOCK_BIN" "$FIXTURES" "$PROC" "$STATE_DIR" "$META_DIR" \
    "$TEST_TMP/home" "$TEST_TMP/runtime"

export HOME="$TEST_TMP/home"
export PATH="$MOCK_BIN:/usr/bin:/bin"
export XDG_RUNTIME_DIR="$TEST_TMP/runtime"
export I3_RESURRECT="$MOCK_BIN/i3-resurrect"
export I3_RESURRECT_STATE_DIR="$STATE_DIR"
export I3_RESURRECT_META_DIR="$META_DIR"
export I3_RESURRECT_PROC_ROOT="$PROC"
export I3_RESURRECT_GHOSTTY_HELPER="$HELPER"
export I3_RESURRECT_REMOTE_HELPERS="$TEST_TMP/remote.zsh"
export TAILSCALE_REMOTE_MODE_FILE="$TEST_TMP/proxy-required"
export I3_RESURRECT_LAYOUT_DELAY=0
export I3_RESURRECT_KILL_WAIT_ATTEMPTS=1
export I3_RESURRECT_KILL_POLL_INTERVAL=0
export I3_RESURRECT_WAIT_ATTEMPTS=1
export I3_RESURRECT_POLL_INTERVAL=0
export TEST_EVENTS="$TEST_TMP/events"
export TEST_NOTIFY="$TEST_TMP/notify"
export TEST_FIXTURES="$FIXTURES"
export TEST_TREE="$FIXTURES/tree.json"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

cat >"$MOCK_BIN/i3-msg" <<'EOF'
#!/usr/bin/env bash
case "$*" in
    '-t get_tree') cat "$TEST_TREE" ;;
    '-t get_workspaces') cat "$TEST_FIXTURES/workspaces.json" ;;
    '-t get_outputs') printf '%s\n' '[{"name":"eDP","active":true}]' ;;
    *) printf '%s\n' '[{"success":true}]' ;;
esac
EOF

# i3-resurrect {save|restore} -w WORKSPACE -d DIRECTORY ...
cat >"$MOCK_BIN/i3-resurrect" <<'EOF'
#!/usr/bin/env bash
printf 'i3-resurrect %s\n' "$*" >>"$TEST_EVENTS"
if [ "$1" = save ]; then
    cp -- "$TEST_FIXTURES/workspace_$3_layout.json" \
        "$TEST_FIXTURES/workspace_$3_programs.json" "$5/"
fi
EOF

cat >"$MOCK_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >>"$TEST_NOTIFY"
EOF

# No Polybar windows: the restore leaves the bar alone.
printf '#!/bin/sh\nexit 0\n' >"$MOCK_BIN/xdotool"
chmod +x "$MOCK_BIN"/*

cat >"$I3_RESURRECT_REMOTE_HELPERS" <<'EOF'
labroute() {
  print -r -- "labroute $*" >>"$TEST_EVENTS"
  if [[ -n ${LABROUTE_TEST_HANG-} ]]; then
    sleep 5
  elif [[ -n ${LABROUTE_TEST_FAIL-} ]]; then
    print 'labroute: starting the proxy'
    print -u2 'labroute: exit node is offline; remote SSH remains blocked'
    return 1
  fi
  print 'Lab SSH route: ON'
}
EOF

# pid ppid comm cwd WINDOWID argv...
add_proc() {
    local pid="$1" ppid="$2" comm="$3" dir="$4" window="$5"
    shift 5
    mkdir -p "$PROC/$pid"
    printf '%s (%s) S %s %s 0 0\n' "$pid" "$comm" "$ppid" "$ppid" >"$PROC/$pid/stat"
    printf '%s\0' "$@" >"$PROC/$pid/cmdline"
    if [ -n "$window" ]; then
        printf 'TERM=xterm-256color\0WINDOWID=%s\0' "$window" >"$PROC/$pid/environ"
    else
        : >"$PROC/$pid/environ"
    fi
    ln -s "$dir" "$PROC/$pid/cwd"
}

hpc_attach() {
    printf 'tmux has-session -t =%s 2>/dev/null || exit 1; exec tmux attach-session -t =%s' \
        "$1" "$1"
}

# Window 101: splits on tmux dev and zmx shell, then dev again.
add_proc 100 1 ghostty "$HOME" '' ghostty
add_proc 110 100 sh "$HOME" 101 /bin/sh -c /usr/bin/zsh
add_proc 111 110 zsh /work/a 101 /usr/bin/zsh
add_proc 112 111 ssh /work/a 101 ssh -S none -o ConnectTimeout=8 -t remote.invalid "$(hpc_attach dev)"
add_proc 120 100 sh "$HOME" 101 /bin/sh -c /usr/bin/zsh
add_proc 121 120 zsh /work/b 101 /usr/bin/zsh
# hpcz leaves ~ for the remote shell to expand.
# shellcheck disable=SC2088
add_proc 122 121 ssh /work/b 101 ssh -t remote.invalid '~/.local/bin/zmx attach shell'
add_proc 150 100 sh "$HOME" 101 /bin/sh -c /usr/bin/zsh
add_proc 151 150 zsh /work/g 101 /usr/bin/zsh
add_proc 152 151 ssh /work/g 101 ssh -t remote.invalid "$(hpc_attach dev)"
# Window 102: a plain split, then one on tmux build.
add_proc 130 100 sh "$HOME" 102 /bin/sh -c /usr/bin/zsh
add_proc 131 130 zsh /work/c 102 /usr/bin/zsh
add_proc 140 100 sh "$HOME" 102 /bin/sh -c /usr/bin/zsh
add_proc 141 140 zsh /work/e 102 /usr/bin/zsh
add_proc 142 141 ssh /work/e 102 ssh -t remote.invalid "$(hpc_attach build)"
# Windows 201 and 202: a restored instance, its shell Ghostty's direct child.
add_proc 200 1 ghostty /work/d '' ghostty --x11-instance-name=ghostty-ws4-1
add_proc 210 200 zsh /work/d 201 zsh
add_proc 211 210 ssh /work/d 201 ssh -t remote.invalid "$(hpc_attach logs)"
add_proc 220 200 sh "$HOME" 202 /bin/sh -c /usr/bin/zsh
add_proc 221 220 zsh /work/f 202 /usr/bin/zsh
# Window 502: a directory the quoted i3 exec line cannot carry.
add_proc 520 100 sh "$HOME" 502 /bin/sh -c /usr/bin/zsh
add_proc 521 520 zsh '/work/$odd"dir' 502 /usr/bin/zsh
# Window 601: a session on a workspace whose counts disagree.
add_proc 610 100 sh "$HOME" 601 /bin/sh -c /usr/bin/zsh
add_proc 611 610 zsh /work/h 601 /usr/bin/zsh
add_proc 612 611 ssh /work/h 601 ssh -t remote.invalid "$(hpc_attach solo)"
# Not Ghostty's surfaces: a stray shell with an inherited WINDOWID, and a
# process name that needs careful stat parsing.
add_proc 300 1 zsh /stale 101 /usr/bin/zsh
add_proc 301 300 ssh /stale 101 ssh -t remote.invalid "$(hpc_attach ghost)"
add_proc 400 1 'odd) name' / '' odd

cat >"$TEST_TREE" <<'EOF'
{"type":"root","nodes":[{"type":"output","name":"eDP","nodes":[{"type":"con","name":"content","nodes":[
 {"type":"workspace","name":"3",
  "floating_nodes":[{"type":"floating_con","nodes":[
   {"window":102,"window_properties":{"class":"com.mitchellh.ghostty","instance":"ghostty"}}]}],
  "nodes":[{"type":"con","nodes":[
   {"window":101,"window_properties":{"class":"com.mitchellh.ghostty","instance":"ghostty"}},
   {"window":103,"window_properties":{"class":"Thunar","instance":"thunar"}}]}]},
 {"type":"workspace","name":"4","nodes":[
  {"window":201,"window_properties":{"class":"com.mitchellh.ghostty","instance":"ghostty-ws4-1"}},
  {"window":202,"window_properties":{"class":"com.mitchellh.ghostty","instance":"ghostty-ws4-1"}}]},
 {"type":"workspace","name":"5","nodes":[
  {"window":501,"window_properties":{"class":"com.mitchellh.ghostty","instance":"ghostty"}},
  {"window":502,"window_properties":{"class":"com.mitchellh.ghostty","instance":"ghostty"}}]},
 {"type":"workspace","name":"6","nodes":[
  {"window":601,"window_properties":{"class":"com.mitchellh.ghostty","instance":"ghostty"}},
  {"window":602,"window_properties":{"class":"com.mitchellh.ghostty","instance":"ghostty"}}]}
]}]}]}
EOF

cat >"$FIXTURES/workspaces.json" <<'EOF'
[{"num":3,"name":"3","focused":true},{"num":4,"name":"4","focused":false},
 {"num":5,"name":"5","focused":false},{"num":6,"name":"6","focused":false}]
EOF

# What i3-resurrect itself writes: bare `ghostty` in the wrapper's directory.
cat >"$FIXTURES/workspace_3_layout.json" <<'EOF'
{"type":"workspace","name":"3",
 "floating_nodes":[{"type":"floating_con","nodes":[
  {"swallows":[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty$","title":"^zsh$"}]}]}],
 "nodes":[{"type":"con","nodes":[
  {"swallows":[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty$","title":"^hpc\\ dev$"}]},
  {"swallows":[{"class":"^Thunar$","instance":"^thunar$","title":"^Files$"}]}]}]}
EOF
cat >"$FIXTURES/workspace_3_programs.json" <<'EOF'
[{"command":["ghostty"],"working_directory":"/work/start"},
 {"command":["thunar"],"working_directory":"/work/start"},
 {"command":["ghostty"],"working_directory":"/work/start"}]
EOF
cat >"$FIXTURES/workspace_4_layout.json" <<'EOF'
{"type":"workspace","name":"4","nodes":[
 {"swallows":[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty\\-ws4\\-1$"}]},
 {"swallows":[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty\\-ws4\\-1$"}]}]}
EOF
cat >"$FIXTURES/workspace_4_programs.json" <<'EOF'
[{"command":["ghostty"],"working_directory":"/work/d"},
 {"command":["ghostty"],"working_directory":"/work/d"}]
EOF
cat >"$FIXTURES/workspace_5_layout.json" <<'EOF'
{"type":"workspace","name":"5","nodes":[
 {"swallows":[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty$"}]},
 {"swallows":[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty$"}]}]}
EOF
cat >"$FIXTURES/workspace_5_programs.json" <<'EOF'
[{"command":["ghostty"],"working_directory":"/work/start"},
 {"command":["ghostty"],"working_directory":"/srv/x"}]
EOF
cat >"$FIXTURES/workspace_6_layout.json" <<'EOF'
{"type":"workspace","name":"6","nodes":[
 {"swallows":[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty$"}]},
 {"swallows":[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty$"}]}]}
EOF
cat >"$FIXTURES/workspace_6_programs.json" <<'EOF'
[{"command":["ghostty"],"working_directory":"/work/start"}]
EOF

assert_json() {
    local label="$1" filter="$2" file="$3" expected="$4" actual
    actual="$(jq -c "$filter" "$file")"
    [ "$actual" = "$(jq -c . <<<"$expected")" ] || fail "$label: $actual"
}

run_restore() {
    local expected="$1"
    local status=0

    : >"$TEST_EVENTS"
    : >"$TEST_NOTIFY"
    bash "$RESTORE" 2>"$TEST_TMP/restore-stderr" || status="$?"
    [ "$status" -eq "$expected" ] ||
        fail "restore exited $status; expected $expected: $(cat "$TEST_TMP/restore-stderr")"
}

printf 'not json' | /usr/bin/python3 "$HELPER" | grep -Fqx '[]' ||
    fail 'the helper did not fall back to [] on unreadable input'

printf '%s\n' '[
 {"workspace":"3","window_id":"101","cwd":"/work/a",
  "sessions":[{"kind":"tmux","name":"dev"},{"kind":"zmx","name":"shell"}]},
 {"workspace":"3","window_id":"102","cwd":"/work/e","sessions":[{"kind":"tmux","name":"build"}]},
 {"workspace":"4","window_id":"201","cwd":"/work/d","sessions":[{"kind":"tmux","name":"logs"}]},
 {"workspace":"4","window_id":"202","cwd":"/work/f","sessions":[]},
 {"workspace":"5","window_id":"501","cwd":null,"sessions":[]},
 {"workspace":"5","window_id":"502","cwd":"/work/$odd\"dir","sessions":[]},
 {"workspace":"6","window_id":"601","cwd":"/work/h","sessions":[{"kind":"tmux","name":"solo"}]},
 {"workspace":"6","window_id":"602","cwd":null,"sessions":[]}]' >"$TEST_TMP/expected-state.json"
/usr/bin/python3 "$HELPER" <"$TEST_TREE" >"$TEST_TMP/state.json"
assert_json 'captured Ghostty state' . "$TEST_TMP/state.json" "$(cat "$TEST_TMP/expected-state.json")"

: >"$TAILSCALE_REMOTE_MODE_FILE"
: >"$TEST_EVENTS"
bash "$SAVE" 2>"$TEST_TMP/save-stderr" ||
    fail "save failed: $(cat "$TEST_TMP/save-stderr")"

assert_json 'workspace 3 programs' . "$STATE_DIR/workspace_3_programs.json" '[
 {"command":["ghostty","--working-directory=/work/a","--x11-instance-name=ghostty-ws3-1",
   "--initial-command=env I3_RESURRECT_REMOTE_SESSION=tmux:dev zsh"],"working_directory":"/work/a"},
 {"command":["thunar"],"working_directory":"/work/start"},
 {"command":["ghostty","--working-directory=/work/e","--x11-instance-name=ghostty-ws3-2",
   "--initial-command=env I3_RESURRECT_REMOTE_SESSION=tmux:build zsh"],"working_directory":"/work/e"}]'
assert_json 'workspace 3 tiled placeholder' '.nodes[0].nodes[0].swallows' \
    "$STATE_DIR/workspace_3_layout.json" \
    '[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty-ws3-1$"}]'
assert_json 'workspace 3 floating placeholder' '.floating_nodes[0].nodes[0].swallows' \
    "$STATE_DIR/workspace_3_layout.json" \
    '[{"class":"^com\\.mitchellh\\.ghostty$","instance":"^ghostty-ws3-2$"}]'
assert_json 'workspace 3 other placeholder' '.nodes[0].nodes[1].swallows' \
    "$STATE_DIR/workspace_3_layout.json" \
    '[{"class":"^Thunar$","instance":"^thunar$","title":"^Files$"}]'
assert_json 'workspace 4 programs' . "$STATE_DIR/workspace_4_programs.json" '[
 {"command":["ghostty","--working-directory=/work/d","--x11-instance-name=ghostty-ws4-1",
   "--initial-command=env I3_RESURRECT_REMOTE_SESSION=tmux:logs zsh"],"working_directory":"/work/d"},
 {"command":["ghostty","--working-directory=/work/f","--x11-instance-name=ghostty-ws4-2"],
  "working_directory":"/work/f"}]'
assert_json 'workspace 4 placeholders' '[.nodes[].swallows[0].instance]' \
    "$STATE_DIR/workspace_4_layout.json" '["^ghostty-ws4-1$","^ghostty-ws4-2$"]'
assert_json 'workspace 5 programs' . "$STATE_DIR/workspace_5_programs.json" '[
 {"command":["ghostty","--working-directory=/work/start","--x11-instance-name=ghostty-ws5-1"],
  "working_directory":"/work/start"},
 {"command":["ghostty","--working-directory=/srv/x","--x11-instance-name=ghostty-ws5-2"],
  "working_directory":"/srv/x"}]'
assert_json 'workspace 6 programs' . "$STATE_DIR/workspace_6_programs.json" \
    '[{"command":["ghostty"],"working_directory":"/work/start"}]'
assert_json 'workspace 6 placeholders' '[.nodes[].swallows[0]]' \
    "$STATE_DIR/workspace_6_layout.json" \
    '[{"class":"^com\\.mitchellh\\.ghostty$"},{"class":"^com\\.mitchellh\\.ghostty$"}]'
[ "$(cat "$META_DIR/labroute.txt")" = on ] ||
    fail 'the save did not record the lab route as on'

export TEST_TREE="$FIXTURES/empty-tree.json"
printf '%s\n' '{"type":"root","nodes":[]}' >"$TEST_TREE"

run_restore 0
labroute_line="$(grep -n -Fx 'labroute on' "$TEST_EVENTS" | cut -d: -f1)"
programs_line="$(grep -n -F -- '--programs-only' "$TEST_EVENTS" | head -n 1 | cut -d: -f1)"
[ -n "$labroute_line" ] || fail 'the restore did not bring a saved lab route back'
[ -n "$programs_line" ] && [ "$labroute_line" -lt "$programs_line" ] ||
    fail 'the lab route came up after programs started'
grep -Fqx 'Restore complete.' "$TEST_NOTIFY" ||
    fail "the restore did not report success: $(cat "$TEST_NOTIFY")"
grep -Fqx 'Reattach by hand: hpcz shell, hpc solo' "$TEST_NOTIFY" ||
    fail "the restore listed the wrong sessions to reattach: $(cat "$TEST_NOTIFY")"

export LABROUTE_TEST_FAIL=1
run_restore 1
unset LABROUTE_TEST_FAIL
reason='labroute: exit node is offline; remote SSH remains blocked'
grep -Fqx "Lab route not restored: $reason" "$TEST_TMP/restore-stderr" ||
    fail 'a failed lab route was not reported on stderr'
grep -Fqx "Lab route not restored: $reason" "$TEST_NOTIFY" ||
    fail "a failed lab route was not in the notification: $(cat "$TEST_NOTIFY")"
[ "$(grep -c -F -- '--programs-only' "$TEST_EVENTS")" -eq 4 ] ||
    fail 'programs were not restored after the lab route failed'

export LABROUTE_TEST_HANG=1 I3_RESURRECT_LABROUTE_TIMEOUT=1
run_restore 1
unset LABROUTE_TEST_HANG I3_RESURRECT_LABROUTE_TIMEOUT
grep -Fqx 'Lab route not restored: labroute on timed out after 1s' "$TEST_NOTIFY" ||
    fail "a hung lab route did not time out: $(cat "$TEST_NOTIFY")"

rm -f "$TAILSCALE_REMOTE_MODE_FILE"
export TEST_TREE="$FIXTURES/tree.json"
bash "$SAVE" 2>"$TEST_TMP/save-stderr" ||
    fail "save failed: $(cat "$TEST_TMP/save-stderr")"
[ "$(cat "$META_DIR/labroute.txt")" = off ] ||
    fail 'the save did not record the lab route as off'
export TEST_TREE="$FIXTURES/empty-tree.json"
run_restore 0
! grep -q '^labroute' "$TEST_EVENTS" ||
    fail 'the restore touched a lab route that was off at save time'

printf 'PASS: Ghostty sessions and the lab route survive save and restore\n'
