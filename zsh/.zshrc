########################
# Main Zsh Configuration
########################

ZSH_CONFIG_DIR="${ZSH_CONFIG_DIR:-$HOME/muxrc/zsh}"

source "$ZSH_CONFIG_DIR/env.zsh"

local _zsh_state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/zsh"
[[ ! -d "$_zsh_state_dir" ]] && mkdir -p "$_zsh_state_dir"

if [[ "$EUID" -eq 0 ]]; then
  HISTFILE="$_zsh_state_dir/history_root"
  [[ ! -f "$HISTFILE" && -f "$HOME/.zsh_history_root" ]] && mv "$HOME/.zsh_history_root" "$HISTFILE" 2> /dev/null
else
  HISTFILE="$_zsh_state_dir/history"
  [[ ! -f "$HISTFILE" && -f "$HOME/.zsh_history" ]] && mv "$HOME/.zsh_history" "$HISTFILE" 2> /dev/null
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

source "$ZSH_CONFIG_DIR/linux/auth.zsh"
local _linux_mod=""
for _linux_mod in "$ZSH_CONFIG_DIR/linux/"*.zsh; do
  [[ "$_linux_mod" == *"auth.zsh" ]] && continue
  [[ -f "$_linux_mod" ]] && source "$_linux_mod"
done
unset _linux_mod

source "$ZSH_CONFIG_DIR/cli/dispatch.zsh"
source "$ZSH_CONFIG_DIR/cli/muxrc.zsh"
source "$ZSH_CONFIG_DIR/aliases.zsh"
source "$ZSH_CONFIG_DIR/prompt.zsh"
if [[ -f "$HOME/.dircolors" ]]; then
  eval "$(dircolors -b "$HOME/.dircolors")"
fi

source "$ZSH_CONFIG_DIR/plugins.zsh"

source "$ZSH_CONFIG_DIR/motd.zsh"
