######################
# Custom shell aliases
######################

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias xclip='termux-clipboard-set'
alias xsel='termux-clipboard-set'
alias pbcopy='termux-clipboard-set'
alias pbpaste='termux-clipboard-get'

alias wakelock='termux-wake-lock && echo "wakelock acquired"'
alias wakelock-off='termux-wake-unlock && echo "wakelock released"'

alias ssh-setup='net remote setup'
alias ssh-start='net remote start'
alias ssh-stop='net remote stop'
alias ssh-reload='net remote reload'
alias ssh-status='net remote status'
alias ssh-pair='net remote pair'
alias ssh-config='net remote config'

##################################
# Android file handlers & suffixes
##################################
alias scandl='termux-media-scan -r /storage/emulated/0/Download'

if (( $+commands[termux-open] )); then
  alias open='termux-open'
  alias share='termux-open --send'
  alias pick='termux-open --chooser'

  alias -s {png,jpg,jpeg,gif,webp,svg}=termux-open
  alias -s {mp4,mkv,webm,mov}=termux-open
  alias -s {mp3,wav,flac,ogg,m4a}=termux-open
  alias -s {pdf,epub,docx,xlsx,pptx}=termux-open
  alias -s {html,htm}=termux-open
elif (( $+commands[xdg-open] )); then
  alias open='xdg-open'

  alias -s {png,jpg,jpeg,gif,webp,svg}=xdg-open
  alias -s {mp4,mkv,webm,mov}=xdg-open
  alias -s {mp3,wav,flac,ogg,m4a}=xdg-open
  alias -s {pdf,epub,docx,xlsx,pptx}=xdg-open
  alias -s {html,htm}=xdg-open
fi
