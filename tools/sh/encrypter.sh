#!/data/data/com.termux/files/usr/bin/bash

########################
# Binary Media Encrypter
########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

target_file="${1:-}"
if [[ -z "$target_file" ]]; then
    log_error "Usage: $(basename "$0") <target_file>"
    exit 1
fi
vault_dir="$HOME/.vault"

if [[ -z "${MUXRC_CRYPT_PASS:-}" ]]; then
    log_error "Error: Password not provided."
    exit 1
fi

mkdir -p "$vault_dir"
touch "$vault_dir/.nomedia"

base_name=$(basename "$target_file")
out_file="$vault_dir/.${base_name}.enc"

log_info "Encrypting $base_name..."

openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -in "$target_file" -out "$out_file" -pass env:MUXRC_CRYPT_PASS

log_success "Success! File encrypted and hidden at: $out_file"
log_success "You may now safely delete the original file if desired."
