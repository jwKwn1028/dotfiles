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
# Never touch a real tmux pane or X display.
unset TMUX TMUX_PANE DISPLAY WINDOWID

typeset -g HPC_SESSIONS_MODE=success
typeset -g ZMX_CLIENTS=0
_hpc_sessions() {
  if [[ $HPC_SESSIONS_MODE == unreachable ]]; then
    print -u2 -- 'ssh: connect to host test.invalid port 22: Connection timed out'
    return 255
  fi

  print -r -- 'tmux%|%dev%|%1%|%0%|%1%|%1%|%/tmp/dev'
  print -r -- "zmx%|%shell%|%-%|%$ZMX_CLIENTS%|%1%|%-%|%/tmp/shell"
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

  if [[ $remote_command == *'zmx kill'* ]]; then
    [[ $# == 2 ]] || fail "unexpected hpcz-kill ssh arguments: ${(j: :)argv}"

    case $SSH_MODE in
      success)
        return 0
        ;;
      unreachable)
        print -u2 -- 'ssh: connect to host test.invalid port 22: Connection timed out'
        return 255
        ;;
      kill-failed)
        print -u2 -- 'hpcz-kill: remote kill failed'
        return 23
        ;;
      *)
        fail "unknown hpcz-kill ssh test mode: $SSH_MODE"
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

# The remote prelude prefers ~/.local/bin/tmux and falls back to PATH.
mkdir -p "$TEST_TMP/home/.local/bin" "$TEST_TMP/global"
print -rl -- '#!/bin/sh' 'echo "local $1"' >| "$TEST_TMP/home/.local/bin/tmux"
print -rl -- '#!/bin/sh' 'echo "global $1"' >| "$TEST_TMP/global/tmux"
chmod +x "$TEST_TMP/home/.local/bin/tmux" "$TEST_TMP/global/tmux"
output=$(HOME=$TEST_TMP/home PATH=$TEST_TMP/global:/usr/bin:/bin sh -c "$SSH_COMMANDS[1]" 2>/dev/null)
[[ $output == $'local has-session\nlocal attach-session' ]] ||
  fail "hpc did not prefer ~/.local/bin/tmux: $output"
rm -- "$TEST_TMP/home/.local/bin/tmux"
output=$(HOME=$TEST_TMP/home PATH=$TEST_TMP/global:/usr/bin:/bin sh -c "$SSH_COMMANDS[1]" 2>/dev/null)
[[ $output == $'global has-session\nglobal attach-session' ]] ||
  fail "hpc did not fall back to the global tmux: $output"

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

SSH_MODE=success
expect_failure 'hpcz-kill missing argument' 2 'usage: hpcz-kill [-f] <session-name>' hpcz-kill
expect_failure 'hpcz-kill invalid name' 2 'usage: hpcz-kill [-f] <session-name>' hpcz-kill 'bad/name'
expect_failure 'hpcz-kill missing session' 1 'hpcz-kill: no zmx session named missing' hpcz-kill missing

ZMX_CLIENTS=unknown
expect_failure 'hpcz-kill invalid client count' 1 'cannot read client count for shell' hpcz-kill shell

ZMX_CLIENTS=2
expect_failure 'hpcz-kill attached clients' 1 'shell has 2 client(s) attached' hpcz-kill shell
expect_ssh_command 'hpcz-kill forced session' '~/.local/bin/zmx kill shell --force' hpcz-kill -f shell

ZMX_CLIENTS=0
expect_ssh_command 'hpcz-kill idle session' '~/.local/bin/zmx kill shell && ~/.local/bin/zmx list' hpcz-kill shell

HPC_SESSIONS_MODE=unreachable
expect_failure 'hpcz-kill unreachable host' 255 'ssh: connect to host test.invalid' hpcz-kill shell
HPC_SESSIONS_MODE=success

# A restored Ghostty window's first shell reattaches its saved session once.
TAILSCALE_REMOTE_MODE_FILE=$TEST_TMP/proxy-required
autoload -Uz add-zsh-hook
SSH_MODE=success
I3_RESURRECT_REMOTE_SESSION=tmux:dev
add-zsh-hook precmd _hpc_restore_session
expect_ssh_command 'restored tmux session' 'exec tmux attach-session -t =dev' _hpc_restore_session
[[ -z ${I3_RESURRECT_REMOTE_SESSION-} ]] ||
  fail 'restore hook left its session request set'
[[ " ${precmd_functions-} " != *' _hpc_restore_session '* ]] ||
  fail 'restore hook stayed registered after running'

I3_RESURRECT_REMOTE_SESSION=zmx:shell
expect_ssh_command 'restored zmx session' '~/.local/bin/zmx attach shell' _hpc_restore_session

SSH_COMMANDS=()
I3_RESURRECT_REMOTE_SESSION=bogus:dev
_hpc_restore_session >| "$TEST_TMP/output" 2>&1
(( ${#SSH_COMMANDS} == 0 )) || fail 'restore hook acted on an unknown session kind'

# hpc and the restore hook wait for labroute-restore.sh.
zmodload zsh/datetime
saved_runtime=${XDG_RUNTIME_DIR-}
XDG_RUNTIME_DIR=$TEST_TMP/runtime
mkdir -p "$XDG_RUNTIME_DIR"
route_lock=$XDG_RUNTIME_DIR/i3-resurrect-labroute.lock
flock "$route_lock" sleep 1 &
route_holder=$!
for _ in {1..40}; do flock -n "$route_lock" true 2>/dev/null || break; sleep 0.05; done
I3_RESURRECT_REMOTE_SESSION=tmux:dev
route_start=$EPOCHREALTIME
expect_ssh_command 'restored session after the lab route' 'exec tmux attach-session -t =dev' _hpc_restore_session
(( EPOCHREALTIME - route_start >= 0.5 )) || fail 'restore hook did not wait for the lab route'
grep -q 'Waiting for the lab route' "$TEST_TMP/output" || fail 'restore hook did not say it waits for the lab route'
wait $route_holder
flock "$route_lock" sleep 1 &
route_holder=$!
for _ in {1..40}; do flock -n "$route_lock" true 2>/dev/null || break; sleep 0.05; done
route_start=$EPOCHREALTIME
expect_ssh_command 'hpc typed while the lab route comes up' 'exec tmux attach-session -t =dev' hpc dev
(( EPOCHREALTIME - route_start >= 0.5 )) || fail 'hpc did not wait for the lab route'
wait $route_holder

# A required route that is down refuses direct SSH.
saved_proxy_enabled=$functions[_labroute_proxy_enabled]
_labroute_proxy_enabled() { return 1 }
: >| "$TAILSCALE_REMOTE_MODE_FILE"
SSH_COMMANDS=()
I3_RESURRECT_REMOTE_SESSION=zmx:shell
_hpc_restore_session >| "$TEST_TMP/output" 2>&1
(( ${#SSH_COMMANDS} == 0 )) || fail 'restore hook connected while the required lab route was down'
grep -q 'then hpcz shell' "$TEST_TMP/output" ||
  fail "restore hook did not say how to reattach: $(<"$TEST_TMP/output")"
expect_failure 'hpc with the required lab route down' 255 'run labroute on (or labroute off for direct SSH), then hpc dev' hpc dev
(( ${#SSH_COMMANDS} == 0 )) || fail 'hpc connected while the required lab route was down'
rm -f "$TAILSCALE_REMOTE_MODE_FILE"
functions[_labroute_proxy_enabled]=$saved_proxy_enabled
XDG_RUNTIME_DIR=$saved_runtime

# Local tmux bar re-check after hpc and typed ssh.
mkdir -p "$TEST_TMP/fakebin"
print -r -- '#!/bin/sh
printf "%s\n" "tmux $*" >> "$TMUX_LOG"' >| "$TEST_TMP/fakebin/tmux"
chmod +x "$TEST_TMP/fakebin/tmux"
export TMUX_LOG=$TEST_TMP/tmux.log
recheck='tmux set-hook -R -t %9 session-window-changed'
for SSH_MODE in success unreachable; do
  : >| "$TMUX_LOG"
  (
    export TMUX=/tmp/tmux-test/default,1,0 TMUX_PANE=%9
    PATH=$TEST_TMP/fakebin:$PATH
    functions[_test_ssh]=$functions[ssh]
    ssh() { print -r -- ssh >> "$TMUX_LOG"; _test_ssh "$@"; }
    hpc dev
  ) >| "$TEST_TMP/output" 2>&1 || true
  [[ $(<"$TMUX_LOG") == ssh$'\n'"$recheck" ]] ||
    fail "hpc ($SSH_MODE) did not re-check the local tmux bar after ssh: $(<"$TMUX_LOG")"
done
SSH_MODE=success
: >| "$TMUX_LOG"
(
  export TMUX=/tmp/tmux-test/default,1,0 TMUX_PANE=%9
  PATH=$TEST_TMP/fakebin:$PATH
  _hpc_local_bar_preexec 'ls -la'; _hpc_local_bar_precmd
  print -r -- after-ls >> "$TMUX_LOG"
  _hpc_local_bar_preexec 'ssh -t host tmux attach'; _hpc_local_bar_precmd; _hpc_local_bar_precmd
)
[[ $(<"$TMUX_LOG") == after-ls$'\n'"$recheck" ]] ||
  fail "typed commands re-checked the local tmux bar wrongly: $(<"$TMUX_LOG")"
: >| "$TMUX_LOG"
( PATH=$TEST_TMP/fakebin:$PATH; hpc dev; _hpc_local_bar_preexec 'ssh host'; _hpc_local_bar_precmd ) >| "$TEST_TMP/output" 2>&1
[[ ! -s $TMUX_LOG ]] || fail "helpers outside tmux ran tmux: $(<"$TMUX_LOG")"

# Ghostty tmux mode around hpc and typed attaches.
print -r -- '#!/bin/sh
[ "$1" = getactivewindow ] && printf "%s\n" "$FAKE_ACTIVE"' >| "$TEST_TMP/fakebin/xdotool"
print -r -- '#!/bin/sh
printf "%s\n" "ghostty-tmux-mode $*" >> "$TMUX_LOG"' >| "$TEST_TMP/fakebin/ghostty-tmux-mode"
print -r -- '#!/bin/sh
if [ "$2" = "$FAKE_GHOSTTY" ]; then
  echo "WM_CLASS(STRING) = \"ghostty\", \"com.mitchellh.ghostty\""
else
  echo "WM_CLASS(STRING) = \"org.pwmt.zathura\", \"Zathura\""
fi' >| "$TEST_TMP/fakebin/xprop"
chmod +x "$TEST_TMP/fakebin/xdotool" "$TEST_TMP/fakebin/xprop" "$TEST_TMP/fakebin/ghostty-tmux-mode"
on='ghostty-tmux-mode on'
off='ghostty-tmux-mode off'
recheck_pane='tmux set-hook -R -t %9 session-window-changed'
expect_keys() {
  local label=$1 expected=$2 code=$3
  : >| "$TMUX_LOG"
  (
    PATH=$TEST_TMP/fakebin:$PATH
    export DISPLAY=:999 FAKE_GHOSTTY=300
    functions[_test_ssh]=$functions[ssh]
    ssh() { print -r -- ssh >> "$TMUX_LOG"; _test_ssh "$@"; }
    eval "$code"
  ) >| "$TEST_TMP/output" 2>&1 || true
  [[ $(<"$TMUX_LOG") == "$expected" ]] ||
    fail "$label pressed the wrong tmux-mode keys: [$(<"$TMUX_LOG")], expected [$expected]"
}
here='export WINDOWID=100 FAKE_ACTIVE=100'
for SSH_MODE in success unreachable; do
  expect_keys "hpc ($SSH_MODE) in its focused Ghostty window" "$on"$'\n'ssh$'\n'"$off" "$here; hpc dev"
done
SSH_MODE=success
expect_keys 'hpc while another window has focus' ssh 'export WINDOWID=100 FAKE_ACTIVE=200; hpc dev'
expect_keys 'hpc outside Ghostty (no WINDOWID)' ssh 'export FAKE_ACTIVE=300; hpc dev'
expect_keys 'hpc without an X display' ssh "unset DISPLAY; $here; hpc dev"
expect_keys 'hpc inside tmux in a focused Ghostty window' "$on"$'\n'ssh$'\n'"$recheck_pane" \
  'export TMUX=/tmp/t,1,0 TMUX_PANE=%9 WINDOWID=1 FAKE_ACTIVE=300; hpc dev'
expect_keys 'hpc inside tmux while another app has focus' ssh$'\n'"$recheck_pane" \
  'export TMUX=/tmp/t,1,0 TMUX_PANE=%9 FAKE_ACTIVE=400; hpc dev'
for typed in 'tmux' 'tmux a' 'tmux attach -t dev' 'tmux -L work new -s x' "ssh host 'tmux attach -t dev'" 'ssh -t host tmux'; do
  expect_keys "typed: $typed" "$on"$'\n'"$off" \
    "$here; _ghostty_tmux_mode_preexec ${(q)typed}; _ghostty_tmux_mode_precmd; _ghostty_tmux_mode_precmd"
done
for typed in 'tmux ls' 'tmux new -d -s x' 'tmux kill-server' 'ssh host cat .tmux.conf' 'ssh host' 'ls -la'; do
  expect_keys "typed: $typed" '' "$here; _ghostty_tmux_mode_preexec ${(q)typed}; _ghostty_tmux_mode_precmd"
done
expect_keys 'typed tmux attach inside tmux' "$on" \
  "export TMUX=/tmp/t,1,0 TMUX_PANE=%9 FAKE_ACTIVE=300; _ghostty_tmux_mode_preexec 'tmux a'; _ghostty_tmux_mode_precmd"

print 'PASS: remote helpers report connection failures, act only on existing sessions, and reattach restored ones'
