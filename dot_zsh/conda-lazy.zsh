# Shared lazy conda init for both interactive shells and login shells used by
# coding agents (`zsh -lc`).
lazy_conda_commands=(conda python pip jupyter mamba)

_conda_init_lazy() {
  emulate -L zsh
  setopt localoptions no_aliases

  local cmd
  local conda_root="$HOME/miniconda3"

  for cmd in "${lazy_conda_commands[@]}"; do
    unalias "$cmd" 2>/dev/null || true
    unfunction "$cmd" 2>/dev/null || true
  done
  unfunction _conda_init_lazy 2>/dev/null || true

  if [[ -x "$conda_root/bin/conda" ]]; then
    eval "$("$conda_root/bin/conda" shell.zsh hook 2>/dev/null)"
  else
    print -u2 "conda not found at $conda_root/bin/conda"
    return 127
  fi

  # auto_activate is off (~/.condarc); make sure the wrapped tools actually
  # come from conda. Unless the command already resolves inside $conda_root
  # (login shells put miniconda3/bin on PATH), activate base first -- this
  # covers both "not found" (python in non-login shells) and "shadowed by a
  # system binary" (Ubuntu's /usr/bin/pip). `conda` itself is exempt: the
  # hook defines it as a function.
  if [[ "$1" != conda && "$(whence -p -- "$1" 2>/dev/null)" != "$conda_root"/* ]]; then
    conda activate base 2>/dev/null
  fi

  "$@"
}

for cmd in "${lazy_conda_commands[@]}"; do
  eval "
${cmd}() {
  _conda_init_lazy ${cmd} \"\$@\"
}
"
done
