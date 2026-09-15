#############################
# Environment variables setup
#############################

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export EDITOR="nano"
export VISUAL="nano"
export PAGER="less"

[ -x $PREFIX/bin/lesspipe ] && eval "$(SHELL=$PREFIX/bin/sh lesspipe)"

export PATH="$HOME/bin:$HOME/.local/bin:$PREFIX/bin:$PREFIX/sbin:/system/bin:/system/xbin:$PATH"

hash -d etc=$PREFIX/etc
hash -d var=$PREFIX/var
hash -d usr=$PREFIX
hash -d tmp=$PREFIX/tmp
hash -d bin=$PREFIX/bin
hash -d opt=$PREFIX/opt
export LESS_TERMCAP_md=$'\e[1;36m'
export LESS_TERMCAP_us=$'\e[1;33m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_ue=$'\e[0m'
