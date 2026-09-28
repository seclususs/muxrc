#!/data/data/com.termux/files/usr/bin/bash

#####################
# Steganography Vault
#####################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

OPSEC_DIR="$HOME/.muxrc/run"
EXTRACT_DIR="$HOME/muxrc/tools/output/extracted"

mkdir -p "$OPSEC_DIR"
mkdir -p "$EXTRACT_DIR"

echo "steganography vault"
echo "1) embed data"
echo "2) extract data"
echo "0) exit"
log_prompt "select [1/2/0]: "
read -r opt

if [[ "$opt" == "1" ]]; then
    log_prompt "path to cover image: "
    read -r cover
    if [[ ! -f "$cover" ]]; then
        log_error "cover image not found."
        exit 1
    fi
    
    echo "what to embed?"
    echo "1) text string"
    echo "2) file"
    log_prompt "select [1/2]: "
    read -r embed_opt
    
    embed_file=""
    if [[ "$embed_opt" == "1" ]]; then
        log_prompt "text to hide: "
        read -r secret_text
        embed_file="$OPSEC_DIR/secret-payload.txt"
        echo "$secret_text" > "$embed_file"
        elif [[ "$embed_opt" == "2" ]]; then
        log_prompt "path to file to hide: "
        read -r embed_file
        if [[ ! -f "$embed_file" ]]; then
            log_error "file to embed not found."
            exit 1
        fi
    else
        log_error "invalid option."
        exit 1
    fi
    
    log_prompt "passphrase: "
    read -r -s pass
    echo
    if [[ -z "$pass" ]]; then
        log_error "passphrase cannot be empty."
        [[ "$embed_opt" == "1" ]] && shred -u "$embed_file" 2>/dev/null
        exit 1
    fi
    
    log_prompt "confirm passphrase: "
    read -r -s pass_conf
    echo
    if [[ "$pass" != "$pass_conf" ]]; then
        log_error "passphrases do not match."
        [[ "$embed_opt" == "1" ]] && shred -u "$embed_file" 2>/dev/null
        exit 1
    fi
    
    trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT
    start_spinner "embedding data"
    if steghide embed -ef "$embed_file" -cf "$cover" -p "$pass"; then
        stop_spinner "success" "embedded into $cover"
    else
        stop_spinner "error" "steghide failed."
    fi
    trap - EXIT
    
    # OPSEC: Shred temporary payload
    if [[ "$embed_opt" == "1" && -f "$embed_file" ]]; then
        shred -u "$embed_file"
    fi
    
    elif [[ "$opt" == "0" ]]; then
    log_warn "exiting..."
    exit 0
    elif [[ "$opt" == "2" ]]; then
    log_prompt "path to stego-image: "
    read -r stego_img
    if [[ ! -f "$stego_img" ]]; then
        log_error "stego-image not found."
        exit 1
    fi
    
    # Resolve absolute path before pushd
    stego_img_abs=$(realpath "$stego_img")
    
    log_prompt "decryption passphrase: "
    read -r -s pass
    echo
    if [[ -z "$pass" ]]; then
        log_error "passphrase cannot be empty."
        exit 1
    fi
    
    trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT
    start_spinner "extracting data"
    pushd "$EXTRACT_DIR" >/dev/null
    if steghide extract -sf "$stego_img_abs" -f -p "$pass"; then
        stop_spinner "success" "extracted to $EXTRACT_DIR"
    else
        stop_spinner "error" "extraction failed."
    fi
    popd >/dev/null
    trap - EXIT
else
    log_error "invalid option."
    exit 1
fi

exit 0
