#!/data/data/com.termux/files/usr/bin/bash

##########################
# Permanent Media Shredder
##########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

target_file="${1:-}"
if [[ -z "$target_file" ]]; then
    log_error "Usage: $(basename "$0") <target_file>"
    exit 1
fi

echo "========================================="
echo "             !!! WARNING !!!             "
echo "========================================="
echo " You will PERMANENTLY DESTROY this file: "
echo " $target_file"
echo "========================================="
echo ""

read -r -p "Type exactly 'SHRED' to execute: " confirm

if [[ "$confirm" == "SHRED" ]]; then
    log_info "Shredding file in progress..."
    shred -u -z -n 3 "$target_file"
    log_success "Done. File completely shredded."
else
    log_warn "Shred aborted by user."
    exit 1
fi
