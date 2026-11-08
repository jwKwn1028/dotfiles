#!/usr/bin/env zsh

emulate -LR zsh
setopt errexit nounset pipe_fail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h:h}
OPENERS_FILE=${ZSH_OPENERS_FILE:-$REPO_ROOT/dot_zsh/rc.d/45-openers.zsh}
[[ -r $OPENERS_FILE ]] || OPENERS_FILE=$HOME/.zsh/rc.d/45-openers.zsh
ALIASES_FILE=${ZSH_ALIASES_FILE:-$REPO_ROOT/dot_zsh/rc.d/30-aliases.zsh}
[[ -r $ALIASES_FILE ]] || ALIASES_FILE=$HOME/.zsh/rc.d/30-aliases.zsh

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

[[ -r $OPENERS_FILE ]] || fail "cannot read 45-openers.zsh"

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT

PDF_FILE="$TEST_TMP/report with spaces.pdf"
EPUB_FILE="$TEST_TMP/book with spaces.epub"
PNG_FILE="$TEST_TMP/photo with spaces.png"
OPEN_LOG="$TEST_TMP/open.log"
CONTROL_LOG="$TEST_TMP/control.log"
ORDER_LOG="$TEST_TMP/order.log"
SESSION_OUTPUT="$TEST_TMP/session-output.log"
: >| "$PDF_FILE"
: >| "$EPUB_FILE"
: >| "$PNG_FILE"

typeset -r SESSION_PROGRAM='
_have() { [[ " $MISSING " != *" $1 "* ]]; }
_zsh_ls_files() { print -r -- "$PICK_FILE"; }
fzf() { cat; return "$FZF_STATUS"; }

_log_viewer() {
  local record="viewer=$1" arg
  shift
  for arg in "$@"; do
    record+=" arg=<$arg>"
  done
  print -r -- "$record" >> "$OPEN_LOG"
}
sioyek() { _log_viewer sioyek "$@"; }
zathura() { _log_viewer zathura "$@"; }
ebook-viewer() { _log_viewer ebook-viewer "$@"; }
feh() { _log_viewer feh "$@"; }
xviewer() { _log_viewer xviewer "$@"; }

source "$OPENERS_FILE"

case $RUN_MODE in
  picked)
    "$OPENER"
    print -r -- survived >> "$CONTROL_LOG"
    ;;
  direct)
    "$OPENER" "$PICK_FILE"
    print -r -- survived >> "$CONTROL_LOG"
    ;;
  cancelled)
    "$OPENER"
    print -r -- "status=$?" >> "$CONTROL_LOG"
    print -r -- survived >> "$CONTROL_LOG"
    ;;
esac
'

run_session() {
  local opener=$1 mode=$2 file=$3 fzf_status=${4:-0}
  : >| "$OPEN_LOG"
  : >| "$CONTROL_LOG"
  : >| "$SESSION_OUTPUT"

  if ! env \
      OPENERS_FILE="$OPENERS_FILE" \
      OPENER="$opener" \
      RUN_MODE="$mode" \
      PICK_FILE="$file" \
      FZF_STATUS="$fzf_status" \
      MISSING="${MISSING:-}" \
      OPEN_LOG="$OPEN_LOG" \
      CONTROL_LOG="$CONTROL_LOG" \
      zsh -f -ic "$SESSION_PROGRAM" </dev/null \
      >| "$SESSION_OUTPUT" 2>&1; then
    fail "$opener $mode session failed: $(<"$SESSION_OUTPUT")"
  fi
}

wait_for_viewer() {
  local expected=$1 contents attempt
  for attempt in {1..100}; do
    contents=$(<"$OPEN_LOG")
    [[ $contents == *"viewer=$expected"* ]] && return 0
    sleep 0.01
  done
  fail "viewer $expected did not launch: $(<"$SESSION_OUTPUT")"
}

expect_picked_closes() {
  local opener=$1 viewer=$2 file=$3 contents
  run_session "$opener" picked "$file"
  wait_for_viewer "$viewer"

  contents=$(<"$CONTROL_LOG")
  [[ -z $contents ]] ||
    fail "$opener continued after a successful pick: $contents"
  contents=$(<"$OPEN_LOG")
  [[ $contents == *"arg=<$file>"* ]] ||
    fail "$opener did not preserve the selected path: $contents"
}

expect_direct_stays_open() {
  local opener=$1 viewer=$2 file=$3 contents
  run_session "$opener" direct "$file"
  wait_for_viewer "$viewer"

  contents=$(<"$CONTROL_LOG")
  [[ $contents == survived ]] ||
    fail "$opener closed after a direct path: $contents"
}

expect_cancel_stays_open() {
  local opener=$1 file=$2 contents
  run_session "$opener" cancelled "$file" 130

  contents=$(<"$CONTROL_LOG")
  [[ $contents == $'status=130\nsurvived' ]] ||
    fail "$opener did not preserve cancellation in the current shell: $contents"
  [[ ! -s $OPEN_LOG ]] ||
    fail "$opener launched a viewer after cancellation: $(<"$OPEN_LOG")"
}

expect_picked_closes so sioyek "$PDF_FILE"
expect_picked_closes zo zathura "$PDF_FILE"
expect_picked_closes bo ebook-viewer "$EPUB_FILE"
expect_picked_closes io xviewer "$PNG_FILE"
MISSING=xviewer expect_picked_closes io feh "$PNG_FILE"

expect_direct_stays_open so sioyek "$PDF_FILE"
expect_direct_stays_open zo zathura "$PDF_FILE"
expect_direct_stays_open bo ebook-viewer "$EPUB_FILE"
expect_direct_stays_open io xviewer "$PNG_FILE"
MISSING=xviewer expect_direct_stays_open io feh "$PNG_FILE"

expect_cancel_stays_open so "$PDF_FILE"
expect_cancel_stays_open zo "$PDF_FILE"
expect_cancel_stays_open bo "$EPUB_FILE"
expect_cancel_stays_open io "$PNG_FILE"

# External mocks exercise command lookup past the thunar function.
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/folder with spaces/sub dir"
sed -n '/^_close_gui_terminal() {/,/^}/p' "$ALIASES_FILE" >| "$TEST_TMP/zsh-close"
cat >| "$TEST_TMP/bin/thunar" <<'MOCK'
#!/bin/sh
{
  printf 'viewer=thunar'
  for arg in "$@"; do printf ' arg=<%s>' "$arg"; done
  printf '\n'
} >> "$OPEN_LOG"
exit "$THUNAR_STATUS"
MOCK
cat >| "$TEST_TMP/bin/dbus-send" <<'MOCK'
#!/bin/sh
{
  printf 'viewer=dbus'
  for arg in "$@"; do
    case $arg in
      --print-reply) printf ' reply' ;;
      org.xfce.FileManager.DisplayFolder) printf ' method=DisplayFolder'; window=1 ;;
      org.freedesktop.DBus.StartServiceByName) printf ' method=StartServiceByName' ;;
      string:?*) printf ' arg=<%s>' "${arg#string:}" ;;
    esac
  done
  printf '\n'
} >> "$OPEN_LOG"
# Whether the calling shell had exited when the window was requested.
if [ -n "${window:-}" ]; then
  kill -0 "$SESSION_PID" 2>/dev/null && echo alive >> "$ORDER_LOG" || echo gone >> "$ORDER_LOG"
fi
exit "$DBUS_STATUS"
MOCK
chmod +x "$TEST_TMP/bin/thunar" "$TEST_TMP/bin/dbus-send"

typeset -r THUNAR_SESSION_PROGRAM='
export SESSION_PID=$$
source "$GUI_CLOSE_FILE"
source "$THUNAR_OPENERS_FILE"
cd -- "$THUNAR_CWD" || exit 1
case $RUN_MODE in
  direct) thunar "$THUNAR_CWD" ;;
  relative) thunar "sub dir" ;;
  multiple) thunar "$THUNAR_CWD" "$SECOND_FOLDER" ;;
  file) thunar "$THUNAR_CWD" "$PDF_FILE" ;;
  *) thunar ;;
esac
printf "status=%s\nsurvived\n" "$?" >> "$CONTROL_LOG"
'

run_thunar_session() {
  local mode=$1 interactive=${2:-interactive}
  local -a shell_args=(-f)
  [[ $interactive == interactive ]] && shell_args+=(-ic) || shell_args+=(-c)
  : >| "$OPEN_LOG"
  : >| "$CONTROL_LOG"
  : >| "$ORDER_LOG"
  : >| "$SESSION_OUTPUT"
  if ! env \
      PATH="$TEST_TMP/bin:$PATH" \
      GUI_CLOSE_FILE="$TEST_TMP/zsh-close" \
      THUNAR_OPENERS_FILE="$OPENERS_FILE" \
      THUNAR_CWD="$TEST_TMP/folder with spaces" \
      SECOND_FOLDER="$TEST_TMP" \
      PDF_FILE="$PDF_FILE" \
      THUNAR_STATUS="${THUNAR_STATUS:-0}" \
      DBUS_STATUS="${DBUS_STATUS:-0}" \
      TERM_PROGRAM="${TEST_TERM_PROGRAM:-ghostty}" \
      TMUX="${TEST_TMUX:-}" \
      SSH_CONNECTION="${TEST_SSH_CONNECTION:-}" \
      RUN_MODE="$mode" \
      OPEN_LOG="$OPEN_LOG" \
      CONTROL_LOG="$CONTROL_LOG" \
      ORDER_LOG="$ORDER_LOG" \
      zsh "${shell_args[@]}" "$THUNAR_SESSION_PROGRAM" </dev/null \
      >| "$SESSION_OUTPUT" 2>&1; then
    fail "thunar $mode session failed: $(<"$SESSION_OUTPUT")"
  fi
}

# Wait for exactly these open-log lines, in any order.
expect_opens() {
  local mode=$1 contents line attempt missing
  shift
  for attempt in {1..100}; do
    contents=$'\n'$(<"$OPEN_LOG")$'\n'
    missing=0
    for line in "$@"; do
      [[ $contents == *$'\n'"$line"$'\n'* ]] || missing=1
    done
    (( ! missing && $(wc -l < "$OPEN_LOG") == $# )) && return 0
    sleep 0.01
  done
  fail "$mode opened: $(<"$OPEN_LOG") $(<"$SESSION_OUTPUT")"
}

expect_thunar_stays_open() {
  local mode=$1 interactive=$2 contents
  shift 2
  run_thunar_session "$mode" "$interactive"
  expect_opens "thunar $mode" "$@"
  contents=$(<"$CONTROL_LOG")
  [[ $contents == $'status=0\nsurvived' ]] ||
    fail "thunar $mode unexpectedly closed: $contents"
}

folder="$TEST_TMP/folder with spaces"
dbus_open='viewer=dbus reply method=DisplayFolder arg='
dbus_start='viewer=dbus reply method=StartServiceByName arg=<org.xfce.FileManager>'

# Ghostty 1.3 loses focus if the tab closes after Thunar's window appears.
run_thunar_session bare
expect_opens "bare thunar" "$dbus_start" "$dbus_open<$folder>"
[[ ! -s $CONTROL_LOG ]] || fail "bare thunar did not close"
[[ $(<"$ORDER_LOG") == gone ]] ||
  fail "bare thunar opened the window before its shell exited"

expect_thunar_stays_open direct interactive "$dbus_open<$folder>"
expect_thunar_stays_open relative interactive "$dbus_open<$folder/sub dir>"
expect_thunar_stays_open multiple interactive "$dbus_open<$folder>" "$dbus_open<$TEST_TMP>"
expect_thunar_stays_open file interactive "viewer=thunar arg=<$folder> arg=<$PDF_FILE>"
TEST_SSH_CONNECTION=test-session expect_thunar_stays_open bare interactive \
  "viewer=thunar arg=<$folder>"
TEST_TMUX=test-session expect_thunar_stays_open bare interactive "$dbus_open<$folder>"
TEST_TERM_PROGRAM=xterm expect_thunar_stays_open bare interactive "$dbus_open<$folder>"
expect_thunar_stays_open bare noninteractive "$dbus_open<$folder>"

DBUS_STATUS=23 run_thunar_session bare
[[ $(<"$CONTROL_LOG") == $'status=23\nsurvived' ]] ||
  fail "thunar closed or lost the failed D-Bus status"
sleep 0.2
[[ $(<"$OPEN_LOG") == "$dbus_start" ]] ||
  fail "thunar requested a window after Thunar failed to start: $(<"$OPEN_LOG")"

# c and z: a closing shell exits before the editor runs; elsewhere it runs here.
sed -n '/^_close_gui_terminal() {/,/^}/p; /^_open_gui_editor() {/,/^}/p' \
  "$ALIASES_FILE" >| "$TEST_TMP/zsh-editor"
cat >| "$TEST_TMP/bin/fake-editor" <<'MOCK'
#!/bin/sh
kill -0 "$SESSION_PID" 2>/dev/null && shell=alive || shell=gone
printf 'viewer=editor arg=<%s> cwd=<%s> shell=%s\n' "$1" "$PWD" "$shell" >> "$OPEN_LOG"
exit "$EDITOR_STATUS"
MOCK
chmod +x "$TEST_TMP/bin/fake-editor"

typeset -r EDITOR_SESSION_PROGRAM='
export SESSION_PID=$$
source "$EDITOR_FILE"
cd -- "$THUNAR_CWD" || exit 1
_open_gui_editor "$EDITOR_NAME"
printf "status=%s\nsurvived\n" "$?" >> "$CONTROL_LOG"
'

run_editor_session() {
  : >| "$OPEN_LOG"
  : >| "$CONTROL_LOG"
  env PATH="$TEST_TMP/bin:$PATH" EDITOR_FILE="$TEST_TMP/zsh-editor" \
    EDITOR_NAME="${TEST_EDITOR:-fake-editor}" EDITOR_STATUS="${EDITOR_STATUS:-0}" \
    THUNAR_CWD="$folder" TERM_PROGRAM=ghostty TMUX="${TEST_TMUX:-}" SSH_CONNECTION= \
    OPEN_LOG="$OPEN_LOG" CONTROL_LOG="$CONTROL_LOG" \
    zsh -f -ic "$EDITOR_SESSION_PROGRAM" </dev/null >| "$SESSION_OUTPUT" 2>&1 || true
}

run_editor_session
expect_opens editor "viewer=editor arg=<.> cwd=<$folder> shell=gone"
[[ ! -s $CONTROL_LOG ]] || fail "editor opener did not close"

TEST_TMUX=test-session run_editor_session
[[ $(<"$OPEN_LOG") == "viewer=editor arg=<.> cwd=<$folder> shell=alive" &&
   $(<"$CONTROL_LOG") == $'status=0\nsurvived' ]] ||
  fail "editor opener in tmux: $(<"$OPEN_LOG") $(<"$CONTROL_LOG")"

TEST_TMUX=test-session EDITOR_STATUS=5 run_editor_session
[[ $(<"$CONTROL_LOG") == $'status=5\nsurvived' ]] ||
  fail "editor opener lost the editor status: $(<"$CONTROL_LOG")"

TEST_EDITOR=missing-editor run_editor_session
[[ $(<"$CONTROL_LOG") == $'status=127\nsurvived' && ! -s $OPEN_LOG ]] ||
  fail "editor opener closed for a missing editor: $(<"$CONTROL_LOG")"

print 'PASS: GUI pickers, c/z, and thunar close only the intended shell'
