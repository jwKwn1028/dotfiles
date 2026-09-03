#!/usr/bin/env zsh

emulate -LR zsh
setopt errexit nounset pipe_fail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h:h}
REMOTE_SOURCE=${REMOTE_HELPERS_FILE:-$REPO_ROOT/dot_zsh/rc.d/50-remote.zsh.tmpl}

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT

if [[ $REMOTE_SOURCE == *.tmpl ]]; then
  REMOTE_FILE=$TEST_TMP/50-remote.zsh
  chezmoi execute-template < "$REMOTE_SOURCE" >| "$REMOTE_FILE"
else
  REMOTE_FILE=$REMOTE_SOURCE
fi

[[ -r $REMOTE_FILE ]] || fail "cannot read remote helpers"
source "$REMOTE_FILE"

_hpc_sessions() {
  print -r -- 'tmux%|%dev%|%1%|%0%|%1%|%1%|%/tmp/dev'
  print -r -- 'zmx%|%shell%|%-%|%0%|%1%|%-%|%/tmp/shell'
}

typeset -ga SSH_COMMANDS
ssh() {
  [[ $1 == -t && $# == 3 ]] || fail "unexpected ssh arguments"
  SSH_COMMANDS+=("$3")
}

expect_missing() {
  local label=$1 expected=$2 output
  shift 2
  SSH_COMMANDS=()

  if output=$("$@" 2>&1); then
    fail "$label unexpectedly succeeded"
  fi
  [[ $output == *"$expected"* ]] ||
    fail "$label returned the wrong error: $output"
  (( ${#SSH_COMMANDS} == 0 )) ||
    fail "$label attempted to attach a missing session"
}

expect_attach() {
  local label=$1 expected=$2
  shift 2
  SSH_COMMANDS=()

  "$@"
  (( ${#SSH_COMMANDS} == 1 )) ||
    fail "$label made ${#SSH_COMMANDS} attach calls"
  [[ $SSH_COMMANDS[1] == "$expected" ]] ||
    fail "$label ran the wrong remote command: $SSH_COMMANDS[1]"
}

expect_missing 'hpc missing name' 'hpc: no tmux session named list' hpc list
expect_missing 'hpc wrong session kind' 'hpc: no tmux session named shell' hpc shell
expect_attach 'hpc existing session' 'tmux attach-session -t dev' hpc dev

expect_missing 'hpcz missing name' 'hpcz: no zmx session named list' hpcz list
expect_missing 'hpcz wrong session kind' 'hpcz: no zmx session named dev' hpcz dev
expect_attach 'hpcz existing session' '~/.local/bin/zmx attach shell' hpcz shell

print 'PASS: remote helpers only attach to existing sessions'
