#!/data/data/com.termux/files/usr/bin/bash

########################
# Binary Media Encrypter
########################
set -euo pipefail

target_file="${1:-}"
if [[ -z "$target_file" ]]; then
    echo "Usage: $(basename "$0") <target_file>"
    exit 1
fi
vault_dir="$HOME/.vault"

if [[ -z "${MUXRC_CRYPT_PASS:-}" ]]; then
    echo "Error: Password not provided."
    exit 1
fi

mkdir -p "$vault_dir"
touch "$vault_dir/.nomedia"

base_name=$(basename "$target_file")
out_file="$vault_dir/.${base_name}.enc"

echo "[*] Encrypting $base_name..."

openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -in "$target_file" -out "$out_file" -pass env:MUXRC_CRYPT_PASS

echo "[+] Success! File encrypted and hidden at: $out_file"
echo "[+] You may now safely delete the original file if desired."
