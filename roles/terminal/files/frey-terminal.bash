# Only change interactive Bash sessions.
case $- in *i*) ;; *) return ;; esac

shopt -s cdspell dirspell histappend checkwinsize
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
export HISTSIZE HISTFILESIZE HISTCONTROL

if [ -r /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
fi
if [ -r /usr/share/doc/fzf/examples/key-bindings.bash ]; then
  . /usr/share/doc/fzf/examples/key-bindings.bash
fi

