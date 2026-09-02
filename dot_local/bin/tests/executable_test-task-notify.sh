#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"
NOTIFY="$ROOT/task-notify"
[ -r "$NOTIFY" ] || NOTIFY="$ROOT/executable_task-notify"
TEST_TMP="$(mktemp -d)"
MOCK_BIN="$TEST_TMP/bin"
STATE="$TEST_TMP/state"
TASKS="$TEST_TMP/tasks.json"
LOG="$TEST_TMP/notify-calls"
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$MOCK_BIN" "$STATE"

# The mock ignores the filter, so the script's own past-time guard is exercised.
cat >"$MOCK_BIN/task" <<'EOF'
#!/usr/bin/env bash
cat "$TASK_NOTIFY_TEST_JSON"
EOF
cat >"$MOCK_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TASK_NOTIFY_TEST_LOG"
exit "${TASK_NOTIFY_TEST_NOTIFY_EXIT:-0}"
EOF
chmod +x "$MOCK_BIN/task" "$MOCK_BIN/notify-send"

stamp() { date -u -d "@$(($(date +%s) + $1 * 60))" +%Y%m%dT%H%M%SZ; }
stamp_seconds() { date -u -d "@$(($(date +%s) + $1))" +%Y%m%dT%H%M%SZ; }
# What taskwarrior stores for a date-only `scheduled:` -- local midnight.
midnight_stamp() { date -u -d "@$(date -d 'tomorrow 00:00' +%s)" +%Y%m%dT%H%M%SZ; }
late_stamp() { date -u -d "@$(date -d 'tomorrow 23:30' +%s)" +%Y%m%dT%H%M%SZ; }

fixture() { cat >"$TASKS"; }
reset() { rm -f "$STATE/notified"; : >"$LOG"; }

run() {
    local lead=()
    if [ -n "${LEAD_DEFAULT:-}" ]; then
        lead=("TASK_NOTIFY_LEAD_DEFAULT=$LEAD_DEFAULT")
    fi
    env PATH="$MOCK_BIN:/usr/bin:/bin" \
        TASK_NOTIFY_TEST_JSON="$TASKS" \
        TASK_NOTIFY_TEST_LOG="$LOG" \
        TASK_NOTIFY_TEST_NOTIFY_EXIT="${1:-0}" \
        TASK_NOTIFY_STATE_DIR="$STATE" \
        "${lead[@]}" \
        sh "$NOTIFY" 2>"$TEST_TMP/err"
}

fail() { printf 'FAIL: %s\n' "$1" >&2; [ -s "$LOG" ] && cat "$LOG" >&2; exit 1; }
count() { wc -l <"$LOG" | tr -d ' '; }
expect_count() {
    [ "$(count)" = "$1" ] || fail "$2 (expected $1 notification(s), got $(count))"
}
expect_match() { grep -Fq -- "$1" "$LOG" || fail "$2"; }
expect_no_match() { grep -Fq -- "$1" "$LOG" && fail "$2"; return 0; }

# --- windowing, and the two exclusions ------------------------------------
reset
fixture <<EOF
[
  {"uuid":"a1","description":"inside the window","scheduled":"$(stamp 14)"},
  {"uuid":"a2","description":"beyond the window","scheduled":"$(stamp 20)"},
  {"uuid":"a3","description":"already past","scheduled":"$(stamp -5)"},
  {"uuid":"a4","description":"date but no time","scheduled":"$(midnight_stamp)"}
]
EOF
run
expect_count 1 'the 15-minute default window admitted the wrong number of tasks'
expect_match 'inside the window' 'a task 14 minutes out was not notified'
expect_no_match 'beyond the window' 'a task 20 minutes out was notified'
expect_no_match 'already past' 'a scheduled time in the past was notified'
expect_no_match 'date but no time' 'a date-only scheduled time was notified'

# Widen the window past tomorrow's midnight so only the date-only guard can
# drop it, with a 23:30 control proving the window really is that wide.
reset
fixture <<EOF
[
  {"uuid":"a5","description":"midnight, no time of day","scheduled":"$(midnight_stamp)"},
  {"uuid":"a6","description":"late but timed","scheduled":"$(late_stamp)"}
]
EOF
LEAD_DEFAULT=2d run
unset LEAD_DEFAULT
expect_match 'late but timed' 'the 2-day control window was not actually wide enough'
expect_no_match 'midnight, no time of day' 'a date-only scheduled time was notified'
expect_count 1 'the date-only scenario admitted the wrong number of tasks'

# --- dedup, re-arm, and pruning -------------------------------------------
reset
fixture <<EOF
[{"uuid":"b1","description":"repeatable","scheduled":"$(stamp 14)"}]
EOF
run
expect_count 1 'a task in window was not notified'
: >"$LOG"
run
expect_count 0 'the same task notified twice'

: >"$LOG"
fixture <<EOF
[{"uuid":"b1","description":"repeatable","scheduled":"$(stamp 10)"}]
EOF
run
expect_count 1 'rescheduling did not re-arm the reminder'
[ "$(wc -l <"$STATE/notified")" = 1 ] ||
    fail 'the superseded key was not pruned from the state file'

: >"$LOG"
fixture <<EOF
[{"uuid":"b1","description":"repeatable","scheduled":"$(stamp 300)"}]
EOF
run
expect_count 0 'a task that left the window notified again'
[ ! -s "$STATE/notified" ] || fail 'a key that left the window was not pruned'

# --- a failed notify-send is retried, not swallowed -----------------------
reset
fixture <<EOF
[{"uuid":"c1","description":"dunst is not up yet","scheduled":"$(stamp 5)"}]
EOF
run 1
[ ! -s "$STATE/notified" ] ||
    fail 'a task was recorded as notified even though notify-send failed'
: >"$LOG"
run 0
expect_count 1 'a reminder was not retried after notify-send failed'

# --- pango escaping (dunstrc sets markup = full) --------------------------
reset
fixture <<EOF
[{"uuid":"d1","description":"R&D on <chip> & >90% yield","scheduled":"$(stamp 5)"}]
EOF
run
expect_match 'R&amp;D on &lt;chip&gt; &amp; &gt;90% yield' 'markup was not escaped for pango'

# --- priority selects category and urgency --------------------------------
reset
fixture <<EOF
[
  {"uuid":"e1","description":"high","scheduled":"$(stamp 5)","priority":"H"},
  {"uuid":"e2","description":"medium","scheduled":"$(stamp 5)","priority":"M"},
  {"uuid":"e3","description":"low","scheduled":"$(stamp 5)","priority":"L"},
  {"uuid":"e4","description":"none","scheduled":"$(stamp 5)"}
]
EOF
run
expect_count 4 'not every priority produced a reminder'
expect_match '--urgency=critical --category=task.h' 'H did not map to critical/task.h'
expect_match '--urgency=normal --category=task.m' 'M did not map to normal/task.m'
expect_match '--urgency=low --category=task.l' 'L did not map to low/task.l'
expect_match '--urgency=normal --category=task.none' 'an unset priority did not map to normal/task.none'

# --- priority picks the default lead --------------------------------------
reset
fixture <<EOF
[
  {"uuid":"f1","description":"high at 25","scheduled":"$(stamp 25)","priority":"H"},
  {"uuid":"f2","description":"unset at 25","scheduled":"$(stamp 25)"},
  {"uuid":"f3","description":"low at 12","scheduled":"$(stamp 12)","priority":"L"}
]
EOF
run
expect_count 1 'the priority-derived default leads are wrong'
expect_match 'high at 25' 'H did not use its 30-minute default lead'
expect_no_match 'unset at 25' 'an unset priority used more than its 15-minute default lead'
expect_no_match 'low at 12' 'L used more than its 10-minute default lead'

# --- remind: units, bare numbers meaning hours ----------------------------
reset
fixture <<EOF
[
  {"uuid":"g1","description":"30m at 20 min","scheduled":"$(stamp 20)","remind":"30m"},
  {"uuid":"g2","description":"30m at 40 min","scheduled":"$(stamp 40)","remind":"30m"},
  {"uuid":"g3","description":"bare 2 means 2 hours","scheduled":"$(stamp 90)","remind":"2"},
  {"uuid":"g4","description":"1d at 20 hours","scheduled":"$(stamp 1200)","remind":"1d"},
  {"uuid":"g5","description":"0.5 means 30 minutes","scheduled":"$(stamp 40)","remind":"0.5"}
]
EOF
run
expect_count 3 'the remind: unit grammar admitted the wrong number of tasks'
expect_match '30m at 20 min' '30m did not cover 20 minutes'
expect_no_match '30m at 40 min' '30m covered 40 minutes'
expect_match 'bare 2 means 2 hours' 'a bare 2 was not read as 2 hours'
expect_match '1d at 20 hours' '1d did not cover 20 hours'
expect_no_match '0.5 means 30 minutes' '0.5 hours covered 40 minutes'

# --- multiple offsets fire one slot at a time, smallest open first --------
reset
fixture <<EOF
[{"uuid":"h1","description":"exam","scheduled":"$(stamp 1500)","remind":"1d,2,30m"}]
EOF
run
expect_count 0 'a task beyond its largest offset notified'

for minutes in 1200 60 20; do
    reset
    fixture <<EOF
[{"uuid":"h1","description":"exam","scheduled":"$(stamp $minutes)","remind":"1d,2,30m"}]
EOF
    run
    expect_count 1 "three open offsets burst into several popups at T-${minutes}m"
done

# The offset is part of the dedup key: seeding the slot that will fire silences
# it, while seeding an earlier slot does not.
sched=$(stamp 60)
reset
printf '%s\n' "h1 scheduled $sched 7200" >"$STATE/notified"
fixture <<EOF
[{"uuid":"h1","description":"exam","scheduled":"$sched","remind":"1d,2,30m"}]
EOF
run
expect_count 0 'the offset or field is missing from the dedup key'

reset
printf '%s\n' "h1 scheduled $sched 86400" >"$STATE/notified"
fixture <<EOF
[{"uuid":"h1","description":"exam","scheduled":"$sched","remind":"1d,2,30m"}]
EOF
run
expect_count 1 'an already-fired earlier slot blocked a later one'

# --- malformed remind: entries --------------------------------------------
reset
fixture <<EOF
[
  {"uuid":"i1","description":"partly bad","scheduled":"$(stamp 60)","remind":"2,bogus,30m"},
  {"uuid":"i2","description":"all bad falls back","scheduled":"$(stamp 20)","remind":"junk","priority":"H"},
  {"uuid":"i3","description":"all bad stays out","scheduled":"$(stamp 60)","remind":"junk","priority":"H"},
  {"uuid":"i4","description":"zero offset falls back","scheduled":"$(stamp 14)","remind":"0"},
  {"uuid":"i5","description":"zero with unit falls back","scheduled":"$(stamp 14)","remind":"0m"}
]
EOF
run
expect_count 4 'a malformed remind: was not handled per entry'
expect_match 'zero offset falls back' 'remind:0 silenced the task instead of falling back'
expect_match 'zero with unit falls back' 'remind:0m silenced the task instead of falling back'
expect_match 'partly bad' 'a valid entry beside a malformed one was dropped'
expect_match 'all bad falls back' 'a wholly malformed remind: did not fall back to the priority default'
expect_no_match 'all bad stays out' 'the fallback used more than the H default lead'
grep -q 'ignoring malformed remind entry' "$TEST_TMP/err" ||
    fail 'a malformed remind: entry was dropped without a warning'

# --- body renders the largest two units -----------------------------------
reset
fixture <<EOF
[
  {"uuid":"j1","description":"days","scheduled":"$(stamp 1666)","remind":"2d"},
  {"uuid":"j2","description":"hours","scheduled":"$(stamp 85)","remind":"2d"},
  {"uuid":"j3","description":"minutes","scheduled":"$(stamp 20)","remind":"2d"},
  {"uuid":"j4","description":"partial minute","scheduled":"$(stamp_seconds 899)"}
]
EOF
run
expect_match 'in 1d 3h' 'a multi-day lead did not render as days and hours'
expect_match 'in 1h 25m' 'an hours lead did not render as hours and minutes'
expect_match 'in 20m' 'a minutes lead did not render as minutes'
expect_match 'in 15m' 'a partial minute was rounded down in the countdown'
expect_no_match ' 0m' 'a zero minutes unit was rendered'
expect_no_match ' 0h' 'a zero hours unit was rendered'

# --- an explicit remind: adds to the priority default, never replaces it ---
reset
fixture <<EOF
[
  {"uuid":"k1","description":"r4 keeps the 15m default","scheduled":"$(stamp 14)","remind":"4"},
  {"uuid":"k2","description":"r4 keeps the 30m H default","scheduled":"$(stamp 25)","remind":"4","priority":"H"}
]
EOF
run
expect_count 2 'an explicit remind: suppressed the appended priority default'
expect_match 'r4 keeps the 15m default' 'remind:4 dropped the 15-minute default'
expect_match 'r4 keeps the 30m H default' 'remind:4 dropped the 30-minute H default'

reset
fixture <<EOF
[{"uuid":"k3","description":"duplicate of the default","scheduled":"$(stamp 14)","remind":"15m"}]
EOF
run
expect_count 1 'remind: matching the default produced two reminders'

# --- due is armed only by an explicit remind: -------------------------------
reset
fixture <<EOF
[
  {"uuid":"m1","description":"due with offsets","due":"$(stamp 60)","remind":"2"},
  {"uuid":"m2","description":"due without offsets","due":"$(stamp 14)"},
  {"uuid":"m3","description":"due already past","due":"$(stamp -30)","remind":"2"},
  {"uuid":"m4","description":"due at midnight","due":"$(midnight_stamp)","remind":"1d,2d"}
]
EOF
run
expect_count 1 'due was not armed by remind: alone'
expect_match 'due with offsets' 'an explicit remind: did not arm a due-only task'
expect_no_match 'due without offsets' 'a due date reminded without an explicit remind:'
expect_no_match 'due already past' 'a due date already past reminded'
expect_no_match 'due at midnight' 'a date-only due reminded'
grep -Eq 'due [0-9]{2}:[0-9]{2}' "$LOG" ||
    fail 'a due-based body did not label the time it announces'

reset
fixture <<EOF
[{"uuid":"m5","description":"both fields","scheduled":"$(stamp 60)","due":"$(stamp 61)","remind":"2"}]
EOF
run
expect_count 1 'a task with both fields reminded more than once'
grep -Fq 'scheduled ' "$STATE/notified" ||
    fail 'the state key does not name the field it fired on'
grep -Fq -- '-- both fields' "$LOG" || fail 'the reminder did not fire at all'
! grep -Eq 'due [0-9]{2}:[0-9]{2}' "$LOG" ||
    fail 'due won over scheduled on a task carrying both'

# Unusable remind: values still opt due-only tasks into the default lead.
reset
fixture <<EOF
[
  {"uuid":"m6","description":"due zero falls back","due":"$(stamp 14)","remind":"0"},
  {"uuid":"m7","description":"due malformed falls back","due":"$(stamp 14)","remind":"junk"}
]
EOF
run
expect_count 2 'a due-only task with an unusable remind: value went silent'
expect_match 'due zero falls back' 'remind:0 did not use the default lead for due'
expect_match 'due malformed falls back' 'malformed remind: did not use the default lead for due'

# --- the env overrides use the same offset grammar ------------------------
reset
fixture <<'EOF'
[]
EOF
status=0
env PATH="$MOCK_BIN:/usr/bin:/bin" TASK_NOTIFY_TEST_JSON="$TASKS" \
    TASK_NOTIFY_TEST_LOG="$LOG" TASK_NOTIFY_STATE_DIR="$STATE" \
    TASK_NOTIFY_LEAD_HIGH=soon sh "$NOTIFY" 2>"$TEST_TMP/err" || status=$?
[ "$status" -eq 2 ] || fail "a malformed TASK_NOTIFY_LEAD_HIGH exited $status, not 2"
grep -Fq 'TASK_NOTIFY_LEAD_HIGH must be an offset' "$TEST_TMP/err" ||
    fail 'the rejected lead override was not named'

env PATH="$MOCK_BIN:/usr/bin:/bin" TASK_NOTIFY_TEST_JSON="$TASKS" \
    TASK_NOTIFY_TEST_LOG="$LOG" TASK_NOTIFY_STATE_DIR="$STATE" \
    TASK_NOTIFY_LEAD_HIGH=90m sh "$NOTIFY" ||
    fail 'a valid offset override was rejected'

state_mode=$(stat -c %a "$STATE/notified")
[ "$state_mode" = 600 ] || fail "the state file mode is $state_mode, not 600"

# Default state lives under XDG_RUNTIME_DIR.
xdg_runtime="$TEST_TMP/xdg-runtime"
mkdir -p "$xdg_runtime"
env -u TASK_NOTIFY_STATE_DIR PATH="$MOCK_BIN:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="$xdg_runtime" \
    TASK_NOTIFY_TEST_JSON="$TASKS" TASK_NOTIFY_TEST_LOG="$LOG" \
    sh "$NOTIFY"
[ -f "$xdg_runtime/task-notify/notified" ] ||
    fail 'XDG_RUNTIME_DIR did not receive the notifier state file'

# Refuse state without an explicit private runtime directory.
status=0
env -u XDG_RUNTIME_DIR -u TASK_NOTIFY_STATE_DIR \
    PATH="$MOCK_BIN:/usr/bin:/bin" sh "$NOTIFY" 2>"$TEST_TMP/err" || status=$?
[ "$status" -eq 1 ] || fail "missing runtime state exited $status, not 1"
grep -Fq 'XDG_RUNTIME_DIR or TASK_NOTIFY_STATE_DIR is required' "$TEST_TMP/err" ||
    fail 'missing runtime state did not name either supported setting'

printf 'PASS: task-notify reminds once per offset, for future timed tasks only\n'
