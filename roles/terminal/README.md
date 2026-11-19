# Terminal

Installs `htop`, `btop`, `tmux`, `ncdu`, `fzf`, `rg` and Bash completion.
Interactive Bash sessions get longer history, Bash's built-in directory
spelling correction, and fzf history search with Ctrl-R. Use Tab to complete
commands and paths. Existing login shells and user startup files are preserved.
The Ghostty terminfo definition is installed so terminal applications work
when connecting with `TERM=xterm-ghostty`.

Deploy with `ansible-playbook playbooks/site.yml --tags terminal`. Start a new
shell, then try `btop`, Tab completion,
and Ctrl-R. `tmux` keeps a session running after disconnect; detach with
Ctrl-B, D and reconnect with `tmux attach`.
