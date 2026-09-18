########################
# Custom shell functions
########################

#####################
# Root access wrapper
#####################
sudo() {
    local HASH_FILE="$HOME/.sudo_hash"
    local SUDO_HASH=""
    [ -f "$HASH_FILE" ] && SUDO_HASH=$(cat "$HASH_FILE" 2>/dev/null)
    
    if [[ -z "$SUDO_HASH" ]]; then
        echo "sudo: /etc/sudoers is world writable"
        return 1
    fi
    
    if [[ $# -eq 0 ]]; then
        echo "usage: sudo -h | -K | -k | -V"
        echo "usage: sudo -v [-AknS] [-g group] [-h host] [-p prompt] [-u user]"
        echo "usage: sudo -l [-AknS] [-g group] [-h host] [-p prompt] [-U user] [-u user] [command]"
        return 1
    fi
    
    if [[ "$1" =~ ^(apt|apt-get|pkg)$ ]]; then
        command "$1" "${@:2}"
        return $?
    fi
    
    local termux_prefix="/data/data/com.termux/files/usr"
    local env_vars="export PATH=/system/bin:/system/xbin:$PATH:$termux_prefix/bin; export HOME=\"$HOME\"; export TERM=\"$TERM\"; export LANG=\"$LANG\"; unset LD_LIBRARY_PATH LD_PRELOAD; cd \"$PWD\";"
    
    local attempts=0
    local max_attempts=3
    local success=0
    local current_user="${USER:-$(whoami)}"
    local user_pass
    
    if [[ "$TERMUX_FAKEROOT" == "1" ]]; then
        success=1
    else
        while (( attempts < max_attempts )); do
            print -n "[sudo] password for $current_user: "
            read -r -s user_pass
            echo ""
            
            local input_hash=$(echo -n "$user_pass" | sha256sum | awk '{print $1}')
            if [[ "$input_hash" == "$SUDO_HASH" ]]; then
                success=1
                break
            else
                echo "Sorry, try again."
                ((attempts++))
            fi
        done
    fi
    
    if (( success == 0 )); then
        echo "sudo: $max_attempts incorrect password attempts"
        return 1
    fi
    
    if [[ "$1" =~ ^(pm|cmd|am|svc|settings|content|input|dpm)$ ]]; then
        print -r "$env_vars ${(q)@}" | command su
    else
        local su_pid
        
        command su -c "$env_vars exec ${(q)@}" &
        su_pid=$!
        
        trap '
            local child line entry ppid
            for child in /proc/<1->; do
                line=$(<"$child/status") 2>/dev/null || continue
                for entry in "${(f)line}"; do
                    if [[ "$entry" == PPid:* ]]; then
                        ppid="${entry#PPid:}"
                        ppid="${ppid//[[:space:]]/}"
                        [[ "$ppid" == "$su_pid" ]] && kill -INT "${child:t}" 2>/dev/null
                        break
                    fi
                done
            done
        ' INT
        
        wait "$su_pid"
        local exit_code=$?
        trap - INT
        return $exit_code
    fi
}

########################
# Fake Root Mode Wrapper
########################
su() {
    if [[ $# -gt 0 ]]; then
        command su "$@"
        return $?
    fi
    
    if [[ "$TERMUX_FAKEROOT" == "1" ]]; then
        TERMUX_FAKEROOT=1 zsh
        return 0
    fi
    
    local HASH_FILE="$HOME/.sudo_hash"
    local SUDO_HASH=""
    [ -f "$HASH_FILE" ] && SUDO_HASH=$(cat "$HASH_FILE" 2>/dev/null)
    
    if [[ -z "$SUDO_HASH" ]]; then
        echo "su: Authentication service cannot retrieve authentication info"
        return 1
    fi
    
    local user_pass
    print -n "Password: "
    read -r -s user_pass
    echo ""
    
    local input_hash=$(echo -n "$user_pass" | sha256sum | awk '{print $1}')
    if [[ "$input_hash" != "$SUDO_HASH" ]]; then
        echo "su: Authentication failure"
        return 1
    fi
    
    TERMUX_FAKEROOT=1 zsh
}

#########################
# Service manager wrapper
#########################
systemctl() {
    if [[ $# -lt 2 ]]; then
        echo "Usage: systemctl {start|stop|restart|status|enable|disable} <service>"
        return 1
    fi
    
    local action="$1"
    local service="$2"
    
    case "$action" in
        start) command sv up "$service" 2>/dev/null ;;
        stop) command sv down "$service" 2>/dev/null ;;
        restart) command sv restart "$service" 2>/dev/null ;;
        status) command sv status "$service" ;;
        enable)
            if [ -d "$PREFIX/share/termux-services/$service" ]; then
                ln -sf "$PREFIX/share/termux-services/$service" "$PREFIX/var/service/"
                echo "Created symlink /etc/systemd/system/multi-user.target.wants/${service}.service → /lib/systemd/system/${service}.service."
            else
                echo "Failed to enable unit: Unit file ${service}.service does not exist."
            fi
        ;;
        disable)
            rm -f "$PREFIX/var/service/$service"
            echo "Removed /etc/systemd/system/multi-user.target.wants/${service}.service."
        ;;
        *)
            echo "Unknown operation '$action'."
            return 1
        ;;
    esac
}

#########################
# Package manager wrapper
#########################
apt() {
    if [[ "$1" =~ ^(install|search|update|upgrade|remove|autoremove|clean)$ ]]; then
        command pkg "$@"
    else
        command apt "$@"
    fi
}

####################
# Legacy apt wrapper
####################
apt-get() { apt "$@"; }

#######################
# Fallback ping command
#######################
ping() {
    if command ping -c 1 "$1" >/dev/null 2>&1; then
        command ping -c 4 "$@"
    else
        su -c "/system/bin/ping -c 4 ${(q)@}"
    fi
}

###########################
# Safe permissions modifier
###########################
chmod() {
    if [[ "$*" == *"/sdcard/"* || "$*" == *"/storage/emulated/"* ]]; then
        return 0
    fi
    command chmod "$@"
}

##########################
# Dummy ownership function
##########################
chown() {
    return 0
}

#####################
# File opener wrapper
#####################
xdg-open() {
    if command -v termux-open >/dev/null 2>&1; then
        command termux-open "$@"
    else
        echo "xdg-open: command not found. Please run: apt install termux-api"
        return 127
    fi
}

#############################
# Universal archive extractor
#############################
ex() {
    if [[ -f $1 ]]; then
        case $1 in
            *.tar.bz2)   tar xjf "$1"   ;;
            *.tar.gz)    tar xzf "$1"   ;;
            *.bz2)       bunzip2 "$1"   ;;
            *.rar)       unrar x "$1"   ;;
            *.gz)        gunzip "$1"    ;;
            *.tar)       tar xf "$1"    ;;
            *.tbz2)      tar xjf "$1"   ;;
            *.tgz)       tar xzf "$1"   ;;
            *.zip)       unzip "$1"     ;;
            *.Z)         uncompress "$1";;
            *.7z)        7z x "$1"      ;;
            *)           echo "ex: '$1' has unknown archive format." ;;
        esac
    else
        echo "ex: '$1' is not a valid file."
    fi
}

###########################
# Command not found handler
###########################
command_not_found_handler() {
    local cmd="$1"
    local matches
    matches=$(pkg search "$cmd" 2>/dev/null | grep "^$cmd/" )
    
    if [[ -n "$matches" ]]; then
        echo "zsh: command not found: $cmd"
        echo "Did you mean to install it? Try: pkg install $cmd"
    else
        echo "zsh: command not found: $cmd"
    fi
    
    return 127
}

###########################
# Notification task wrapper
###########################
notify-task() {
    (( $# == 0 )) && { echo "usage: notify-task <cmd> [args...]"; return 1; }
    
    local label="$*"
    local start=$(date +%s)
    
    "$@"
    local code=$?
    local secs=$(( $(date +%s) - start ))
    local status="done in ${secs}s"
    (( code != 0 )) && status="failed (exit ${code}) after ${secs}s"
    
    termux-vibrate -d 250 >/dev/null 2>&1
    termux-notification --id notify-task --title "${label:0:40}" --content "$status"
    return $code
}

###########################
# Clipboard history helpers
###########################
CLIP_HISTORY_FILE="$HOME/.cache/clip_history.log"

clip-save() {
    mkdir -p "${CLIP_HISTORY_FILE:h}"
    local cur=$(termux-clipboard-get 2>/dev/null)
    [[ -z "$cur" ]] && return
    [[ "$(tail -n1 "$CLIP_HISTORY_FILE" 2>/dev/null)" != "$cur" ]] && echo "$cur" >> "$CLIP_HISTORY_FILE"
}

clip-watch() {
    while true; do clip-save; sleep 2; done
}

clip-pick() {
    [[ -f "$CLIP_HISTORY_FILE" ]] || return 1
    local pick=$(tac "$CLIP_HISTORY_FILE" | fzf --prompt="clip> ")
    [[ -n "$pick" ]] && echo -n "$pick" | termux-clipboard-set && termux-toast "copied"
}

########################
# Safe trash and untrash
########################
TRASH_DIR="$HOME/.trash"

trash() {
    mkdir -p "$TRASH_DIR"
    for f in "$@"; do
        [[ -e "$f" ]] || { echo "trash: no such file: $f"; continue; }
        mv -- "$f" "$TRASH_DIR/${f:t}.$(date +%s)"
    done
}

untrash() {
    local item=$(ls -1t "$TRASH_DIR" 2>/dev/null | fzf --prompt="restore> ") || return
    [[ -n "$item" ]] && mv -- "$TRASH_DIR/$item" "./${item%.*}"
}

#####################
# Network info helper
#####################
net-info() {
    command -v termux-wifi-connectioninfo >/dev/null 2>&1 || { echo "net-info: needs termux-api"; return 1; }
    local ip=$(termux-wifi-connectioninfo | jq -r '.ip // empty')
    [[ -z "$ip" || "$ip" == null ]] && { echo "net-info: no wifi ip"; return 1; }
    local cmd="ssh ${USER:-$(whoami)}@${ip} -p 8022"
    echo "$cmd"
    termux-toast "$cmd"
}

#############################
# Gemini command auto-correct
#############################
_gemini_env="$HOME/.gemini_ai_env"
_gemini_cooldown="$HOME/.cache/gemini_cooldown"
_gemini_load() { [[ -f "$_gemini_env" ]] && source "$_gemini_env" }

_gemini_query() {
    local failed="$1"
    _gemini_load
    [[ "$AI_AUTOCORRECT_ENABLED" == 1 && -n "$GEMINI_API_KEY" ]] || return
    command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 || return
    
    mkdir -p "${_gemini_cooldown:h}"
    local now=$(date +%s) last=0
    [[ -f "$_gemini_cooldown" ]] && last=$(cat "$_gemini_cooldown")
    (( now - last >= 8 )) || return
    echo "$now" > "$_gemini_cooldown"
    
    local payload=$(jq -n --arg c "$failed" \
    '{contents:[{parts:[{text:("shell command failed: \"" + $c + "\". guess the corrected command line the user meant, including any arguments. reply with just the corrected command, nothing else.")}]}]}')
    
    local suggestion=$(curl -s --max-time 4 \
        -H "x-goog-api-key: $GEMINI_API_KEY" \
        -H "Content-Type: application/json" \
        -X POST "https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL:-gemini-3.5-flash-lite}:generateContent" \
    -d "$payload" 2>/dev/null | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null | xargs)
    
    [[ -n "$suggestion" && "$suggestion" != "$failed" ]] && echo "$suggestion"
}

(( $+functions[command_not_found_handler] )) && \
functions -c command_not_found_handler _cnf_original

command_not_found_handler() {
    local cmd="$1"
    local suggestion=$(_gemini_query "$*")
    
    if [[ -n "$suggestion" ]]; then
        echo "zsh: command not found: $cmd"
        echo "gemini: $suggestion"
        if read -q "?run it? [y/N] "; then
            echo; eval "$suggestion"; return $?
        fi
        echo
    fi
    
    if (( $+functions[_cnf_original] )); then
        _cnf_original "$cmd"
    else
        echo "zsh: command not found: $cmd"
        return 127
    fi
}

#################################
# Gemini sub-command auto-correct
#################################
typeset -ga _gemini_skip_cmds=(grep egrep fgrep diff cmp test true false which type)

_gemini_postcmd_check() {
    local ret=$?
    (( ret == 0 || ret == 127 )) && return
    
    local lastcmd="$(fc -ln -1)"
    [[ -z "$lastcmd" ]] && return
    
    local head="${${(z)lastcmd}[1]}"
    (( ${_gemini_skip_cmds[(Ie)$head]} )) && return
    
    local suggestion=$(_gemini_query "$lastcmd")
    [[ -z "$suggestion" ]] && return
    
    echo "gemini: $suggestion"
    if read -q "?run it? [y/N] "; then
        echo; eval "$suggestion"
    else
        echo
    fi
}
precmd_functions+=(_gemini_postcmd_check)

########################
# AI auto-correct toggle
########################
ai-toggle() {
    mkdir -p "${_gemini_env:h}"; touch "$_gemini_env"
    _gemini_load
    if [[ "$AI_AUTOCORRECT_ENABLED" == 1 ]]; then
        sed -i 's/^AI_AUTOCORRECT_ENABLED=.*/AI_AUTOCORRECT_ENABLED=0/' "$_gemini_env"
        echo "gemini auto-correct: off"
    else
        grep -q AI_AUTOCORRECT_ENABLED "$_gemini_env" \
        && sed -i 's/^AI_AUTOCORRECT_ENABLED=.*/AI_AUTOCORRECT_ENABLED=1/' "$_gemini_env" \
        || echo "AI_AUTOCORRECT_ENABLED=1" >> "$_gemini_env"
        echo "gemini auto-correct: on"
    fi
}
