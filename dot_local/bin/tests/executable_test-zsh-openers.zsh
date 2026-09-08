#!/usr/bin/env zsh

emulate -LR zsh
setopt errexit nounset pipe_fail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h:h}
OPENERS_FILE=${ZSH_OPENERS_FILE:-$REPO_ROOT/dot_zsh/rc.d/45-openers.zsh}
[[ -r $OPENERS_FILE ]] || OPENERS_FILE=$HOME/.zsh/rc.d/45-openers.zsh

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

[[ -r $OPENERS_FILE ]] || fail "cannot read 45-openers.zsh"

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT

PDF_FILE="$TEST_TMP/report with spaces.pdf"
EPUB_FILE="$TEST_TMP/book with spaces.epub"
OPEN_LOG="$TEST_TMP/open.log"
CONTROL_LOG="$TEST_TMP/control.log"
SESSION_OUTPUT="$TEST_TMP/session-output.log"
: >| "$PDF_FILE"
: >| "$EPUB_FILE"

typeset -r SESSION_PROGRAM='
_have() { return 0; }
_zsh_ls_files() { print -r -- "$PICK_FILE"; }
fzf() { cat; return "$FZF_STATUS"; }

_log_viewer() {
  local viewer=$1 arg
  shift
  print -r -- "viewer=$viewer" >> "$OPEN_LOG"
  for arg in "$@"; do
    print -r -- "arg=<$arg>" >> "$OPEN_LOG"
  done
}
sioyek() { _log_viewer sioyek "$@"; }
zathura() { _log_viewer zathura "$@"; }
ebook-viewer() { _log_viewer ebook-viewer "$@"; }

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

expect_direct_stays_open so sioyek "$PDF_FILE"
expect_direct_stays_open zo zathura "$PDF_FILE"
expect_direct_stays_open bo ebook-viewer "$EPUB_FILE"

expect_cancel_stays_open so "$PDF_FILE"
expect_cancel_stays_open zo "$PDF_FILE"
expect_cancel_stays_open bo "$EPUB_FILE"

print 'PASS: Zsh GUI pickers close only their successful interactive surface'
