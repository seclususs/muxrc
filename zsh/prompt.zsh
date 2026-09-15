############################
# Shell prompt customization
############################

setopt PROMPT_SUBST

autoload -U colors && colors

autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' %F{yellow}(%b)%f'
zstyle ':vcs_info:git:*' actionformats ' %F{yellow}(%b|%a)%f'

precmd_functions+=(vcs_info)

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

if [[ -n "$SSH_CONNECTION" ]]; then
    COLOR_USR="%F{214}"
fi

if [[ "$EUID" -eq 0 ]]; then
    PROMPT="${COLOR_ROOT}root@${TERMUX_HOST}${RESET}:${COLOR_DIR}%~${RESET}${vcs_info_msg_0_}# "
else
    PROMPT="${COLOR_USR}${TERMUX_USER}@${TERMUX_HOST}${RESET}:${COLOR_DIR}%~${RESET}${vcs_info_msg_0_}$ "
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
