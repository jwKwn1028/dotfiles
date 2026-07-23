#!/usr/bin/env zsh

# Conservatively prune zsh history for history-based suggestions.
#
# The script starts an isolated interactive zsh so aliases and functions from the
# user's normal configuration count as valid commands. The isolated shell never
# writes to the real history file.

emulate -L zsh

script_path=${${(%):-%N}:A}
state_dir=${XDG_STATE_HOME:-${HOME}/.local/state}

usage() {
  print -r -- "Usage: ${script_path:t} [--dry-run] [HISTORY_FILE]"
  print -r -- ""
  print -r -- "Remove high-confidence autocomplete clutter from zsh history:"
  print -r -- "  - exact duplicates"
  print -r -- "  - unresolved command names, typos, prompts, and pasted output"
  print -r -- "  - trivial standalone commands"
  print -r -- "  - commands containing credential-like values"
  print -r -- ""
  print -r -- "A timestamped backup is created before the history is replaced."
  print -r -- "With no HISTORY_FILE, an exported HISTFILE is used; otherwise"
  print -r -- "\$XDG_STATE_HOME/zsh/history (or ~/.local/state/zsh/history) is used."
  print -r -- ""
  print -r -- "Options:"
  print -r -- "  -n, --dry-run  Report what would change without replacing history"
  print -r -- "  -h, --help     Show this help"
}

# A non-interactive script does not normally have the user's aliases/functions.
# Re-enter through an isolated interactive shell, suppressing startup stdout while
# preserving this script's own output on descriptor 3.
if [[ ${ZSH_HISTORY_CLEANER_INTERNAL:-0} != 1 ]]; then
  default_history=${HISTFILE:-${state_dir}/zsh/history}
  HISTFILE='' \
    ZSH_HISTORY_CLEANER_INTERNAL=1 \
    ZSH_HISTORY_CLEANER_DEFAULT_HISTORY=$default_history \
    ZSH_HISTORY_CLEANER_OUTPUT_FD=3 \
    zsh -ic 'HISTFILE=""; source "$1" "${@:2}"' \
      clean-zsh-history "$script_path" "$@" 3>&1 >/dev/null
  cleaner_status=$?
  return $cleaner_status 2>/dev/null || exit $cleaner_status
fi

# Prevent startup hooks in the isolated interactive shell from saving any of its
# in-memory history to the user's history file.
HISTFILE=''
umask 077
setopt EXTENDED_GLOB

integer output_fd=${ZSH_HISTORY_CLEANER_OUTPUT_FD:-1}

report() {
  print -r -u $output_fd -- "$*"
}

fail() {
  print -r -- "${script_path:t}: $*" >&2
  return 1
}

integer dry_run=0
history_arg=''

while (( $# )); do
  case $1 in
    -n|--dry-run)
      dry_run=1
      ;;
    -h|--help)
      usage >&$output_fd
      return 0
      ;;
    --)
      shift
      if (( $# > 1 )); then
        fail "expected at most one history file" || return
      fi
      (( $# == 1 )) && history_arg=$1
      break
      ;;
    -*)
      fail "unknown option: $1" || return
      ;;
    *)
      if [[ -n $history_arg ]]; then
        fail "expected at most one history file" || return
      fi
      history_arg=$1
      ;;
  esac
  shift
done

history_file=${history_arg:-${ZSH_HISTORY_CLEANER_DEFAULT_HISTORY:-${state_dir}/zsh/history}}
history_file=${history_file:P}

if [[ ! -f $history_file ]]; then
  fail "history file does not exist: $history_file" || return
fi
if [[ ! -r $history_file ]]; then
  fail "history file is not readable: $history_file" || return
fi
if (( ! dry_run )) && [[ ! -w $history_file || ! -w ${history_file:h} ]]; then
  fail "history file and its directory must be writable: $history_file" || return
fi

for required_command in cp sha256sum mktemp mv chmod; do
  if ! command -v -- $required_command >/dev/null 2>&1; then
    fail "required command not found: $required_command" || return
  fi
done

snapshot_file=''
cleaned_file=''
context_file=''
integer history_contexts=0

cleanup() {
  while (( history_contexts > 0 )); do
    fc -P 2>/dev/null
    (( --history_contexts ))
  done
  if [[ -n $snapshot_file && -e $snapshot_file ]]; then
    command rm -f -- "$snapshot_file"
  fi
  if [[ -n $cleaned_file && -e $cleaned_file ]]; then
    command rm -f -- "$cleaned_file"
  fi
  if [[ -n $context_file && -e $context_file ]]; then
    command rm -f -- "$context_file"
  fi
}
trap cleanup EXIT HUP INT TERM

snapshot_file=$(mktemp "${history_file:h}/.${history_file:t}.snapshot.XXXXXX") ||
  { fail "could not create a snapshot file" || return; }
cleaned_file=$(mktemp "${history_file:h}/.${history_file:t}.cleaned.XXXXXX") ||
  { fail "could not create an output file" || return; }
context_file=$(mktemp "${history_file:h}/.${history_file:t}.context.XXXXXX") ||
  { fail "could not create a private history context" || return; }

# Verify that the source did not change while it was being copied.
source_hash=$(sha256sum -- "$history_file") || { fail "could not hash history" || return; }
source_hash=${source_hash%%[[:space:]]*}
cp -p -- "$history_file" "$snapshot_file" ||
  { fail "could not snapshot history" || return; }
snapshot_hash=$(sha256sum -- "$snapshot_file") ||
  { fail "could not hash history snapshot" || return; }
snapshot_hash=${snapshot_hash%%[[:space:]]*}
current_hash=$(sha256sum -- "$history_file") ||
  { fail "could not re-check history" || return; }
current_hash=${current_hash%%[[:space:]]*}

if [[ $source_hash != $snapshot_hash || $source_hash != $current_hash ]]; then
  fail "history changed while it was being read; no changes made (run again)" || return
fi

# Read only the stable snapshot into a private history context.
HISTSIZE=200000
SAVEHIST=200000
fc -p "$context_file" $HISTSIZE $SAVEHIST
(( ++history_contexts ))
fc -R -- "$snapshot_file" ||
  { fail "zsh could not read the history snapshot" || return; }
zmodload zsh/parameter ||
  { fail "could not load zsh history parameters" || return; }

entries=()
for event_number in ${(on)${(k)history}}; do
  entries+=("$history[$event_number]")
done

integer original_count=$#entries
integer candidate_count=0
integer dropped_empty=0
integer dropped_sensitive=0
integer dropped_trivial=0
integer dropped_unresolved=0

# Build the cleaned result in another private context. Only exact duplicate
# suppression is enabled; other user history-discard settings are disabled so
# they cannot silently make this filter more aggressive.
fc -p "$context_file" $HISTSIZE $SAVEHIST
(( ++history_contexts ))
unsetopt \
  APPEND_HISTORY \
  EXTENDED_HISTORY \
  HIST_IGNORE_DUPS \
  HIST_IGNORE_SPACE \
  HIST_REDUCE_BLANKS \
  HIST_SAVE_NO_DUPS \
  INC_APPEND_HISTORY \
  INC_APPEND_HISTORY_TIME \
  SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS

trivial_commands=(
  :
  bg
  cd
  clear
  exit
  false
  fg
  history
  jobs
  la
  ll
  logout
  ls
  n
  pwd
  q
  quit
  true
  y
)

for entry in "${entries[@]}"; do
  words=(${(z)entry})
  if (( $#words == 0 )); then
    (( ++dropped_empty ))
    continue
  fi

  lower_entry=${(L)entry}
  if [[ $lower_entry =~ '(^|[[:space:];])(export[[:space:]]+)?[[:alnum:]_]*(api[_-]?key|access[_-]?token|auth[_-]?token|password|passwd|secret)[[:alnum:]_]*=' ||
        $lower_entry =~ '--(api[_-]?key|token|password|passwd|secret)(=|[[:space:]])[^[:space:]]+' ||
        $lower_entry =~ 'authorization:[[:space:]]*bearer[[:space:]]+[[:alnum:]]' ]]; then
    (( ++dropped_sensitive ))
    continue
  fi

  integer word_index=1
  while (( word_index <= $#words )); do
    command_head=${(Q)words[$word_index]}
    [[ $command_head == [A-Za-z_][A-Za-z0-9_]#=* ]] || break
    (( ++word_index ))
  done

  if (( word_index <= $#words )); then
    if (( $#words == 1 && ${trivial_commands[(Ie)$command_head]} )); then
      (( ++dropped_trivial ))
      continue
    fi

    integer recognized=0
    whence -w -- "$command_head" >/dev/null 2>&1 && recognized=1

    # Keep plausible explicit scripts even if they only exist in the directory
    # from which they were originally invoked. Reject path-shaped diagnostics.
    if (( ! recognized )); then
      if [[ $command_head == ./* && $command_head != (./|./.) ]]; then
        recognized=1
      elif [[ $command_head == (../*|\~/*|/*) &&
              $command_head == *.(sh|py|AppImage) ]]; then
        recognized=1
      elif [[ $command_head == (/bin/*|/usr/bin/*|*/.venv/bin/*|*/venvs/*/bin/*) &&
              ! $command_head =~ ':[0-9]+(:[0-9]+)?:$' ]]; then
        recognized=1
      elif [[ $command_head == */*.(sh|py|AppImage) ]]; then
        recognized=1
      fi
    fi

    if (( ! recognized )); then
      (( ++dropped_unresolved ))
      continue
    fi
  fi

  print -s -- "$entry"
  (( ++candidate_count ))
done

zmodload zsh/parameter
integer final_count=${#history}
integer duplicate_count=$(( candidate_count - final_count ))

fc -W -- "$cleaned_file" ||
  { fail "zsh could not write the cleaned history" || return; }
chmod --reference="$history_file" -- "$cleaned_file" ||
  { fail "could not preserve history permissions" || return; }

# Confirm the generated file is fully reloadable before considering replacement.
fc -p "$context_file" $HISTSIZE $SAVEHIST
(( ++history_contexts ))
fc -R -- "$cleaned_file" ||
  { fail "generated history failed validation" || return; }
zmodload zsh/parameter
if (( ${#history} != final_count )); then
  fail "generated history count changed during validation" || return
fi

report "History: $history_file"
report "Entries: $original_count -> $final_count"
report "Removed: unresolved/noise=$dropped_unresolved, trivial=$dropped_trivial, sensitive=$dropped_sensitive, empty=$dropped_empty, exact-duplicates=$duplicate_count"

if (( dry_run )); then
  report "Dry run: no files changed."
  return 0
fi

# Refuse to replace a file that another shell changed after the snapshot.
current_hash=$(sha256sum -- "$history_file") ||
  { fail "could not perform final history check" || return; }
current_hash=${current_hash%%[[:space:]]*}
if [[ $current_hash != $snapshot_hash ]]; then
  fail "history changed during cleanup; no replacement made (run again)" || return
fi

timestamp=${(%):-%D{%Y%m%d-%H%M%S}}
backup_file="${history_file}.pre-autocomplete-cleanup-${timestamp}"
integer backup_suffix=0
while [[ -e $backup_file ]]; do
  (( ++backup_suffix ))
  backup_file="${history_file}.pre-autocomplete-cleanup-${timestamp}.${backup_suffix}"
done

cp -p -- "$snapshot_file" "$backup_file" ||
  { fail "could not create backup: $backup_file" || return; }
mv -f -- "$cleaned_file" "$history_file" ||
  { fail "could not replace history; backup is at $backup_file" || return; }
cleaned_file=''

report "Backup: $backup_file"
report "Done. Restart open zsh sessions with: exec zsh"
