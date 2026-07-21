#!/bin/zsh

emulate -L zsh
setopt no_aliases pipefail

typeset root="${${(%):-%N}:A:h}"
typeset -i failures=0

if [[ $OSTYPE != darwin* ]]; then
  print -u2 -- 'macos/doctor.zsh must be run on macOS.'
  exit 2
fi

source "$root/compat.zsh"

pass() { print -P -- "%F{green}ok%f  $1"; }
fail() { print -P -u2 -- "%F{red}fail%f  $1"; (( failures++ )); }

if [[ ${commands[date]:-} == "$root/bin/date" ]]; then
  pass 'date compatibility shim is first in PATH'
else
  fail "date resolves to ${commands[date]:-missing}"
fi

if [[ ${commands[wc]:-} == "$root/bin/wc" ]]; then
  pass 'wc compatibility shim is first in PATH'
else
  fail "wc resolves to ${commands[wc]:-missing}"
fi

typeset today relative_today
today=$(/bin/date +%F)
relative_today=$(date -d '0 days' +%F 2>/dev/null)
[[ $relative_today == $today ]] &&
  pass 'GNU-style date -d works' || fail 'GNU-style date -d failed'

typeset banner_width
banner_width=$(print -rn -- 'é漢' | command wc -L 2>/dev/null)
banner_width=${banner_width//[[:space:]]/}
[[ $banner_width == 3 ]] &&
  pass 'wc -L reports Unicode display width' ||
  fail 'install Homebrew coreutils so wc -L reports display width'

[[ $ZHM_CLIPBOARD_PIPE_CONTENT_TO == pbcopy &&
   $ZHM_CLIPBOARD_READ_CONTENT_FROM == pbpaste ]] &&
  pass 'Helix clipboard uses pbcopy/pbpaste' ||
  fail 'Helix clipboard variables are not configured for macOS'

[[ -x "$root/bin/systemctl" ]] &&
  pass 'systemctl power shim is installed' || fail 'systemctl shim is missing'
[[ -x "$root/bin/clipcopy" ]] &&
  pass 'clipcopy shim is installed' || fail 'clipcopy shim is missing'

typeset rsync_version
rsync_version=$(rsync --info=progress2 --protect-args --version 2>/dev/null |
  command head -n 1)
[[ $rsync_version == *'version 3.'* ]] &&
  pass "$rsync_version" ||
  fail 'install Homebrew rsync 3.x with --info and --protect-args support'

[[ -r "$HOME/.fzf.zsh" ]] &&
  pass '~/.fzf.zsh is available to rc.d/40-fzf.zsh' ||
  fail '~/.fzf.zsh is missing; run macos/install.zsh'

if (( failures )); then
  print -u2 -- "$failures compatibility check(s) failed."
  exit 1
fi

print -- 'macOS compatibility layer is ready.'
