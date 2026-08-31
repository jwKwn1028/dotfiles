#!/usr/bin/env zsh

emulate -LR zsh
setopt errexit nounset pipe_fail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h:h}
ALIASES_FILE=${TASK_QUICK_ADD_ALIASES:-$REPO_ROOT/dot_zsh/rc.d/30-aliases.zsh}
[[ -r $ALIASES_FILE ]] || ALIASES_FILE=$HOME/.zsh/rc.d/30-aliases.zsh

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

[[ -r $ALIASES_FILE ]] || fail "cannot read 30-aliases.zsh"

# Disable optional command-dependent aliases.
_have() { return 1 }

typeset -ga TASK_CALL
task() {
  TASK_CALL=( "$@" )
}

# Anchor weekday arithmetic; pass other forms to GNU date.
date() {
  emulate -L zsh
  if [[ $# == 1 && $1 == +%u ]]; then
    print -r -- 1
  elif [[ $# == 1 && $1 == +%F ]]; then
    print -r -- 2026-08-24
  elif [[ $# == 1 && $1 == +%s ]]; then
    TZ=UTC /usr/bin/date -d '2026-08-24 08:00' +%s
  elif [[ $# == 3 && $1 == -d && $2 == *' days' && $3 == +%F ]]; then
    TZ=UTC /usr/bin/date -d "2026-08-24 $2" +%F
  else
    TZ=UTC /usr/bin/date "$@"
  fi
}

source "$ALIASES_FILE"

expect_call() {
  emulate -L zsh
  local label=$1
  shift
  local -a expected=( "$@" )
  local i

  (( ${#TASK_CALL} == ${#expected} )) ||
    fail "$label produced ${#TASK_CALL} arguments, expected ${#expected}: ${(j: :)TASK_CALL}"
  for (( i = 1; i <= ${#expected}; i++ )); do
    [[ ${TASK_CALL[i]} == ${expected[i]} ]] ||
      fail "$label argument $i is '${TASK_CALL[i]}', expected '${expected[i]}'"
  done
}

TASK_CALL=()
command_not_found_handler t12dh dentist +health
expect_call 'priority-only shortcut' \
  add dentist +health due:2026-09-01 priority:H

TASK_CALL=()
command_not_found_handler t12s16:30 lecture
expect_call 'time-only shortcut' \
  add lecture scheduled:2026-09-01T16:30

TASK_CALL=()
command_not_found_handler t12sm16:30 golf
expect_call 'priority-and-time shortcut' \
  add golf scheduled:2026-09-01T16:30 priority:M

print 'PASS: task quick-add preserves priority and time suffixes'
