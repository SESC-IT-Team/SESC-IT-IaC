autoload -U colors
colors

setopt PROMPT_SUBST

smart_pwd() {
    local pwd_str="${PWD/#$HOME/~}"

    if [[ ${#pwd_str} -gt 64 ]]; then
        echo "...${pwd_str: -61}"
    else
        echo "$pwd_str"
    fi
}

PROMPT='%F{green}$(smart_pwd)%f%F{green}>%f '

autoload -U compinit
zstyle ':completion:*' menu select
zmodload zsh/complist
compinit

_comp_options+=(globdots)

bindkey -v
export KEYTIMEOUT=1

export EDITOR='nvim'
export VISUAL='nvim'

alias nv='nvim'

alias gs='git status --short'
alias ga='git add'
alias gap='ga --patch'
alias gb='git branch'
alias gba='gb --all'
alias gc='git commit'
alias gca='gc --amend --no-edit'
alias gce='gc --amend'
alias gco='git checkout'
alias gcl='git clone --recursive'
alias gd='git diff --output-indicator-new=" " --output-indicator-old=" "'
alias gds='gd --staged'
alias gi='git init'
alias gl='git log --graph --all --pretty=format:"%C(magenta)%h %C(white) %an  %ar%C(auto)  %D%n%s%n"'
alias gm='git merge'
alias gn='git checkout -b'
alias gp='git push'
alias gr='git reset'
alias gu='git pull'
alias gw='git switch'

bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'j' vi-down-line-or-history
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char

bindkey -v '^?' backward-delete-char

autoload -U edit-command-line
zle -N edit-command-line
bindkey '^e' edit-command-line

zle-keymap-select() {
    if [[ ${KEYMAP} == vicmd || $1 == block ]]; then
        echo -ne '\e[1 q'
    elif [[ ${KEYMAP} == main || ${KEYMAP} == viins || -z ${KEYMAP} || $1 == beam ]]; then
        echo -ne '\e[5 q'
    fi
}
zle -N zle-keymap-select

zle-line-init() {
    zle -K viins
    echo -ne '\e[5 q'
}
zle -N zle-line-init

echo -ne '\e[5 q'

preexec() {
    echo -ne '\e[5 q'
}

if [[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi