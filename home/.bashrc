# ~/.bashrc

[[ $- != *i* ]] && return

# Large, deduplicated history shared between terminals
HISTSIZE=50000
HISTFILESIZE=100000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend checkwinsize globstar autocd
PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || export PATH="$HOME/.local/bin:$PATH"

alias ls='ls --color=auto --group-directories-first'
alias ll='ls -lah'
alias grep='grep --color=auto'
alias ip='ip -color=auto'
alias diff='diff --color=auto'
alias ..='cd ..'

# Split tunnel: `vpn firefox --new-instance -P vpn` runs the command through WireGuard
alias vpn='wgsplit run'

if [[ -r /usr/share/bash-completion/bash_completion ]]; then
    # shellcheck source=/dev/null
    . /usr/share/bash-completion/bash_completion
fi

if command -v starship >/dev/null; then
    eval "$(starship init bash)"
fi

# Machine-specific tweaks (kept out of the repo)
# shellcheck source=/dev/null
[[ -r ~/.bashrc.local ]] && . ~/.bashrc.local
