#!/data/data/com.termux/files/usr/bin/bash

########################
# Binary Media Encrypter
########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

target_file="${1:-}"
if [[ -z "$target_file" ]]; then
    log_error "usage: $(basename "$0") <target_file>"
    exit 1
fi
vault_dir="$HOME/.vault"

if [[ -z "${MUXRC_CRYPT_PASS:-}" ]]; then
    log_error "password not provided."
    exit 1
fi

mkdir -p "$vault_dir"
touch "$vault_dir/.nomedia"

base_name=$(basename "$target_file")
out_file="$vault_dir/.${base_name}.enc"

trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT

start_spinner "encrypting $base_name"

if openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -in "$target_file" -out "$out_file" -pass env:MUXRC_CRYPT_PASS; then
    stop_spinner "success" "encrypted: $out_file"
else
    stop_spinner "error" "encryption failed."
    exit 1
fi

exit 0
