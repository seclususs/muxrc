#!/data/data/com.termux/files/usr/bin/bash

###################
# Tor Privacy Setup
###################
set -euo pipefail

action="${1:-start}"

OPSEC_DIR="$HOME/.muxrc/run"
TORRC="$OPSEC_DIR/torrc"
TOR_DATA="$OPSEC_DIR/tor_data"
PID_FILE="$OPSEC_DIR/tor.pid"

if [[ "$action" == "start" ]]; then
    mkdir -p "$TOR_DATA"
    
    echo "[*] Generating Tor configuration..."
    cat <<EOF > "$TORRC"
SocksPort 127.0.0.1:9050
DNSPort 127.0.0.1:5353
DataDirectory $TOR_DATA
PidFile $PID_FILE
EOF
    
    echo "[*] Spawning Tor daemon in background..."
    tor -f "$TORRC" > "$OPSEC_DIR/tor.log" 2>&1 &
    
    echo "[*] Waiting for Tor to write PID file..."
    sleep 2
    
    if [[ -f "$PID_FILE" ]]; then
        tpid=$(cat "$PID_FILE")
        echo "[+] Tor successfully spawned PID: $tpid. SOCKS5 proxy active on 127.0.0.1:9050"
    else
        echo "[-] Error: Tor daemon failed to spawn. Check $OPSEC_DIR/tor.log"
        exit 1
    fi
    
    elif [[ "$action" == "stop" ]]; then
    if [[ ! -f "$PID_FILE" ]]; then
        echo "[-] Tor PID file not found in $OPSEC_DIR."
        echo "[-] Assume Tor is not running."
        exit 0
    fi
    
    tpid=$(cat "$PID_FILE")
    
    if kill -0 "$tpid" 2>/dev/null; then
        echo "[*] Terminating Tor daemon PID: $tpid..."
        kill -INT "$tpid"
        
        for i in {1..10}; do
            if ! kill -0 "$tpid" 2>/dev/null; then
                break
            fi
            sleep 1
        done
        
        if kill -0 "$tpid" 2>/dev/null; then
            echo "[!] Tor didn't exit gracefully. Forcing kill..."
            kill -9 "$tpid"
        fi
    else
        echo "[-] Tor process $tpid is no longer running."
    fi
    
    echo "[*] Shredding ephemeral configuration and data..."
    [[ -f "$TORRC" ]] && shred -u "$TORRC" 2>/dev/null || true
    [[ -f "$PID_FILE" ]] && shred -u "$PID_FILE" 2>/dev/null || true
    [[ -f "$OPSEC_DIR/tor.log" ]] && shred -u "$OPSEC_DIR/tor.log" 2>/dev/null || true
    
    if [[ -d "$TOR_DATA" ]]; then
        find "$TOR_DATA" -type f -exec shred -u {} \; 2>/dev/null || true
        rm -rf "$TOR_DATA"
    fi
    
    echo "[+] Tor stopped and state files physically destroyed."
else
    echo "Usage: tor-setup.sh {start|stop}"
    exit 1
fi
