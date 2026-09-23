#!/data/data/com.termux/files/usr/bin/bash

#######################
# EXIF Metadata Cleaner
#######################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

target_dir="${1:-}"
if [[ -z "$target_dir" ]]; then
    log_error "Usage: $(basename "$0") <target_directory>"
    exit 1
fi
output_dir="$HOME/muxrc/tools/output/stripped"

exiftool -all= -o "$output_dir/" "$target_dir" || true
