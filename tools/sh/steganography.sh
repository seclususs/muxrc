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

echo "==========================="
echo " Steganography Data Vault  "
echo "==========================="
echo "1. Embed Data"
echo "2. Extract Data"
echo "==========================="
read -r -p "Select option [1/2]: " opt

if [[ "$opt" == "1" ]]; then
    read -r -p "Path to cover image: " cover
    if [[ ! -f "$cover" ]]; then
        log_error "Error: Cover image not found."
        exit 1
    fi
    
    echo "What do you want to embed?"
    echo "1. A text string (typed now)"
    echo "2. An existing file"
    read -r -p "Select option [1/2]: " embed_opt
    
    embed_file=""
    if [[ "$embed_opt" == "1" ]]; then
        read -r -p "Enter text to hide: " secret_text
        embed_file="$OPSEC_DIR/secret-payload.txt"
        echo "$secret_text" > "$embed_file"
        elif [[ "$embed_opt" == "2" ]]; then
        read -r -p "Path to file to hide: " embed_file
        if [[ ! -f "$embed_file" ]]; then
            log_error "Error: File to embed not found."
            exit 1
        fi
    else
        log_error "Invalid option."
        exit 1
    fi
    
    read -r -s -p "Enter secure passphrase: " pass
    echo
    if [[ -z "$pass" ]]; then
        log_error "Error: Passphrase cannot be empty."
        [[ "$embed_opt" == "1" ]] && shred -u "$embed_file" 2>/dev/null
        exit 1
    fi
    
    read -r -s -p "Confirm passphrase: " pass_conf
    echo
    if [[ "$pass" != "$pass_conf" ]]; then
        log_error "Error: Passphrases do not match."
        [[ "$embed_opt" == "1" ]] && shred -u "$embed_file" 2>/dev/null
        exit 1
    fi
    
    log_info "Embedding data..."
    if steghide embed -ef "$embed_file" -cf "$cover" -p "$pass"; then
        log_success "Data successfully embedded into $cover"
    else
        log_error "Steghide failed."
    fi
    
    # OPSEC: Shred temporary payload
    if [[ "$embed_opt" == "1" && -f "$embed_file" ]]; then
        shred -u "$embed_file"
    fi
    
    elif [[ "$opt" == "2" ]]; then
    read -r -p "Path to stego-image: " stego_img
    if [[ ! -f "$stego_img" ]]; then
        log_error "Error: Stego-image not found."
        exit 1
    fi
    
    # Resolve absolute path before pushd
    stego_img_abs=$(realpath "$stego_img")
    
    read -r -s -p "Enter decryption passphrase: " pass
    echo
    if [[ -z "$pass" ]]; then
        log_error "Error: Passphrase cannot be empty."
        exit 1
    fi
    
    log_info "Extracting data..."
    pushd "$EXTRACT_DIR" >/dev/null
    if steghide extract -sf "$stego_img_abs" -f -p "$pass"; then
        log_success "Data successfully extracted to $EXTRACT_DIR"
    else
        log_error "Extraction failed."
    fi
    popd >/dev/null
else
    log_error "Invalid option."
    exit 1
fi
