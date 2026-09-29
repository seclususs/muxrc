#!/usr/bin/env bash

#########
# loggers
#########
log_info() { echo -e "${C_BLUE:-}[*]${C_RESET:-} $*"; }
log_success() { echo -e "${C_GREEN:-}[+]${C_RESET:-} $*"; }
log_warn() { echo -e "${C_YELLOW:-}[-]${C_RESET:-} $*"; }
log_error() { echo -e "${C_RED:-}[!]${C_RESET:-} $*" >&2; }
log_prompt() { echo -ne "${C_CYAN:-}[?]${C_RESET:-} $*"; }

#########
# Spinner
#########
SPINNER_PID=""
start_spinner() {
    local msg="$1"
    local frames=("\\" "|" "/" "-")
    (
        while true; do
            for frame in "${frames[@]}"; do
                echo -ne "\r${C_BLUE:-}[*]${C_RESET:-} ${msg}... ${frame}"
                sleep 0.1
            done
        done
    ) &
    SPINNER_PID=$!
}

stop_spinner() {
    local spin_status="$1"
    local msg="$2"
    if [[ -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" >/dev/null 2>&1
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    echo -ne "\r\033[K"
    if [[ "$spin_status" == "success" ]]; then
        log_success "$msg"
        elif [[ "$spin_status" == "error" ]]; then
        log_error "$msg"
    else
        log_info "$msg"
    fi
}
