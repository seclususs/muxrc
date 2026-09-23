#!/data/data/com.termux/files/usr/bin/bash

########################
# Duplicate File Cleaner
########################
set -euo pipefail

target_dir="${1:-}"
if [[ -z "$target_dir" ]]; then
    echo "Usage: $(basename "$0") <directory>"
    exit 1
fi

fdupes -rd "$target_dir"
