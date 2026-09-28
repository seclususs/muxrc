#!/data/data/com.termux/files/usr/bin/bash

###################
# Tor Privacy Setup
###################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

action="${1:-start}"

OPSEC_DIR="$HOME/.muxrc/run"
TORRC="$OPSEC_DIR/torrc"
TOR_DATA="$OPSEC_DIR/tor_data"
PID_FILE="$OPSEC_DIR/tor.pid"

if [[ "$action" == "start" ]]; then
    mkdir -p "$TOR_DATA"
    
    log_info "generating config..."
    cat <<EOF > "$TORRC"
SocksPort 127.0.0.1:9050
DNSPort 127.0.0.1:5353
DataDirectory $TOR_DATA
PidFile $PID_FILE
EOF
    
    log_info "spawning tor..."
    tor -f "$TORRC" > "$OPSEC_DIR/tor.log" 2>&1 &
    
    start_spinner "waiting for tor"
    sleep 2
    
    if [[ -f "$PID_FILE" ]]; then
        tpid=$(cat "$PID_FILE")
        stop_spinner "success" "tor spawned (pid: $tpid). proxy: 127.0.0.1:9050"
    else
        stop_spinner "error" "failed to spawn tor. check log"
        exit 1
    fi
    
    elif [[ "$action" == "stop" ]]; then
    if [[ ! -f "$PID_FILE" ]]; then
        log_warn "pid file not found in $opsec_dir."
        log_warn "assume tor is stopped."
        exit 0
    fi
    
    tpid=$(cat "$PID_FILE")
    
    if kill -0 "$tpid" 2>/dev/null; then
        trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT
        start_spinner "terminating tor (pid: $tpid)"
        kill -INT "$tpid"
        
        for i in {1..10}; do
            if ! kill -0 "$tpid" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        
        if kill -0 "$tpid" 2>/dev/null; then
            stop_spinner "error" "force killing tor..."
            kill -9 "$tpid"
        else
            stop_spinner "success" "tor terminated."
        fi
        trap - EXIT
    else
        log_warn "tor $tpid no longer running."
    fi
    
    trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT
    start_spinner "shredding state"
    [[ -f "$TORRC" ]] && shred -u "$TORRC" 2>/dev/null || true
    [[ -f "$PID_FILE" ]] && shred -u "$PID_FILE" 2>/dev/null || true
    [[ -f "$OPSEC_DIR/tor.log" ]] && shred -u "$OPSEC_DIR/tor.log" 2>/dev/null || true
    
    if [[ -d "$TOR_DATA" ]]; then
        find "$TOR_DATA" -type f -exec shred -u {} \; 2>/dev/null || true
        rm -rf "$TOR_DATA"
    fi
    
    stop_spinner "success" "tor stopped and shredded."
    trap - EXIT
else
    log_error "usage: tor-setup.sh {start|stop}"
    exit 1
fi

exit 0
