#!/usr/bin/env zsh

# Sources the cleaner directly with ZSH_HISTORY_CLEANER_INTERNAL=1 to skip its
# re-entry into an interactive login shell, then runs one case through the real
# entry point. `zsh -fi` keeps command resolution deterministic; -i is required
# because the cleaner relies on $history hiding the newest event.

emulate -LR zsh
setopt errexit nounset pipe_fail

SCRIPT_DIR=${0:A:h}
REPO_ROOT=${SCRIPT_DIR:h:h:h}
CLEANER=$REPO_ROOT/private_executable_dot_clean-zsh-history.zsh
[[ -r $CLEANER ]] || CLEANER=$HOME/.clean-zsh-history.zsh

fail() {
  print -u2 -- "FAIL: $1"
  exit 1
}

[[ -r $CLEANER ]] || fail "cannot read the cleaner script"

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p -- "$TEST_TMP/config/zsh-history-cleaner"

# Pin the names these fixtures rely on: `zsh -f` sees no conda or venv, so
# `python` would otherwise be dropped as unresolved and hide what is on trial.
cat >| "$TEST_TMP/config/zsh-history-cleaner/keep" <<'KEEP'
# comment, ignored
python
huggingface-cli   # trailing comment, ignored

KEEP

write_history() {
  local target=$1
  shift
  print -rl -- "$@" >| "$target"
}

run_cleaner() {
  local hist=$1
  shift
  ZSH_HISTORY_CLEANER_INTERNAL=1 \
  ZSH_HISTORY_CLEANER_OUTPUT_FD=1 \
  XDG_CONFIG_HOME=$TEST_TMP/config \
    zsh -fi -c 'cleaner=$1; shift; source "$cleaner" "$@"' \
      cleaner-test "$CLEANER" "$hist" "$@" 2>&1
}

assert_kept() {
  local hist=$1 needle=$2 label=$3
  grep -qxF -- "$needle" "$hist" || fail "$label: dropped '$needle'"
}

assert_dropped() {
  local hist=$1 needle=$2 label=$3
  grep -qxF -- "$needle" "$hist" && fail "$label: kept '$needle'"
  return 0
}

assert_absent() {
  local file=$1 needle=$2 label=$3
  grep -qF -- "$needle" "$file" && fail "$label: found '$needle' in ${file:t}"
  return 0
}

# --- Credential-carrying entries ------------------------------------------
# The vendor-prefixed forms all passed the old alternation, which only matched
# access_token / auth_token. HF_TOKEN sat in the live history for three weeks.

hist=$TEST_TMP/secrets
write_history "$hist" \
  'export HF_TOKEN="hf_examplefixturevaluenotarealtoken"' \
  'export GITHUB_TOKEN=abc' \
  'GH_TOKEN=abc git push' \
  'export NPM_TOKEN=abc' \
  'export OPENAI_API_KEY=sk-proj-abcdefghijklmnopqrstuvwxyz' \
  'export AWS_SECRET_ACCESS_KEY=x' \
  'mypassword=hunter2' \
  'passphrase=abc' \
  'echo github_pat_notarealtokenfixture1234567890' \
  'echo ghs_123456_notarealtokenfixture.1234567890' \
  'huggingface-cli login --token hf_abcdefghijklmnopqrstuvwxyz12' \
  'curl -H "Authorization: Bearer ghp_abcdefghijklmnopqrstuvwx"' \
  'git status'
run_cleaner "$hist" >/dev/null

for leaked in 'hf_examplefixturevaluenotarealtoken' GITHUB_TOKEN GH_TOKEN NPM_TOKEN \
              OPENAI_API_KEY AWS_SECRET_ACCESS_KEY mypassword passphrase \
              'github_pat_notarealtokenfixture1234567890' \
              'ghs_123456_notarealtokenfixture.1234567890' \
              'hf_abcdefghijklmnopqrstuvwxyz12' 'ghp_abcdefghijklmnopqrstuvwx'; do
  grep -qF -- "$leaked" "$hist" && fail "credential survived cleaning: $leaked"
done
assert_kept "$hist" 'git status' 'credentials'

# --- Names that merely contain a credential word --------------------------
# Dropping these would cost real ML commands; `token` must break on _ or -.

hist=$TEST_TMP/benign
write_history "$hist" \
  'tokenizers_parallelism=false uv run train.py' \
  'python train.py --max_tokens=512' \
  'export HF_HOME=/tmp/hf' \
  'export TOKENIZER_DIR=/tmp/tok' \
  'git commit -m "add token parser"' \
  'grep -r token src/'
run_cleaner "$hist" >/dev/null

assert_kept "$hist" 'tokenizers_parallelism=false uv run train.py' 'benign'
assert_kept "$hist" 'python train.py --max_tokens=512' 'benign'
assert_kept "$hist" 'export HF_HOME=/tmp/hf' 'benign'
assert_kept "$hist" 'export TOKENIZER_DIR=/tmp/tok' 'benign'
assert_kept "$hist" 'git commit -m "add token parser"' 'benign'
assert_kept "$hist" 'grep -r token src/' 'benign'

# --- Words the sensitive-value glob gate must not miss --------------------
# is_sensitive screens with a case-insensitive glob before running its regexes,
# so the glob has to stay a superset of every word those regexes can match.
# One missing alternative here is a silently disabled credential rule.

hist=$TEST_TMP/gate
write_history "$hist" \
  'CREDENTIAL_FILE=/tmp/c' \
  'MYSECRET=x' \
  'curl --password hunter2 https://example.invalid' \
  'echo AKIAIOSFODNN7EXAMPLE' \
  'echo xoxb-1234567890-abcdefghij' \
  'echo sk-abcdefghijklmnopqrstuvwxyz' \
  'git status'
run_cleaner "$hist" >/dev/null

for gated in CREDENTIAL_FILE MYSECRET hunter2 AKIAIOSFODNN7EXAMPLE \
             xoxb-1234567890-abcdefghij sk-abcdefghijklmnopqrstuvwxyz; do
  grep -qF -- "$gated" "$hist" && fail "gate: '$gated' slipped past the glob"
done
assert_kept "$hist" 'git status' 'gate'

# --- The pushed history context never reaches disk ------------------------
# fc -p's savehist argument must stay 0. cleanup() pops the context before it
# removes the file, so any other value writes the uncleaned history out first.
# Shim rm rather than delete, and read back what cleanup was about to destroy.

hist=$TEST_TMP/context-leak
write_history "$hist" 'export HF_TOKEN=hf_abcdefghijklmnopqrstuvwxyz12' 'git status'
LEAK_DIR=$TEST_TMP/leaked
mkdir -p -- "$LEAK_DIR/context" "$LEAK_DIR/snapshot" "$TEST_TMP/rmshim"
cat >| "$TEST_TMP/rmshim/rm" <<SHIM
#!/bin/sh
for arg in "\$@"; do
  case \$arg in
    *.context.*)  [ -f "\$arg" ] && cp -p -- "\$arg" "$LEAK_DIR/context/" ;;
    *.snapshot.*) [ -f "\$arg" ] && cp -p -- "\$arg" "$LEAK_DIR/snapshot/" ;;
  esac
done
exec $(command -v -- rm) "\$@"
SHIM
chmod +x -- "$TEST_TMP/rmshim/rm"
(
  export PATH=$TEST_TMP/rmshim:$PATH
  run_cleaner "$hist" >/dev/null
)
# The snapshot is expected to hold the credential; catching it proves the shim
# ran, so an empty context/ below means the context was never written, not that
# the check quietly stopped looking. Both temp names begin with a dot.
shim_ran=( $LEAK_DIR/snapshot/*(N.D) )
(( $#shim_ran )) || fail "context: the rm shim never ran, so the check is vacuous"
for leaked in $LEAK_DIR/context/*(N.D); do
  assert_absent "$leaked" 'hf_abcdefghijklmnopqrstuvwxyz12' 'context'
done
assert_dropped "$hist" 'export HF_TOKEN=hf_abcdefghijklmnopqrstuvwxyz12' 'context'

# --- Wrapper commands -----------------------------------------------------
# Only words[1] used to be resolved, so `sudo renoot` outlived every pass.
# An option after the wrapper means the next word may be its argument, not a
# command, so those entries are left alone.

hist=$TEST_TMP/wrappers
write_history "$hist" \
  'sudo renoot' \
  'env definitelynotacommand' \
  'command nosuchbinary --flag' \
  'sudo ls -la' \
  'sudo -u postgres definitelynotacommand' \
  'builtin cd /tmp' \
  'FOO=1 sudo grep x /etc/hosts'
run_cleaner "$hist" >/dev/null

assert_dropped "$hist" 'sudo renoot' 'wrappers'
assert_dropped "$hist" 'env definitelynotacommand' 'wrappers'
assert_dropped "$hist" 'command nosuchbinary --flag' 'wrappers'
assert_kept "$hist" 'sudo ls -la' 'wrappers'
assert_kept "$hist" 'sudo -u postgres definitelynotacommand' 'wrappers'
assert_kept "$hist" 'builtin cd /tmp' 'wrappers'
assert_kept "$hist" 'FOO=1 sudo grep x /etc/hosts' 'wrappers'

# --- Raw record preservation ----------------------------------------------
# Replaying with `print -s` would restamp these and fuse the continuation.

hist=$TEST_TMP/records
{
  print -r -- ': 1756400000:0;git status'
  print -r -- ': 1756400001:2;echo one\'
  print -r -- 'two'
  print -r -- ': 1756400002:0;git status'
} >| "$hist"
run_cleaner "$hist" >/dev/null

grep -qxF -- ': 1756400001:2;echo one\' "$hist" ||
  fail "records: continuation record lost its timestamp or trailing backslash"
grep -qxF -- 'two' "$hist" || fail "records: continuation line was dropped"
grep -qxF -- ': 1756400002:0;git status' "$hist" ||
  fail "records: newest duplicate should survive with its own timestamp"
grep -qxF -- ': 1756400000:0;git status' "$hist" &&
  fail "records: older duplicate should have been dropped"

# --- Entries appended by another shell while the cleaner runs --------------
# Refusing the whole run discarded them; they are now carried over, but still
# screened for credentials. chmod is the cleaner's last call before its final
# hash check, which makes it the injection point.

hist=$TEST_TMP/raced
write_history "$hist" 'git status' 'definitelynotacommand'
merge_output=$(
  ZSH_HISTORY_CLEANER_INTERNAL=1 \
  ZSH_HISTORY_CLEANER_OUTPUT_FD=1 \
  XDG_CONFIG_HOME=$TEST_TMP/config \
    zsh -fi -c '
      cleaner=$1; hist=$2
      chmod() {
        command chmod "$@" || return
        unfunction chmod
        print -rl -- "echo raced-in" "export GH_TOKEN=leaked" >> $hist
      }
      source "$cleaner" "$hist"
    ' cleaner-test "$CLEANER" "$hist" 2>&1
)

[[ $merge_output == *'Merged: 1 record(s)'* ]] ||
  fail "merge: expected one carried-over record, got: $merge_output"
assert_kept "$hist" 'git status' 'merge'
assert_kept "$hist" 'echo raced-in' 'merge'
assert_dropped "$hist" 'export GH_TOKEN=leaked' 'merge'
assert_dropped "$hist" 'definitelynotacommand' 'merge'

# A history record can occupy several physical lines. Filter the whole record,
# or dropping only its sensitive continuation leaves the opening backslash to
# consume the next, unrelated history entry.
hist=$TEST_TMP/raced-multiline
write_history "$hist" 'git status'
merge_output=$(
  ZSH_HISTORY_CLEANER_INTERNAL=1 \
  ZSH_HISTORY_CLEANER_OUTPUT_FD=1 \
  XDG_CONFIG_HOME=$TEST_TMP/config \
    zsh -fi -c '
      cleaner=$1; hist=$2
      chmod() {
        command chmod "$@" || return
        unfunction chmod
        print -r -- ": 1756400001:0;curl https://example.invalid \\" >> $hist
        print -r -- "  -H Authorization: Bearer ghp_abcdefghijklmnopqrstuvwx" >> $hist
        print -r -- ": 1756400002:0;echo next-entry" >> $hist
      }
      source "$cleaner" "$hist"
    ' cleaner-test "$CLEANER" "$hist" 2>&1
)

[[ $merge_output == *'Merged: 1 record(s)'* ]] ||
  fail "multiline merge: expected one carried-over record, got: $merge_output"
assert_dropped "$hist" ': 1756400001:0;curl https://example.invalid \' 'multiline merge'
assert_dropped "$hist" '  -H Authorization: Bearer ghp_abcdefghijklmnopqrstuvwx' 'multiline merge'
assert_kept "$hist" ': 1756400002:0;echo next-entry' 'multiline merge'

validation_output=$(run_cleaner "$hist" --dry-run)
[[ $validation_output == *'Entries: 2 -> 2'* ]] ||
  fail "multiline merge: output is not two intact records: $validation_output"

# If another shell has only written the opening line, leave its append and the
# original history untouched so a later run can see the completed record.
hist=$TEST_TMP/raced-incomplete
write_history "$hist" 'git status'
incomplete_status=0
incomplete_output=$(
  ZSH_HISTORY_CLEANER_INTERNAL=1 \
  ZSH_HISTORY_CLEANER_OUTPUT_FD=1 \
  XDG_CONFIG_HOME=$TEST_TMP/config \
    zsh -fi -c '
      cleaner=$1; hist=$2
      chmod() {
        command chmod "$@" || return
        unfunction chmod
        print -r -- ": 1756400003:0;echo unfinished \\" >> $hist
      }
      source "$cleaner" "$hist"
    ' cleaner-test "$CLEANER" "$hist" 2>&1
) || incomplete_status=$?

(( incomplete_status != 0 )) || fail "incomplete merge: cleaner should have refused"
[[ $incomplete_output == *'append ended mid-record'* ]] ||
  fail "incomplete merge: unexpected message: $incomplete_output"
assert_kept "$hist" 'git status' 'incomplete merge'
assert_kept "$hist" ': 1756400003:0;echo unfinished \' 'incomplete merge'

# --- A rewrite, as opposed to an append, is still refused ------------------

hist=$TEST_TMP/rewritten
write_history "$hist" 'git status' 'definitelynotacommand'
rewrite_status=0
rewrite_output=$(
  ZSH_HISTORY_CLEANER_INTERNAL=1 \
  ZSH_HISTORY_CLEANER_OUTPUT_FD=1 \
  XDG_CONFIG_HOME=$TEST_TMP/config \
    zsh -fi -c '
      cleaner=$1; hist=$2
      chmod() {
        command chmod "$@" || return
        unfunction chmod
        print -r -- "totally different" >| $hist
      }
      source "$cleaner" "$hist"
    ' cleaner-test "$CLEANER" "$hist" 2>&1
) || rewrite_status=$?

(( rewrite_status != 0 )) || fail "rewrite: cleaner should have refused"
[[ $rewrite_output == *'rewritten during cleanup'* ]] ||
  fail "rewrite: unexpected message: $rewrite_output"
[[ $(<"$hist") == 'totally different' ]] ||
  fail "rewrite: the concurrent write was clobbered"

# --- Backup retention -----------------------------------------------------
# Backups keep every credential the live history just lost, so they cannot
# accumulate unbounded.

hist=$TEST_TMP/backups
write_history "$hist" 'git status'
for stamp in 01 02 03 04 05 06 07; do
  : >| "${hist}.pre-autocomplete-cleanup-202601${stamp}-000000"
  touch -t "202601${stamp}0000" -- "${hist}.pre-autocomplete-cleanup-202601${stamp}-000000"
done
run_cleaner "$hist" >/dev/null

backups=( ${hist}.pre-autocomplete-cleanup-*(N.) )
(( $#backups == 5 )) ||
  fail "backups: expected 5 retained, found $#backups"
[[ -e ${hist}.pre-autocomplete-cleanup-20260101-000000 ]] &&
  fail "backups: pruned the newest instead of the oldest"

hist=$TEST_TMP/backups-env
write_history "$hist" 'git status'
for stamp in 01 02 03 04; do
  : >| "${hist}.pre-autocomplete-cleanup-202601${stamp}-000000"
  touch -t "202601${stamp}0000" -- "${hist}.pre-autocomplete-cleanup-202601${stamp}-000000"
done
ZSH_HISTORY_CLEANER_KEEP_BACKUPS=2 run_cleaner "$hist" >/dev/null
backups=( ${hist}.pre-autocomplete-cleanup-*(N.) )
(( $#backups == 2 )) ||
  fail "backups: ZSH_HISTORY_CLEANER_KEEP_BACKUPS=2 left $#backups"

# --- Dry run leaves everything alone --------------------------------------

hist=$TEST_TMP/dry
write_history "$hist" 'git status' 'definitelynotacommand'
before=$(<"$hist")
dry_output=$(run_cleaner "$hist" --dry-run)
[[ $(<"$hist") == "$before" ]] || fail "dry-run: history was modified"
[[ $dry_output == *'Dry run: no files changed.'* ]] ||
  fail "dry-run: missing report line"
backups=( ${hist}.pre-autocomplete-cleanup-*(N.) )
(( $#backups == 0 )) || fail "dry-run: created a backup"

# --- Refusals -------------------------------------------------------------

refuse_status=0
run_cleaner "$CLEANER" >/dev/null 2>&1 || refuse_status=$?
(( refuse_status != 0 )) || fail "cleaner agreed to clean a script"

refuse_status=0
run_cleaner "$TEST_TMP/does-not-exist" >/dev/null 2>&1 || refuse_status=$?
(( refuse_status != 0 )) || fail "cleaner accepted a missing history file"

# A second file after `--` used to overwrite the one given before it.
refuse_status=0
refuse_output=$(run_cleaner "$TEST_TMP/dry" -- "$TEST_TMP/dry" 2>&1) || refuse_status=$?
(( refuse_status != 0 )) || fail "cleaner accepted two history files"
[[ $refuse_output == *'at most one history file'* ]] ||
  fail "two files: unexpected message: $refuse_output"

# cleanup() and backup pruning both shell out to rm, so the guard must list it.
zsh_bin=$(command -v -- zsh) || fail "cannot locate zsh"
stub_bin=$TEST_TMP/stub-bin
mkdir -p -- "$stub_bin"
for tool in cp mktemp mv chmod head tail sha256sum shasum; do
  tool_path=$(command -v -- $tool) && ln -sf -- "$tool_path" "$stub_bin/$tool"
done
hist=$TEST_TMP/no-rm
write_history "$hist" 'git status'
refuse_status=0
refuse_output=$(
  ZSH_HISTORY_CLEANER_INTERNAL=1 \
  ZSH_HISTORY_CLEANER_OUTPUT_FD=1 \
  XDG_CONFIG_HOME=$TEST_TMP/config \
  PATH=$stub_bin \
    "$zsh_bin" -fi -c 'cleaner=$1; shift; source "$cleaner" "$@"' \
      cleaner-test "$CLEANER" "$hist" 2>&1
) || refuse_status=$?
(( refuse_status != 0 )) || fail "cleaner ran with no rm on PATH"
[[ $refuse_output == *'required command not found: rm'* ]] ||
  fail "missing rm: unexpected message: $refuse_output"

# --- The real entry point, once -------------------------------------------
# Everything above bypasses the re-entry wrapper; this exercises it.

hist=$TEST_TMP/endtoend
write_history "$hist" 'git status' 'export HF_TOKEN=hf_abcdefghijklmnopqrstuvwxyz12'
HISTFILE='' XDG_CONFIG_HOME=$TEST_TMP/config zsh "$CLEANER" "$hist" >/dev/null 2>&1 ||
  fail "end-to-end: cleaner exited non-zero through its own wrapper"
assert_kept "$hist" 'git status' 'end-to-end'
assert_dropped "$hist" 'export HF_TOKEN=hf_abcdefghijklmnopqrstuvwxyz12' 'end-to-end'

# --help is answered before the re-entry, so a zshrc that dies cannot eat it.
mkdir -p -- "$TEST_TMP/broken-zdotdir"
print -r -- 'print -u2 "broken zshrc"; exit 3' >| "$TEST_TMP/broken-zdotdir/.zshrc"
help_status=0
help_output=$(
  HISTFILE='' ZDOTDIR=$TEST_TMP/broken-zdotdir zsh "$CLEANER" --help 2>/dev/null
) || help_status=$?
(( help_status == 0 )) || fail "help: exited $help_status with a broken zshrc"
[[ $help_output == *'Usage:'* ]] || fail "help: no usage text: $help_output"

print 'PASS: clean-zsh-history drops credentials, resolves past wrappers, and preserves concurrent appends'
