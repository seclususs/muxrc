############################
# Shell prompt customization
############################

setopt PROMPT_SUBST

autoload -U colors && colors

######################
# Lightweight git info
######################
typeset -g _muxrc_git_info=""

_prompt_git_info() {
    _muxrc_git_info=""
    local raw
    raw=$(git status --porcelain -b 2>/dev/null) || return
    local header="${raw%%$'\n'*}"
    local branch="${header#\#\# }"
    
    if [[ "$branch" == *"(no branch)"* ]]; then
        branch="detached"
        elif [[ "$branch" == "No commits yet on "* ]]; then
        branch="${branch#No commits yet on }"
    else
        branch="${branch%%...*}"
    fi
    
    local dirty=""
    [[ "$raw" != "$header" ]] && dirty="✚"
    
    if [[ -n "$dirty" ]]; then
        _muxrc_git_info=" %F{yellow}(${branch}"
        _muxrc_git_info+=" %F{#e06c75}${dirty}%F{yellow})%f"
    else
        _muxrc_git_info=" %F{yellow}(${branch})%f"
    fi
}
precmd_functions+=(_prompt_git_info)

zmodload zsh/datetime

preexec_track_duration() { _cmd_start=$EPOCHSECONDS }
preexec_functions+=(preexec_track_duration)

precmd_status_line() {
    local exit_code=$?
    local duration=""
    if [[ -n "$_cmd_start" ]]; then
        local elapsed=$(( EPOCHSECONDS - _cmd_start ))
        (( elapsed >= 5 )) && duration=" %F{yellow}${elapsed}s%f"
        unset _cmd_start
    fi
    
    if (( exit_code != 0 )); then
        RPROMPT="%F{196}✗ ${exit_code}%f${duration}"
    else
        RPROMPT="${duration}"
    fi
}
precmd_functions+=(precmd_status_line)

TERMUX_USER=${USER:-user}
TERMUX_HOST="termux"

COLOR_USR="%F{114}"
COLOR_DIR="%F{39}"
COLOR_ROOT="%F{196}"
RESET="%f"

if [[ -n "${SSH_CONNECTION-}" ]]; then
    COLOR_USR="%F{214}"
fi

if [[ "$EUID" -eq 0 ]]; then
    PROMPT='${COLOR_ROOT}root@${TERMUX_HOST}${RESET}:${COLOR_DIR}%~${RESET}${_muxrc_git_info}# '
else
    PROMPT='${COLOR_USR}${TERMUX_USER}@${TERMUX_HOST}${RESET}:${COLOR_DIR}%~${RESET}${_muxrc_git_info}$ '
fi

PS2="${COLOR_USR}>${RESET} "

precmd_set_title() {
    print -Pn "\e]2;%~\a"
}
precmd_functions+=(precmd_set_title)

preexec_set_title() {
    print -Pn "\e]2;%~: $1\a"
}
preexec_functions+=(preexec_set_title)

#############################
# Transient prompt (condense)
#############################
typeset -g _PROMPT_FULL="$PROMPT"
_prompt_restore() { PROMPT="$_PROMPT_FULL" }
precmd_functions+=(_prompt_restore)

_prompt_condense() {
    [[ -z $BUFFER ]] && return
    PROMPT='%F{#5c6370}%*%f ❯ '
    RPROMPT=''
    zle && zle .reset-prompt
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget zle-line-finish _prompt_condense
