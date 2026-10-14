########################
# Main Zsh Configuration
########################

ZSH_CONFIG_DIR="${ZSH_CONFIG_DIR:-$HOME/muxrc/zsh}"

source "$ZSH_CONFIG_DIR/env.zsh"

if [[ "$EUID" -eq 0 ]]; then
  HISTFILE="$HOME/.zsh_history_root"
else
  HISTFILE="$HOME/.zsh_history"
fi

HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY
setopt SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS

setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT

source "$ZSH_CONFIG_DIR/functions.zsh"
source "$ZSH_CONFIG_DIR/tools.zsh"
source "$ZSH_CONFIG_DIR/ai.zsh"
source "$ZSH_CONFIG_DIR/aliases.zsh"
source "$ZSH_CONFIG_DIR/prompt.zsh"
source "$ZSH_CONFIG_DIR/plugins.zsh"

if [[ -f "$HOME/.dircolors" ]]; then
  eval "$(dircolors -b "$HOME/.dircolors")"
fi

source "$ZSH_CONFIG_DIR/motd.zsh"
