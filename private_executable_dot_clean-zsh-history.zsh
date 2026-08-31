#!/usr/bin/env zsh

# Conservatively prune zsh history for history-based suggestions.
#
# Drops exact duplicates (keeping the most recent), unresolved command names,
# trivial standalone commands, and commands carrying credential-like values.
# Names in $XDG_CONFIG_HOME/zsh-history-cleaner/keep are always treated as real.
# An unresolved name is also kept when it looks like an explicitly invoked
# script. A timestamped backup is written before the history is replaced.
#
# Load-bearing, each having broken this script before:
#
#   - Re-enters through an isolated interactive zsh so the user's aliases and
#     functions count as valid commands; that shell never writes the real
#     history file. `shift` before `source` is required: `source` with no
#     arguments leaves the caller's positional parameters visible to the sourced
#     file, which once handed this script its own path as HISTORY_FILE.
#   - In an interactive shell $history hides the newest event, so a sentinel
#     occupies that slot; without it the last real entry was dropped.
#   - Kept entries are copied as raw file records, not replayed with `print -s`:
#     replaying restamps every entry and loses zsh's metafied encoding. One
#     record is one entry byte-for-byte, including the optional
#     ": <timestamp>:<elapsed>;" prefix and backslash-marked continuation lines.
#   - `print -s` also ignores the HIST_* discard options, so exact duplicates are
#     resolved here rather than by HIST_IGNORE_ALL_DUPS.

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
  print -r -- "Command names listed in \$XDG_CONFIG_HOME/zsh-history-cleaner/keep"
  print -r -- "(or ~/.config/zsh-history-cleaner/keep) are never treated as unresolved."
  print -r -- ""
  print -r -- "Entries that survive keep their original timestamps."
  print -r -- "A timestamped backup is created before the history is replaced;"
  print -r -- "the newest \$ZSH_HISTORY_CLEANER_KEEP_BACKUPS (default 5) are kept."
  print -r -- "Backups retain the credentials dropped from the live history."
  print -r -- "With no HISTORY_FILE, an exported HISTFILE is used; otherwise"
  print -r -- "\$XDG_STATE_HOME/zsh/history (or ~/.local/state/zsh/history) is used."
  print -r -- ""
  print -r -- "Options:"
  print -r -- "  -n, --dry-run  Report what would change without replacing history"
  print -r -- "  -h, --help     Show this help"
}

if [[ ${ZSH_HISTORY_CLEANER_INTERNAL:-0} != 1 ]]; then
  default_history=${HISTFILE:-${state_dir}/zsh/history}
  HISTFILE='' \
    ZSH_HISTORY_CLEANER_INTERNAL=1 \
    ZSH_HISTORY_CLEANER_DEFAULT_HISTORY=$default_history \
    ZSH_HISTORY_CLEANER_OUTPUT_FD=3 \
    zsh -ic 'HISTFILE=""; cleaner_script=$1; shift; source "$cleaner_script" "$@"' \
      clean-zsh-history "$script_path" "$@" 3>&1 >/dev/null
  cleaner_status=$?
  return $cleaner_status 2>/dev/null || exit $cleaner_status
fi

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

if [[ $history_file == ${script_path:P} ]]; then
  fail "refusing to clean this script itself: $history_file" || return
fi
if [[ ! -f $history_file ]]; then
  fail "history file does not exist: $history_file" || return
fi
if [[ ! -r $history_file ]]; then
  fail "history file is not readable: $history_file" || return
fi
if IFS= read -r shebang_line < "$history_file" && [[ $shebang_line == '#!'* ]]; then
  fail "refusing to clean what looks like a script, not a history file: $history_file" || return
fi
if (( ! dry_run )) && [[ ! -w $history_file || ! -w ${history_file:h} ]]; then
  fail "history file and its directory must be writable: $history_file" || return
fi

for required_command in cp mktemp mv chmod head tail; do
  if ! command -v -- $required_command >/dev/null 2>&1; then
    fail "required command not found: $required_command" || return
  fi
done

zmodload -F zsh/stat b:zstat ||
  { fail "could not load zsh/stat" || return; }

if command -v -- sha256sum >/dev/null 2>&1; then
  digest() { local o; o=$(sha256sum -- "$1") || return 1; print -r -- ${o%%[[:space:]]*} }
elif command -v -- shasum >/dev/null 2>&1; then
  digest() { local o; o=$(shasum -a 256 -- "$1") || return 1; print -r -- ${o%%[[:space:]]*} }
else
  fail "required command not found: sha256sum or shasum" || return
fi

file_size() {
  local -a s
  zstat -A s +size -- "$1" || return 1
  print -r -- $s[1]
}

# The name suffix must break on _ or -, or `tokenizers_parallelism=` matches.
is_sensitive() {
  local lower=${(L)1}
  [[ $lower =~ '(^|[[:space:];])(export[[:space:]]+|env[[:space:]]+)?[[:alnum:]_]*(api[_-]?key|token|secret|password|passwd|passphrase|credential)([_-][[:alnum:]_]*)?=' ||
     $lower =~ '--(api[_-]?key|token|password|passwd|passphrase|secret)(=|[[:space:]])[^[:space:]]+' ||
     $lower =~ 'authorization:[[:space:]]*bearer[[:space:]]+[[:alnum:]]' ||
     $lower =~ '(^|[^[:alnum:]_-])(github_pat_[[:alnum:]_]{20,}|gh[pousr]_[[:alnum:]_.-]{16,})' ||
     $lower =~ '(^|[^[:alnum:]_-])(sk-[[:alnum:]_-]{20,}|hf_[[:alnum:]]{20,}|xox[baprs]-[[:alnum:]-]{10,}|akia[[:alnum:]]{16})' ]]
}

snapshot_file=''
cleaned_file=''
context_file=''
tail_file=''
history_sentinel=': zsh-history-cleaner sentinel, never written to disk'
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
  if [[ -n $tail_file && -e $tail_file ]]; then
    command rm -f -- "$tail_file"
  fi
}
trap cleanup EXIT HUP INT TERM

snapshot_file=$(mktemp "${history_file:h}/.${history_file:t}.snapshot.XXXXXX") ||
  { fail "could not create a snapshot file" || return; }
cleaned_file=$(mktemp "${history_file:h}/.${history_file:t}.cleaned.XXXXXX") ||
  { fail "could not create an output file" || return; }
context_file=$(mktemp "${history_file:h}/.${history_file:t}.context.XXXXXX") ||
  { fail "could not create a private history context" || return; }
tail_file=$(mktemp "${history_file:h}/.${history_file:t}.tail.XXXXXX") ||
  { fail "could not create a merge scratch file" || return; }

source_hash=$(digest "$history_file") || { fail "could not hash history" || return; }
cp -p -- "$history_file" "$snapshot_file" ||
  { fail "could not snapshot history" || return; }
snapshot_hash=$(digest "$snapshot_file") ||
  { fail "could not hash history snapshot" || return; }
current_hash=$(digest "$history_file") ||
  { fail "could not re-check history" || return; }
integer snapshot_size
snapshot_size=$(file_size "$snapshot_file") ||
  { fail "could not measure history snapshot" || return; }

if [[ $source_hash != $snapshot_hash || $source_hash != $current_hash ]]; then
  fail "history changed while it was being read; no changes made (run again)" || return
fi

records=()
record=''
record_line=''
integer record_open=0
while IFS= read -r record_line || [[ -n $record_line ]]; do
  if (( record_open )); then
    record+=$'\n'$record_line
  else
    record=$record_line
    record_open=1
  fi
  record_trailing=${record##*[^\\]}
  (( ${#record_trailing} % 2 )) && continue
  records+=("$record")
  record_open=0
  record_line=''
done < "$snapshot_file"
(( record_open )) && records+=("$record")

unsetopt \
  APPEND_HISTORY \
  EXTENDED_HISTORY \
  HIST_IGNORE_ALL_DUPS \
  HIST_IGNORE_DUPS \
  HIST_IGNORE_SPACE \
  HIST_REDUCE_BLANKS \
  HIST_SAVE_NO_DUPS \
  INC_APPEND_HISTORY \
  INC_APPEND_HISTORY_TIME \
  SHARE_HISTORY

# Below $#records, fc -R silently drops the oldest events.
HISTSIZE=$(( $#records + 1000 ))
(( HISTSIZE < 200000 )) && HISTSIZE=200000
SAVEHIST=$HISTSIZE
fc -p "$context_file" $HISTSIZE $SAVEHIST
(( ++history_contexts ))
fc -R -- "$snapshot_file" ||
  { fail "zsh could not read the history snapshot" || return; }
zmodload zsh/parameter ||
  { fail "could not load zsh history parameters" || return; }
print -s -- "$history_sentinel"

entries=()
for event_number in ${(on)${(k)history}}; do
  entries+=("$history[$event_number]")
done

if (( $#records != $#entries )); then
  fail "could not match $#records history records to $#entries parsed entries; no changes made" || return
fi

integer original_count=$#entries
integer dropped_empty=0
integer dropped_duplicate=0
integer dropped_sensitive=0
integer dropped_trivial=0
integer dropped_unresolved=0

typeset -A last_index
for (( entry_index = 1; entry_index <= $#entries; entry_index++ )); do
  [[ -n ${entries[$entry_index]} ]] && last_index[${entries[$entry_index]}]=$entry_index
done

keep_file=${XDG_CONFIG_HOME:-${HOME}/.config}/zsh-history-cleaner/keep
typeset -A keep_commands
if [[ -r $keep_file ]]; then
  while IFS= read -r keep_line; do
    keep_line=${keep_line%%\#*}
    keep_line=${${keep_line##[[:space:]]#}%%[[:space:]]#}
    [[ -n $keep_line ]] && keep_commands[$keep_line]=1
  done < "$keep_file"
fi

wrapper_commands=(
  builtin
  command
  doas
  env
  exec
  nohup
  setsid
  sudo
  time
)

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

kept_records=()

for (( entry_index = 1; entry_index <= $#entries; entry_index++ )); do
  entry=${entries[$entry_index]}
  words=(${(z)entry})
  if (( $#words == 0 )); then
    (( ++dropped_empty ))
    continue
  fi

  if [[ ${last_index[$entry]} != $entry_index ]]; then
    (( ++dropped_duplicate ))
    continue
  fi

  if is_sensitive "$entry"; then
    (( ++dropped_sensitive ))
    continue
  fi

  integer word_index=1 wrapper_hops=0
  while (( word_index <= $#words )); do
    command_head=${(Q)words[$word_index]}
    if [[ $command_head == [A-Za-z_][A-Za-z0-9_]#=* ]]; then
      (( ++word_index ))
      continue
    fi
    # Look past a wrapper only when no option follows: `sudo -u x cmd` would
    # otherwise resolve `x` as the command.
    (( wrapper_hops < 3 )) &&
      (( ${wrapper_commands[(Ie)$command_head]} )) &&
      (( word_index < $#words )) &&
      [[ ${(Q)words[word_index+1]} != -* ]] || break
    (( ++wrapper_hops, ++word_index ))
  done

  if (( word_index <= $#words )); then
    if (( $#words == 1 && ${trivial_commands[(Ie)$command_head]} )); then
      (( ++dropped_trivial ))
      continue
    fi

    integer recognized=0
    whence -w -- "$command_head" >/dev/null 2>&1 && recognized=1
    [[ -n ${keep_commands[$command_head]} ]] && recognized=1

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

  kept_records+=("$records[$entry_index]")
done

integer final_count=$#kept_records
integer expected_count=$(( original_count - dropped_empty - dropped_duplicate -
                           dropped_sensitive - dropped_trivial - dropped_unresolved ))
if (( final_count != expected_count )); then
  fail "internal count mismatch: kept $final_count, expected $expected_count" || return
fi

if (( final_count )); then
  print -rl -- "${kept_records[@]}" > "$cleaned_file" ||
    { fail "could not write the cleaned history" || return; }
else
  : > "$cleaned_file" || { fail "could not write the cleaned history" || return; }
fi
zstat -A history_mode +mode -- "$history_file" ||
  { fail "could not read history permissions" || return; }
chmod $(( [##8] history_mode[1] & 8#7777 )) -- "$cleaned_file" ||
  { fail "could not preserve history permissions" || return; }

validate_cleaned() {
  local -i expected=$1

  fc -p "$context_file" $HISTSIZE $SAVEHIST
  (( ++history_contexts ))
  fc -R -- "$cleaned_file" ||
    { fail "generated history failed validation" || return; }
  zmodload zsh/parameter ||
    { fail "could not load zsh history parameters" || return; }
  print -s -- "$history_sentinel"
  if (( ${#history} != expected )); then
    fail "generated history holds ${#history} entries, expected $expected" || return
  fi
}

validate_cleaned $final_count || return

report "History: $history_file"
report "Entries: $original_count -> $final_count"
report "Removed: unresolved/noise=$dropped_unresolved, trivial=$dropped_trivial, sensitive=$dropped_sensitive, empty=$dropped_empty, exact-duplicates=$dropped_duplicate"

if (( dry_run )); then
  report "Dry run: no files changed."
  return 0
fi

current_hash=$(digest "$history_file") ||
  { fail "could not perform final history check" || return; }

integer merged_records=0
if [[ $current_hash != $snapshot_hash ]]; then
  integer current_size
  current_size=$(file_size "$history_file") ||
    { fail "could not measure history" || return; }
  head -c $snapshot_size -- "$history_file" >| "$tail_file" ||
    { fail "could not re-read history" || return; }
  # Only a pure append is recoverable: the file must still open with the
  # snapshot, byte for byte, and end on a record boundary.
  if (( snapshot_size == 0 || current_size <= snapshot_size )) ||
     [[ -n $(tail -c 1 -- "$snapshot_file") ]] ||
     [[ $(digest "$tail_file") != $snapshot_hash ]]; then
    fail "history was rewritten during cleanup; no replacement made (run again)" || return
  fi
  tail -c +$(( snapshot_size + 1 )) -- "$history_file" >| "$tail_file" ||
    { fail "could not read the appended history" || return; }

  # A writer caught mid-record must win the race. Replacing the file now would
  # either lose its unfinished entry or splice the following entry into it.
  if [[ -n $(tail -c 1 -- "$tail_file") ]]; then
    fail "history append ended mid-record; no replacement made (run again)" || return
  fi

  appended_records=()
  appended_record=''
  appended_line=''
  integer appended_record_open=0
  while IFS= read -r appended_line || [[ -n $appended_line ]]; do
    if (( appended_record_open )); then
      appended_record+=$'\n'$appended_line
    else
      appended_record=$appended_line
      appended_record_open=1
    fi
    appended_trailing=${appended_record##*[^\\]}
    (( ${#appended_trailing} % 2 )) && continue
    appended_records+=("$appended_record")
    appended_record_open=0
    appended_line=''
  done < "$tail_file"
  if (( appended_record_open )); then
    fail "history append ended mid-record; no replacement made (run again)" || return
  fi

  for appended_record in "${appended_records[@]}"; do
    is_sensitive "$appended_record" && continue
    print -r -- "$appended_record" >> "$cleaned_file" ||
      { fail "could not merge appended history" || return; }
    (( ++merged_records ))
  done
  report "Merged: $merged_records record(s) appended by other shells during the run"
  validate_cleaned $(( final_count + merged_records )) || return
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

integer keep_backups=${ZSH_HISTORY_CLEANER_KEEP_BACKUPS:-5}
(( keep_backups < 1 )) && keep_backups=1
stale_backups=( ${history_file}.pre-autocomplete-cleanup-*(N.om) )
if (( $#stale_backups > keep_backups )); then
  prune_backups=( "${(@)stale_backups[keep_backups+1,-1]}" )
  if command rm -f -- "${(@)prune_backups}"; then
    report "Pruned: $#prune_backups old backup(s)"
  else
    report "Warning: could not prune old backups"
  fi
fi

report "Backup: $backup_file"
report "Done. Restart open zsh sessions with: exec zsh"
