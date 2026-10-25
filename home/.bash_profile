# ~/.bash_profile — login shells (TTY, ssh). The graphical session starts from greetd.

[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"

# shellcheck source=/dev/null
[[ -f ~/.bashrc ]] && . ~/.bashrc
