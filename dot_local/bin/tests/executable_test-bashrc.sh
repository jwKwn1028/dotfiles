#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/../../.." && pwd)
BASHRC_FILE=${BASHRC_FILE:-$REPO_ROOT/dot_bashrc}
[[ -r $BASHRC_FILE ]] || BASHRC_FILE=$HOME/.bashrc
[[ -r $BASHRC_FILE ]] || { printf 'FAIL: cannot read bashrc\n' >&2; exit 1; }

TEST_TMP=$(mktemp -d)
trap 'rm -rf -- "$TEST_TMP"' EXIT
mkdir -p "$TEST_TMP/bin" "$TEST_TMP/home" "$TEST_TMP/optional-bin"

for tool in bash basename cat cp date dirname find grep head ls mkdir mktemp readlink rm sed sort tail tput tr uname wc; do
  tool_path=$(type -P -- "$tool")
  ln -s -- "$tool_path" "$TEST_TMP/bin/$tool"
done
for tool in vi python pip jupyter mamba; do
  cat > "$TEST_TMP/bin/$tool" <<'MOCK'
#!/bin/bash
printf '%s\n' "${0##*/}"
MOCK
  chmod +x "$TEST_TMP/bin/$tool"
done

cat > "$TEST_TMP/home/.fzf.bash" <<'MOCK'
printf 'stale fzf integration was sourced\n' >&2
MOCK

run_session() {
  local name=$1 test_path=$2 program=$3
  shift 3
  if ! env -i HOME="$TEST_TMP/home" PATH="$test_path" TERM=xterm COLUMNS=80 \
      BASHRC_FILE="$BASHRC_FILE" "$@" \
      /bin/bash --noprofile --norc -ic '
        source "$BASHRC_FILE"
        fail() { printf "FAIL: %s\n" "$*" >&2; exit 1; }
        eval "$1"
      ' bashrc-test "$program" > "$TEST_TMP/$name.out" 2> "$TEST_TMP/$name.err"; then
    cat "$TEST_TMP/$name.err" >&2
    exit 1
  fi
  # Ignore Bash terminal warnings.
  while IFS= read -r line; do
    case "$line" in
      *': cannot set terminal process group ('*|*': no job control in this shell') ;;
      *) printf 'FAIL: %s emitted stderr: %s\n' "$name" "$line" >&2; exit 1 ;;
    esac
  done < "$TEST_TMP/$name.err"
}

run_session minimal "$TEST_TMP/bin" '
  [[ $EDITOR == vi && $VISUAL == vi && $ZK_EDITOR == vi ]] || fail "editor fallback"
  ! alias ls >/dev/null 2>&1 || fail "ls was replaced without eza"
  [[ $(ls -d .) == . ]] || fail "plain ls is unusable"
  for tool in python pip jupyter mamba; do
    [[ $(type -t "$tool") == file ]] || fail "$tool was shadowed without Miniconda"
    [[ $("$tool") == "$tool" ]] || fail "$tool did not reach its PATH binary"
  done
  for name in twt v h vi mo rg :qa sidle sq myq wsidle mytop; do
    ! alias "$name" >/dev/null 2>&1 || fail "alias $name requires a missing tool"
  done
  for helper in n r y hf zn zs crpf crpd c z thunar tcheck poweroff; do
    output=$("$helper" 2>&1)
    status=$?
    [[ $status == 127 && $output == *"not found"* && $output != *"command not found"* ]] ||
      fail "$helper did not report its missing dependency: status=$status output=$output"
  done
  [[ $_bash_bat == cat && -z $_bash_fd ]] || fail "bat/fd fallbacks"
  [[ -z ${FZF_DEFAULT_OPTS:-} ]] || fail "fzf setup ran without fzf"
'

run_session editor_preferences "$TEST_TMP/bin" '
  [[ $EDITOR == "vi -f" && $VISUAL == vi && $ZK_EDITOR == "vi -f" ]] ||
    fail "existing editor preferences were overwritten"
' EDITOR='vi -f' VISUAL=vi

for tool in eza hx fzf sinfo squeue fdfind batcat; do
  cat > "$TEST_TMP/optional-bin/$tool" <<'MOCK'
#!/bin/bash
printf '%s\n' "${0##*/}"
MOCK
  chmod +x "$TEST_TMP/optional-bin/$tool"
done
cat > "$TEST_TMP/home/.fzf.bash" <<'MOCK'
FZF_INTEGRATION_LOADED=1
MOCK

run_session optional "$TEST_TMP/optional-bin:$TEST_TMP/bin" '
  [[ $EDITOR == hx && $VISUAL == hx ]] || fail "Helix was not selected when installed"
  [[ $(ls) == eza ]] || fail "installed eza alias did not run"
  [[ $(alias h) == *"hx ."* ]] || fail "Helix alias is missing"
  [[ $_bash_fd == fdfind && $_bash_bat == batcat ]] || fail "Debian tool variants"
  [[ ${FZF_INTEGRATION_LOADED:-} == 1 ]] || fail "installed fzf integration was skipped"
  [[ $FZF_DEFAULT_OPTS != *fzf-preview* ]] || fail "missing preview helper was enabled"
  alias sidle sq >/dev/null 2>&1 || fail "available Slurm aliases are missing"
  ! alias myq >/dev/null 2>&1 || fail "watch alias was enabled without watch"
'

cat > "$TEST_TMP/optional-bin/fzf-preview" <<'MOCK'
#!/bin/bash
exit 0
MOCK
chmod +x "$TEST_TMP/optional-bin/fzf-preview"
run_session preview "$TEST_TMP/optional-bin:$TEST_TMP/bin" '
  [[ $FZF_DEFAULT_OPTS == *"fzf-preview {}"* ]] || fail "available preview was skipped"
'

mkdir -p "$TEST_TMP/home/miniconda3/bin"
cat > "$TEST_TMP/home/miniconda3/bin/conda" <<'MOCK'
#!/bin/bash
[[ $* == "shell.bash hook" ]] || exit 1
printf "%s\n" "conda() { :; }" "export PATH=\"\$HOME/miniconda3/bin:\$PATH\""
MOCK
cat > "$TEST_TMP/home/miniconda3/bin/python" <<'MOCK'
#!/bin/bash
printf 'conda-python\n'
MOCK
chmod +x "$TEST_TMP/home/miniconda3/bin/conda" "$TEST_TMP/home/miniconda3/bin/python"
run_session conda "$TEST_TMP/bin" '
  [[ $(type -t python) == function ]] || fail "installed Miniconda was not lazy"
  [[ $(python) == conda-python ]] || fail "lazy initialization did not run Conda Python"
'

env -i HOME="$TEST_TMP/home" PATH="$TEST_TMP/bin" BASHRC_FILE="$BASHRC_FILE" \
  /bin/bash --noprofile --norc -c '
    source "$BASHRC_FILE"
    [[ -z ${EDITOR:-} ]] && ! declare -F _have >/dev/null
  ' > "$TEST_TMP/noninteractive.out" 2> "$TEST_TMP/noninteractive.err"
[[ ! -s $TEST_TMP/noninteractive.out && ! -s $TEST_TMP/noninteractive.err ]]

printf 'PASS: remote Bash startup, missing tools, editor preferences, fzf, and lazy Conda\n'
