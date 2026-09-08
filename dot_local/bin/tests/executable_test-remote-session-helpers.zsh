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

typeset -g HPC_SESSIONS_MODE=success
_hpc_sessions() {
  if [[ $HPC_SESSIONS_MODE == unreachable ]]; then
    print -u2 -- 'ssh: connect to host test.invalid port 22: Connection timed out'
    return 255
  fi

  print -r -- 'tmux%|%dev%|%1%|%0%|%1%|%1%|%/tmp/dev'
  print -r -- 'zmx%|%shell%|%-%|%0%|%1%|%-%|%/tmp/shell'
}

typeset -ga SSH_COMMANDS
typeset -g SSH_MODE=success
ssh() {
  local remote_command=$argv[-1] session

  SSH_COMMANDS+=("$remote_command")

  if [[ $remote_command == *'tmux detach-client'* ]]; then
    [[ $# == 8 && $1 == -S && $2 == none &&
      $3 == -o && $4 == ConnectTimeout=8 &&
      $5 == -o && $6 == ConnectionAttempts=1 ]] ||
      fail "unexpected hpc-detach ssh arguments: ${(j: :)argv}"

    case $SSH_MODE in
      success)
        return 0
        ;;
      missing)
        print -u2 -- 'hpc-detach: no tmux session named dev'
        return 1
        ;;
      no-tmux)
        print -u2 -- 'hpc-detach: tmux is not installed on the remote host'
        return 127
        ;;
      unreachable)
        print -u2 -- 'ssh: connect to host test.invalid port 22: Connection timed out'
        return 255
        ;;
      detach-failed)
        return 23
        ;;
      *)
        fail "unknown hpc-detach ssh test mode: $SSH_MODE"
        ;;
    esac
  fi

  if [[ $remote_command == *'zmx detach'* ]]; then
    [[ $# == 8 && $1 == -S && $2 == none &&
      $3 == -o && $4 == ConnectTimeout=8 &&
      $5 == -o && $6 == ConnectionAttempts=1 ]] ||
      fail "unexpected hpcz-detach ssh arguments: ${(j: :)argv}"

    case $SSH_MODE in
      success)
        return 0
        ;;
      missing)
        print -u2 -- 'hpcz-detach: no zmx session named shell'
        return 1
        ;;
      no-zmx)
        print -u2 -- 'hpcz-detach: zmx is not installed on the remote host'
        return 127
        ;;
      unreachable)
        print -u2 -- 'ssh: connect to host test.invalid port 22: Connection timed out'
        return 255
        ;;
      detach-failed)
        return 23
        ;;
      *)
        fail "unknown hpcz-detach ssh test mode: $SSH_MODE"
        ;;
    esac
  fi

  if [[ $remote_command == *'tmux has-session'* ]]; then
    [[ $# == 9 && $1 == -S && $2 == none &&
      $3 == -o && $4 == ConnectTimeout=8 &&
      $5 == -o && $6 == ConnectionAttempts=1 && $7 == -t ]] ||
      fail "unexpected hpc ssh arguments: ${(j: :)argv}"

    case $SSH_MODE in
      success)
        return 0
        ;;
      missing)
        session=${${remote_command#*'tmux has-session -t ='}%% *}
        print -u2 -- "hpc: no tmux session named $session"
        return 1
        ;;
      no-tmux)
        print -u2 -- 'hpc: tmux is not installed on the remote host'
        return 127
        ;;
      unreachable)
        print -u2 -- 'ssh: connect to host test.invalid port 22: Connection timed out'
        return 255
        ;;
      attach-failed)
        return 23
        ;;
      *)
        fail "unknown ssh test mode: $SSH_MODE"
        ;;
    esac
  fi

  [[ $1 == -t && $# == 3 ]] || fail "unexpected ssh arguments"
}

expect_failure() {
  local label=$1 expected_rc=$2 expected=$3 output rc
  shift 3
  SSH_COMMANDS=()

  if "$@" >| "$TEST_TMP/output" 2>&1; then
    fail "$label unexpectedly succeeded"
  else
    rc=$?
  fi
  output=$(<"$TEST_TMP/output")
  (( rc == expected_rc )) ||
    fail "$label returned status $rc instead of $expected_rc: $output"
  [[ $output == *"$expected"* ]] ||
    fail "$label returned the wrong error: $output"
}

expect_ssh_command() {
  local label=$1 expected=$2
  shift 2
  SSH_COMMANDS=()

  "$@" >| "$TEST_TMP/output" 2>&1
  (( ${#SSH_COMMANDS} == 1 )) ||
    fail "$label made ${#SSH_COMMANDS} ssh calls"
  [[ $SSH_COMMANDS[1] == *"$expected"* ]] ||
    fail "$label ran the wrong remote command: $SSH_COMMANDS[1]"
}

if ! hpc >| "$TEST_TMP/output" 2>&1; then
  fail "bare hpc unexpectedly failed: $(<"$TEST_TMP/output")"
fi
output=$(<"$TEST_TMP/output")
[[ $output == *'hpc: connecting to remote host to list sessions...'* ]] ||
  fail "bare hpc omitted its connecting message: $output"
[[ $output == *'tmux  dev'* ]] ||
  fail "bare hpc omitted its session listing: $output"

HPC_SESSIONS_MODE=unreachable
expect_failure 'bare hpc unreachable host' 255 'hpc: connecting to remote host to list sessions...' hpc
output=$(<"$TEST_TMP/output")
[[ $output == *'ssh: connect to host test.invalid'* ]] ||
  fail "bare hpc swallowed the SSH diagnostic: $output"
[[ $output == *'hpc: SSH connection to the remote host failed'* ]] ||
  fail "bare hpc omitted its connection failure summary: $output"
HPC_SESSIONS_MODE=success

SSH_MODE=missing
expect_failure 'hpc missing name' 1 'hpc: no tmux session named list' hpc list
(( ${#SSH_COMMANDS} == 1 )) || fail 'hpc missing name did not use exactly one ssh call'
expect_failure 'hpc wrong session kind' 1 'hpc: no tmux session named shell' hpc shell

SSH_MODE=success
expect_ssh_command 'hpc existing session' 'exec tmux attach-session -t =dev' hpc dev
output=$(<"$TEST_TMP/output")
[[ $output == *"hpc: connecting to remote host for tmux session 'dev'..."* ]] ||
  fail "hpc omitted its connecting message: $output"
[[ $SSH_COMMANDS[1] == *'tmux has-session -t =dev'* ]] ||
  fail "hpc did not check the exact session in its attach call: $SSH_COMMANDS[1]"
[[ $SSH_COMMANDS[1] == *"hpc: connected; attaching to tmux session 'dev'..."* ]] ||
  fail "hpc attach call omitted the connected message: $SSH_COMMANDS[1]"
sh -n -c "$SSH_COMMANDS[1]" ||
  fail "hpc generated invalid remote shell code: $SSH_COMMANDS[1]"

SSH_MODE=no-tmux
expect_failure 'hpc missing remote tmux' 127 'hpc: tmux is not installed on the remote host' hpc dev

SSH_MODE=unreachable
expect_failure 'hpc unreachable host' 255 'ssh: connect to host test.invalid' hpc dev
output=$(<"$TEST_TMP/output")
[[ $output == *'hpc: SSH connection to the remote host failed'* ]] ||
  fail "hpc omitted its connection failure summary: $output"

SSH_MODE=attach-failed
expect_failure 'hpc attach failure' 23 "hpc: remote attach failed for tmux session 'dev' (status 23)" hpc dev

SSH_MODE=success
expect_failure 'hpc-detach missing argument' 2 'usage: hpc-detach <session-name>' hpc-detach
expect_failure 'hpc-detach invalid name' 2 'usage: hpc-detach <session-name>' hpc-detach 'bad/name'
expect_ssh_command 'hpc-detach existing session' "tmux detach-client -s '=dev'" hpc-detach dev
[[ $SSH_COMMANDS[1] == *"tmux has-session -t '=dev'"* ]] ||
  fail "hpc-detach did not check the exact session: $SSH_COMMANDS[1]"
sh -n -c "$SSH_COMMANDS[1]" ||
  fail "hpc-detach generated invalid remote shell code: $SSH_COMMANDS[1]"

SSH_MODE=missing
expect_failure 'hpc-detach missing session' 1 'hpc-detach: no tmux session named dev' hpc-detach dev
SSH_MODE=no-tmux
expect_failure 'hpc-detach missing remote tmux' 127 'hpc-detach: tmux is not installed on the remote host' hpc-detach dev
SSH_MODE=unreachable
expect_failure 'hpc-detach unreachable host' 255 'hpc-detach: SSH connection to the remote host failed' hpc-detach dev
SSH_MODE=detach-failed
expect_failure 'hpc-detach remote failure' 23 "hpc-detach: remote detach failed for tmux session 'dev' (status 23)" hpc-detach dev

SSH_MODE=success
expect_failure 'hpcz missing name' 1 'hpcz: no zmx session named list' hpcz list
expect_failure 'hpcz wrong session kind' 1 'hpcz: no zmx session named dev' hpcz dev
expect_ssh_command 'hpcz existing session' '~/.local/bin/zmx attach shell' hpcz shell

expect_failure 'hpcz-detach missing argument' 2 'usage: hpcz-detach <session-name>' hpcz-detach
expect_failure 'hpcz-detach invalid name' 2 'usage: hpcz-detach <session-name>' hpcz-detach 'bad/name'
expect_ssh_command 'hpcz-detach existing session' "env ZMX_SESSION='shell' ~/.local/bin/zmx detach" hpcz-detach shell
[[ $SSH_COMMANDS[1] == *"name=shell([[:space:]]|$)"* ]] ||
  fail "hpcz-detach did not check the exact session: $SSH_COMMANDS[1]"
sh -n -c "$SSH_COMMANDS[1]" ||
  fail "hpcz-detach generated invalid remote shell code: $SSH_COMMANDS[1]"

SSH_MODE=missing
expect_failure 'hpcz-detach missing session' 1 'hpcz-detach: no zmx session named shell' hpcz-detach shell
SSH_MODE=no-zmx
expect_failure 'hpcz-detach missing remote zmx' 127 'hpcz-detach: zmx is not installed on the remote host' hpcz-detach shell
SSH_MODE=unreachable
expect_failure 'hpcz-detach unreachable host' 255 'hpcz-detach: SSH connection to the remote host failed' hpcz-detach shell
SSH_MODE=detach-failed
expect_failure 'hpcz-detach remote failure' 23 "hpcz-detach: remote detach failed for zmx session 'shell' (status 23)" hpcz-detach shell

print 'PASS: remote helpers report connection failures and attach or detach only existing sessions'
