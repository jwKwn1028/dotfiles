# macOS compatibility layer

This directory makes the existing rc.d modules usable on macOS without editing
them.

On a Mac, keep this repository at ~/.zsh and run:

~~~zsh
~/.zsh/macos/install.zsh
~~~

The installer adds a pre-loader hook to ~/.zshenv, installs the minimum
Homebrew compatibility packages (coreutils, rsync, and fzf), and exposes the
fzf integration at ~/.fzf.zsh. Run ~/.zsh/macos/doctor.zsh at any time to
validate the setup.

The compatibility layer provides:

- GNU-compatible date and display-width-aware wc resolution;
- an intentionally limited systemctl shim for poweroff and reboot;
- native pbcopy/pbpaste configuration for zsh-helix-mode;
- a native clipcopy command;
- Homebrew rsync 3.x and fzf integration discovery.

Commands such as eza, hx, yazi, zk, PDF viewers, and Taskwarrior remain
separate application dependencies. Missing applications affect only their
corresponding aliases/functions, not shell startup.
