# fzf shell integration at the exact path rc.d/40-fzf.zsh expects.

if (( $+commands[fzf] )); then
  if fzf --zsh >/dev/null 2>&1; then
    source <(fzf --zsh)
  else
    typeset _macos_fzf_root
    for _macos_fzf_root in \
      "${HOMEBREW_PREFIX:-}/opt/fzf/shell" \
      /opt/homebrew/opt/fzf/shell \
      /usr/local/opt/fzf/shell \
      /usr/share/doc/fzf/examples \
      /usr/share/fzf
    do
      if [[ -r "$_macos_fzf_root/key-bindings.zsh" ]]; then
        source "$_macos_fzf_root/key-bindings.zsh"
        [[ -r "$_macos_fzf_root/completion.zsh" ]] &&
          source "$_macos_fzf_root/completion.zsh"
        break
      fi
    done
    unset _macos_fzf_root
  fi
fi
