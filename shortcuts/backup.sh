#!/data/data/com.termux/files/usr/bin/bash
source "$HOME/muxrc/zsh/functions.zsh" 2>/dev/null
notify-task rsync -avh --progress "$HOME/" "$HOME/backup/"
