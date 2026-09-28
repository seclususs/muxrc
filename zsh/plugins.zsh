#######################
# Zsh extensions loader
#######################

ZSH_PLUGINS_DIR="$HOME/.zsh/plugins"

fpath=($ZSH_PLUGINS_DIR/zsh-completions/src $fpath)

autoload -Uz compinit
compinit

[ -f $PREFIX/share/fzf/completion.zsh ] && source $PREFIX/share/fzf/completion.zsh
[ -f $PREFIX/share/fzf/key-bindings.zsh ] && source $PREFIX/share/fzf/key-bindings.zsh

if [[ -f "$ZSH_PLUGINS_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh" ]]; then
    source "$ZSH_PLUGINS_DIR/zsh-history-substring-search/zsh-history-substring-search.zsh"
    
    bindkey '^[[A' history-substring-search-up
    bindkey '^[[B' history-substring-search-down
    
    bindkey -M vicmd 'k' history-substring-search-up
    bindkey -M vicmd 'j' history-substring-search-down
    
    HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='fg=green,bold'
    HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='fg=red,bold'
fi

if [[ -f "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
    source "$ZSH_PLUGINS_DIR/zsh-autosuggestions/zsh-autosuggestions.zsh"
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#5c6370"
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
fi

if [[ -f "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
    source "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

if [[ -f "$ZSH_PLUGINS_DIR/fzf-tab/fzf-tab.plugin.zsh" ]]; then
    source "$ZSH_PLUGINS_DIR/fzf-tab/fzf-tab.plugin.zsh"
fi

##############################
# Completion & fzf-tab Configs
##############################
zstyle ':completion:*' list-colors ${(s.:.)${LS_COLORS-}}
zstyle ':completion:*:descriptions' format '[%d]'
zstyle ':fzf-tab:*' switch-group '<' '>'
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color=always -1 $realpath'


################################
# Zsh Syntax Highlighting Styles
################################
typeset -gA ZSH_HIGHLIGHT_STYLES

###############
# Core Commands
###############
ZSH_HIGHLIGHT_STYLES[command]='fg=green'
ZSH_HIGHLIGHT_STYLES[alias]='fg=magenta'
ZSH_HIGHLIGHT_STYLES[builtin]='fg=green'
ZSH_HIGHLIGHT_STYLES[function]='fg=cyan'
ZSH_HIGHLIGHT_STYLES[precommand]='fg=yellow'
ZSH_HIGHLIGHT_STYLES[hashed-command]='fg=green'

#######
# Paths
#######
ZSH_HIGHLIGHT_STYLES[path]='fg=cyan'
ZSH_HIGHLIGHT_STYLES[path_prefix]='fg=cyan'
ZSH_HIGHLIGHT_STYLES[path_approx]='fg=yellow'

#####################
# Arguments & Options
#####################
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]='fg=blue'
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]='fg=blue'
ZSH_HIGHLIGHT_STYLES[assign]='fg=magenta'

##################
# Strings & Quotes
##################
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]='fg=yellow'
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]='fg=yellow'
ZSH_HIGHLIGHT_STYLES[back-quoted-argument]='fg=magenta'
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]='fg=cyan'

####################
# Special Characters
####################
ZSH_HIGHLIGHT_STYLES[globbing]='fg=blue'
ZSH_HIGHLIGHT_STYLES[history-expansion]='fg=blue'
ZSH_HIGHLIGHT_STYLES[commandseparator]='fg=magenta'
ZSH_HIGHLIGHT_STYLES[redirection]='fg=magenta'

##########
# Brackets
##########
ZSH_HIGHLIGHT_STYLES[bracket-level-1]='fg=blue'
ZSH_HIGHLIGHT_STYLES[bracket-level-2]='fg=cyan'
ZSH_HIGHLIGHT_STYLES[bracket-level-3]='fg=magenta'
ZSH_HIGHLIGHT_STYLES[bracket-error]='fg=red,bold'

########
# Errors
########
ZSH_HIGHLIGHT_STYLES[unknown-token]='fg=red'
