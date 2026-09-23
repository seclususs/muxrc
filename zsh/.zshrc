########################
# Main Zsh configuration
########################

ZSH_CONFIG_DIR="$HOME/muxrc/zsh"

source "$ZSH_CONFIG_DIR/env.zsh"

HISTFILE="$HOME/.zsh_history"
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

source "$ZSH_CONFIG_DIR/aliases.zsh"

source "$ZSH_CONFIG_DIR/prompt.zsh"

source "$ZSH_CONFIG_DIR/plugins.zsh"

if [[ -f "$HOME/.dircolors" ]]; then
    eval $(dircolors -b "$HOME/.dircolors")
fi

if [[ "$TERMUX_FAKEROOT" == "1" ]]; then
    PROMPT='%F{196}root@termux%f:%F{39}%~%f# '
    
    magic_su_enter() {
        local cmd="${BUFFER%% *}"
        
        if [[ -n "$BUFFER" && "$cmd" != "exit" && "$cmd" != "clear" && "$cmd" != "sudo" && "$cmd" != "su" ]]; then
            
            local cmd_type
            cmd_type=$(whence -w "$cmd" 2>/dev/null | awk '{print $2}')
            
            if [[ "$cmd_type" != "builtin" && "$cmd_type" != "function" ]]; then
                
                local current_alias=$(alias "$cmd" 2>/dev/null)
                
                if [[ -n "$current_alias" ]]; then
                    if [[ "$current_alias" != *"sudo "* ]]; then
                        local alias_val="${current_alias#*=}"
                        alias_val="${alias_val%\'}"
                        alias_val="${alias_val#\'}"
                        alias "$cmd"="sudo $alias_val"
                    fi
                else
                    alias "$cmd"="sudo $cmd"
                fi
            fi
        fi
        
        zle .accept-line
    }
    
    zle -N accept-line magic_su_enter
fi

source "$ZSH_CONFIG_DIR/motd.zsh"
