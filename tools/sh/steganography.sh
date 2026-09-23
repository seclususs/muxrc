#!/data/data/com.termux/files/usr/bin/bash

#####################
# Steganography Vault
#####################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

OPSEC_DIR="$HOME/.muxrc/run"
EXTRACT_DIR="$HOME/muxrc/tools/output/extracted"

mkdir -p "$OPSEC_DIR"
mkdir -p "$EXTRACT_DIR"

echo "steganography vault"
echo "1) embed data"
echo "2) extract data"
echo "0) exit"
read -r -p "select [1/2/0]: " opt

if [[ "$opt" == "1" ]]; then
    read -r -p "path to cover image: " cover
    if [[ ! -f "$cover" ]]; then
        log_error "cover image not found."
        exit 1
    fi
    
    echo "what to embed?"
    echo "1) text string"
    echo "2) file"
    read -r -p "select [1/2]: " embed_opt
    
    embed_file=""
    if [[ "$embed_opt" == "1" ]]; then
        read -r -p "text to hide: " secret_text
        embed_file="$OPSEC_DIR/secret-payload.txt"
        echo "$secret_text" > "$embed_file"
        elif [[ "$embed_opt" == "2" ]]; then
        read -r -p "path to file to hide: " embed_file
        if [[ ! -f "$embed_file" ]]; then
            log_error "file to embed not found."
            exit 1
        fi
    else
        log_error "invalid option."
        exit 1
    fi
    
    read -r -s -p "passphrase: " pass
    echo
    if [[ -z "$pass" ]]; then
        log_error "passphrase cannot be empty."
        [[ "$embed_opt" == "1" ]] && shred -u "$embed_file" 2>/dev/null
        exit 1
    fi
    
    read -r -s -p "confirm passphrase: " pass_conf
    echo
    if [[ "$pass" != "$pass_conf" ]]; then
        log_error "passphrases do not match."
        [[ "$embed_opt" == "1" ]] && shred -u "$embed_file" 2>/dev/null
        exit 1
    fi
    
    log_info "embedding data..."
    if steghide embed -ef "$embed_file" -cf "$cover" -p "$pass"; then
        log_success "embedded into $cover"
    else
        log_error "steghide failed."
    fi
    
    # OPSEC: Shred temporary payload
    if [[ "$embed_opt" == "1" && -f "$embed_file" ]]; then
        shred -u "$embed_file"
    fi
    
    elif [[ "$opt" == "0" ]]; then
    log_info "exiting..."
    exit 0
    elif [[ "$opt" == "2" ]]; then
    read -r -p "path to stego-image: " stego_img
    if [[ ! -f "$stego_img" ]]; then
        log_error "stego-image not found."
        exit 1
    fi
    
    # Resolve absolute path before pushd
    stego_img_abs=$(realpath "$stego_img")
    
    read -r -s -p "decryption passphrase: " pass
    echo
    if [[ -z "$pass" ]]; then
        log_error "passphrase cannot be empty."
        exit 1
    fi
    
    log_info "extracting data..."
    pushd "$EXTRACT_DIR" >/dev/null
    if steghide extract -sf "$stego_img_abs" -f -p "$pass"; then
        log_success "extracted to $EXTRACT_DIR"
    else
        log_error "extraction failed."
    fi
    popd >/dev/null
else
    log_error "invalid option."
    exit 1
fi

exit 0
