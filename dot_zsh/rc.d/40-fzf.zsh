# --------------------------------------------------------
# fzf integration
# --------------------------------------------------------
# Default/CTRL-T/ALT-C commands, preview, keybindings, hf.
# Uses $_zsh_fd / $_zsh_bat (resolved once in _lib.zsh) instead of the
# old per-block fd -> fdfind -> rg -> find ladder.
if command -v fzf >/dev/null 2>&1; then

  if [[ -n $_zsh_fd ]]; then
    export FZF_DEFAULT_COMMAND="$_zsh_fd --hidden --follow --exclude .git --type f"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND="$_zsh_fd --hidden --follow --exclude .git --type d"

    _fzf_compgen_path() { "$_zsh_fd" --hidden --follow --exclude .git . "$1"; }
    _fzf_compgen_dir()  { "$_zsh_fd" --hidden --follow --exclude .git --type d . "$1"; }
  elif whence -p rg >/dev/null; then
    export FZF_DEFAULT_COMMAND='rg --files --no-ignore --hidden --glob "!.git/*"'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='find . -type d -not -path "*/.git/*"'

    _fzf_compgen_path() { rg --files --no-ignore --hidden --glob '!.git/*' "${1:-.}"; }
    _fzf_compgen_dir()  { find "${1:-.}" -type d -not -path '*/.git/*'; }
  else
    export FZF_DEFAULT_COMMAND='find . -type f -not -path "*/.git/*"'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='find . -type d -not -path "*/.git/*"'

    _fzf_compgen_path() { find "${1:-.}" -not -path '*/.git/*'; }
    _fzf_compgen_dir()  { find "${1:-.}" -type d -not -path '*/.git/*'; }
  fi

  # Preview command, built inside an anonymous function so the scratch
  # variables stay local (the old top-level `local`s leaked into the session).
  () {
    local highlight='cat -- {}'
    [[ $_zsh_bat != cat ]] && highlight="$_zsh_bat --color=always --style=numbers --line-range=:500 -- {}"

    local prev_cmd="
    if [ -d {} ]; then
      eza --tree --level=2 --color=always --icons --group-directories-first -- {};
    elif echo {} | grep -iq '\.pdf$'; then
      pdftotext -f 1 -l 10 -- {} - 2>/dev/null;
    else
      ${highlight};
    fi"

    export FZF_DEFAULT_OPTS="
    --height 60%
    --layout=reverse
    --border
    --preview 'sh -c \"${prev_cmd//$'\n'/ }\"'"
  }
fi

# --------------------------------------------------------
# Source fzf keybindings
# --------------------------------------------------------
if [[ -t 0 && -t 1 ]]; then
  if [[ -f "$HOME/.fzf.zsh" ]]; then
    source "$HOME/.fzf.zsh"
  elif [[ -f "/usr/share/doc/fzf/examples/key-bindings.zsh" ]]; then
    source "/usr/share/doc/fzf/examples/key-bindings.zsh"
    source "/usr/share/doc/fzf/examples/completion.zsh"
  elif [[ -f "/usr/share/fzf/key-bindings.zsh" ]]; then
    source "/usr/share/fzf/key-bindings.zsh"
    source "/usr/share/fzf/completion.zsh"
  fi

  # Silent Alt-C: cd directly without echoing "builtin cd -- ..."
  if (( $+functions[fzf-cd-widget] )); then
    fzf-cd-widget() {
      local cmd="${FZF_ALT_C_COMMAND:-"command find -L . -mindepth 1 \\( -path '*/.*' -o -fstype 'sysfs' -o -fstype 'devfs' -o -fstype 'devtmpfs' -o -fstype 'proc' \\) -prune \
        -o -type d -print 2> /dev/null | cut -b3-"}"
      setopt localoptions pipefail no_aliases 2> /dev/null
      local dir="$(eval "$cmd" | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse --scheme=path --bind=ctrl-z:ignore ${FZF_DEFAULT_OPTS-} ${FZF_ALT_C_OPTS-}" $(__fzfcmd) +m)"
      if [[ -z "$dir" ]]; then
        zle redisplay
        return 0
      fi
      builtin cd -- "${dir}" 2> /dev/null
      local ret=$?
      unset dir
      zle reset-prompt
      return $ret
    }
    zle -N fzf-cd-widget
  fi

  if (( $+functions[zhm_wrap_widget] )); then
    if (( $+functions[fzf-file-widget] )); then
      bindkey -M hxins '^T' fzf-file-widget
      bindkey -M hxnor '^T' fzf-file-widget
    fi
    if (( $+functions[fzf-cd-widget] )); then
      bindkey -M hxins '\ec' fzf-cd-widget
      bindkey -M hxnor '\ec' fzf-cd-widget
    fi
    if (( $+functions[fzf-history-widget] )); then
      bindkey -M hxins '^R' fzf-history-widget
      bindkey -M hxnor '^R' fzf-history-widget
    fi
  fi
fi

if (( $+functions[zhm_wrap_widget] && $+functions[fzf-completion] )); then
  zhm_wrap_widget fzf-completion zhm_fzf_completion
  bindkey '^I' zhm_fzf_completion
fi

# --------------------------------------------------------
# Helix + FZF
# --------------------------------------------------------
hf() {
  local file
  file="$(fzf --prompt='Open with Helix> ')" || return 1

  hx "$file"
}
