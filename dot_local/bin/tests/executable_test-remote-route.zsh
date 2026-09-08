#!/usr/bin/env zsh

emulate -LR zsh
setopt errexit nounset pipe_fail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h:h}
REMOTE_SOURCE=${REMOTE_HELPERS_FILE:-$REPO_ROOT/dot_zsh/rc.d/50-remote.zsh.tmpl}
CONNECT_SOURCE=${TAILSCALE_REMOTE_CONNECT_FILE:-$REPO_ROOT/dot_local/bin/executable_tailscale-remote-connect}

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT

REMOTE_FILE=$TEST_TMP/50-remote.zsh
chezmoi execute-template < "$REMOTE_SOURCE" >| "$REMOTE_FILE"
source "$REMOTE_FILE"

TAILSCALE_LAB_EXIT_NODE=test-exit-node
TAILSCALE_REMOTE_SOCKET=$TEST_TMP/tailscaled.sock
TAILSCALE_REMOTE_SERVICE=tailscale-remote-proxy.service

typeset -gi TEST_SERVICE_ACTIVE=0
typeset -gi TEST_PROXY_EXIT=0
typeset -gi TEST_MAIN_EXIT=0
typeset -g TEST_BACKEND=NeedsLogin
typeset -ga LABROUTE_COMMANDS

_labroute_require_commands() {
  return 0
}

_labroute_service_active() {
  (( TEST_SERVICE_ACTIVE ))
}

_labroute_start_service() {
  LABROUTE_COMMANDS+=(start-service)
  TEST_SERVICE_ACTIVE=1
}

_labroute_stop_service() {
  LABROUTE_COMMANDS+=(stop-service)
  TEST_SERVICE_ACTIVE=0
}

_labroute_wait_for_socket() {
  return 0
}

_labroute_main_exit_enabled() {
  (( TEST_MAIN_EXIT ))
}

_labroute_cli() {
  local argument exit_node

  LABROUTE_COMMANDS+=("${(j: :)argv}")
  case $1 in
    status)
      if (( TEST_PROXY_EXIT )); then
        print -r -- '{"BackendState":"Running","ExitNodeStatus":{"ID":"test"}}'
      else
        printf '{"BackendState":"%s"}' "$TEST_BACKEND"
      fi
      ;;
    up)
      TEST_BACKEND=Running
      ;;
    set)
      for argument in "$@"; do
        if [[ $argument == --exit-node=* ]]; then
          exit_node=${argument#*=}
          if [[ -n $exit_node ]]; then
            TEST_PROXY_EXIT=1
          else
            TEST_PROXY_EXIT=0
          fi
        fi
      done
      ;;
    *)
      fail "unexpected labroute CLI call: ${(j: :)argv}"
      ;;
  esac
}

expect_success() {
  local label=$1 expected=$2 output
  shift 2

  if ! "$@" >| "$TEST_TMP/output" 2>&1; then
    fail "$label unexpectedly failed: $(<"$TEST_TMP/output")"
  fi
  output=$(<"$TEST_TMP/output")
  [[ $output == *"$expected"* ]] ||
    fail "$label returned the wrong output: $output"
}

expect_failure() {
  local label=$1 expected_rc=$2 expected=$3 output rc
  shift 3

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

expect_failure 'invalid action' 2 'usage: labroute' labroute sideways
expect_success 'initial status' 'Lab SSH route: OFF' labroute status

TEST_SERVICE_ACTIVE=1
TEST_BACKEND=NeedsLogin
expect_success 'authentication status' 'Lab SSH route: AUTH REQUIRED' labroute status
TEST_SERVICE_ACTIVE=0

TEST_MAIN_EXIT=1
expect_failure 'main exit conflict' 1 'main Tailscale daemon is using an exit node' labroute on
(( TEST_SERVICE_ACTIVE == 0 )) || fail 'conflict started the proxy service'
TEST_MAIN_EXIT=0

LABROUTE_COMMANDS=()
expect_success 'first activation' 'Lab SSH route: ON' labroute on
(( TEST_SERVICE_ACTIVE == 1 )) || fail 'activation did not start the service'
(( TEST_PROXY_EXIT == 1 )) || fail 'activation did not select the proxy exit node'
recorded_commands=${(j:|:)LABROUTE_COMMANDS}
[[ $recorded_commands == *'up --hostname='* ]] ||
  fail "first activation did not authenticate the proxy: $recorded_commands"
[[ $recorded_commands == *'set --accept-dns=false --accept-routes=false --exit-node=test-exit-node'* ]] ||
  fail "activation selected the wrong proxy preferences: $recorded_commands"

expect_success 'active status' 'Lab SSH route: ON' labroute status
expect_success 'active toggle' 'Lab SSH route: OFF' labroute toggle
(( TEST_SERVICE_ACTIVE == 0 )) || fail 'off toggle did not stop the service'

TEST_BACKEND=Running
LABROUTE_COMMANDS=()
expect_success 'inactive toggle' 'Lab SSH route: ON' labroute toggle
(( TEST_SERVICE_ACTIVE == 1 && TEST_PROXY_EXIT == 1 )) ||
  fail 'on toggle did not restore the proxy route'

expect_success 'explicit off' 'Lab SSH route: OFF' labroute off
expect_success 'idempotent off' 'Lab SSH route: OFF' labroute off

expect_failure 'connector missing route' 1 'run: labroute on' env TAILSCALE_REMOTE_SOCKET="$TEST_TMP/missing.sock" /bin/sh "$CONNECT_SOURCE" example.test 22
expect_failure 'connector invalid host' 2 'invalid host' env TAILSCALE_REMOTE_SOCKET="$TEST_TMP/missing.sock" /bin/sh "$CONNECT_SOURCE" 'bad;host' 22
expect_failure 'connector invalid port' 2 'invalid port' env TAILSCALE_REMOTE_SOCKET="$TEST_TMP/missing.sock" /bin/sh "$CONNECT_SOURCE" example.test 70000

zmodload zsh/net/socket || fail 'zsh/net/socket is unavailable'
TEST_SOCKET=$TEST_TMP/proxy.sock
zsocket -l "$TEST_SOCKET" || fail 'cannot create the test Unix socket'
typeset -g TEST_SOCKET_FD=$REPLY

FAKE_BIN=$TEST_TMP/bin
NC_LOG=$TEST_TMP/nc.args
mkdir -p "$FAKE_BIN"
{
  print -r -- '#!/bin/sh'
  print -r -- 'printf "%s|" "$@" > "$NC_LOG"'
} >| "$FAKE_BIN/nc"
chmod +x "$FAKE_BIN/nc"

if ! env PATH="$FAKE_BIN:$PATH" NC_LOG="$NC_LOG" TAILSCALE_REMOTE_SOCKET="$TEST_SOCKET" TAILSCALE_REMOTE_PROXY=127.0.0.1:1055 /bin/sh "$CONNECT_SOURCE" example.test 22; then
  fail 'connector did not invoke netcat through the SOCKS5 proxy'
fi

actual_args=$(<"$NC_LOG")
[[ $actual_args == '-X|5|-x|127.0.0.1:1055|example.test|22|' ]] ||
  fail "connector passed the wrong netcat arguments: ${(qqq)actual_args}"

print 'PASS: labroute isolates the exit node to the SSH SOCKS5 proxy'
