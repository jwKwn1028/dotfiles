#!/usr/bin/env zsh

emulate -LR zsh
setopt errexit nounset pipe_fail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h:h}
OPENERS_FILE=${ZSH_OPENERS_FILE:-$REPO_ROOT/dot_zsh/rc.d/45-openers.zsh}
[[ -r $OPENERS_FILE ]] || OPENERS_FILE=$HOME/.zsh/rc.d/45-openers.zsh
ALIASES_FILE=${ZSH_ALIASES_FILE:-$REPO_ROOT/dot_zsh/rc.d/30-aliases.zsh}
[[ -r $ALIASES_FILE ]] || ALIASES_FILE=$HOME/.zsh/rc.d/30-aliases.zsh
BASHRC_FILE=${BASH_OPENERS_FILE:-$REPO_ROOT/dot_bashrc}
[[ -r $BASHRC_FILE ]] || BASHRC_FILE=$HOME/.bashrc

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

# External mocks exercise command/nohup lookup past the thunar function.
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/folder with spaces"
SERVICE_LOG="$TEST_TMP/service.log"
sed -n '/^_close_gui_terminal() {/,/^}/p' "$ALIASES_FILE" >| "$TEST_TMP/zsh-close"
sed -n '/^_close_gui_terminal() {/,/^}/p' "$BASHRC_FILE" >| "$TEST_TMP/bash-close"
sed -n '/^thunar() {/,/^}/p' "$BASHRC_FILE" >| "$TEST_TMP/bash-thunar"
cat >| "$TEST_TMP/bin/thunar" <<'MOCK'
#!/bin/sh
{
  printf 'viewer=thunar'
  for arg in "$@"; do printf ' arg=<%s>' "$arg"; done
  printf '\n'
} >> "$OPEN_LOG"
exit "$THUNAR_STATUS"
MOCK
cat >| "$TEST_TMP/bin/systemctl" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$SERVICE_LOG"
exit "$SERVICE_STATUS"
MOCK
chmod +x "$TEST_TMP/bin/thunar" "$TEST_TMP/bin/systemctl"

typeset -r THUNAR_SESSION_PROGRAM='
source "$GUI_CLOSE_FILE"
source "$THUNAR_OPENERS_FILE"
cd -- "$THUNAR_CWD" || exit 1
case $RUN_MODE in
  direct) thunar "$THUNAR_CWD" ;;
  multiple) thunar "$THUNAR_CWD" "$SECOND_FOLDER" ;;
  *) thunar ;;
esac
printf "status=%s\nsurvived\n" "$?" >> "$CONTROL_LOG"
'

run_thunar_session() {
  local shell=$1 mode=$2 interactive=${3:-interactive} openers_file
  local -a shell_args
  if [[ $shell == zsh ]]; then
    shell_args=(-f)
    openers_file=$OPENERS_FILE
  else
    shell_args=(--noprofile --norc)
    openers_file=$TEST_TMP/bash-thunar
  fi
  [[ $interactive == interactive ]] && shell_args+=(-ic) || shell_args+=(-c)
  : >| "$OPEN_LOG"
  : >| "$CONTROL_LOG"
  : >| "$SERVICE_LOG"
  : >| "$SESSION_OUTPUT"
  if ! env \
      PATH="$TEST_TMP/bin:$PATH" \
      GUI_CLOSE_FILE="$TEST_TMP/$shell-close" \
      THUNAR_OPENERS_FILE="$openers_file" \
      THUNAR_CWD="$TEST_TMP/folder with spaces" \
      SECOND_FOLDER="$TEST_TMP" \
      THUNAR_STATUS="${THUNAR_STATUS:-0}" \
      SERVICE_STATUS="${SERVICE_STATUS:-0}" \
      TERM_PROGRAM="${TEST_TERM_PROGRAM:-ghostty}" \
      TMUX="${TEST_TMUX:-}" \
      SSH_CONNECTION="${TEST_SSH_CONNECTION:-}" \
      RUN_MODE="$mode" \
      OPEN_LOG="$OPEN_LOG" \
      CONTROL_LOG="$CONTROL_LOG" \
      SERVICE_LOG="$SERVICE_LOG" \
      "$shell" "${shell_args[@]}" "$THUNAR_SESSION_PROGRAM" </dev/null \
      >| "$SESSION_OUTPUT" 2>&1; then
    fail "$shell thunar $mode session failed: $(<"$SESSION_OUTPUT")"
  fi
}

expect_thunar_stays_open() {
  local shell=$1 mode=$2 interactive=${3:-interactive} contents
  run_thunar_session "$shell" "$mode" "$interactive"
  wait_for_viewer thunar
  contents=$(<"$CONTROL_LOG")
  [[ $contents == $'status=0\nsurvived' ]] ||
    fail "$shell thunar $mode unexpectedly closed: $contents"
  [[ ! -s $SERVICE_LOG ]] ||
    fail "$shell thunar $mode unexpectedly started the service"
  contents=$(<"$OPEN_LOG")
  [[ $contents == *"arg=<$TEST_TMP/folder with spaces>"* ]] ||
    fail "$shell thunar $mode did not preserve the folder: $contents"
  if [[ $mode == multiple ]]; then
    [[ $contents == *"arg=<$TEST_TMP>"* ]] ||
      fail "$shell thunar lost its second argument: $contents"
  fi
}

for test_shell in zsh bash; do
  run_thunar_session "$test_shell" bare
  wait_for_viewer thunar
  [[ ! -s $CONTROL_LOG ]] || fail "$test_shell bare thunar did not close"
  [[ $(<"$SERVICE_LOG") == '--user start thunar.service' ]] ||
    fail "$test_shell bare thunar did not start its daemon"
  [[ $(<"$OPEN_LOG") == "viewer=thunar arg=<$TEST_TMP/folder with spaces>" ]] ||
    fail "$test_shell bare thunar did not open the current directory"

  expect_thunar_stays_open "$test_shell" direct
  expect_thunar_stays_open "$test_shell" multiple
  TEST_TMUX=test-session expect_thunar_stays_open "$test_shell" bare
  TEST_SSH_CONNECTION=test-session expect_thunar_stays_open "$test_shell" bare
  TEST_TERM_PROGRAM=xterm expect_thunar_stays_open "$test_shell" bare
  expect_thunar_stays_open "$test_shell" bare noninteractive

  THUNAR_STATUS=23 run_thunar_session "$test_shell" bare
  [[ $(<"$CONTROL_LOG") == $'status=23\nsurvived' ]] ||
    fail "$test_shell closed or lost the failed launch status"

  SERVICE_STATUS=31 run_thunar_session "$test_shell" bare
  [[ $(<"$CONTROL_LOG") == $'status=31\nsurvived' ]] ||
    fail "$test_shell closed or lost the failed daemon status"
  [[ ! -s $OPEN_LOG ]] || fail "$test_shell launched Thunar after daemon failure"
done

print 'PASS: GUI pickers and Bash/Zsh Thunar close only the intended shell'
