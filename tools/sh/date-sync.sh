#!/data/data/com.termux/files/usr/bin/bash

################
# Meta Date Sync
################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

target="${1:-}"

if [[ -z "$target" ]]; then
    log_error "usage: date-sync.sh <file_or_directory>"
    exit 1
fi

if [[ ! -e "$target" ]]; then
    log_error "target '$target' not found"
    exit 1
fi

if ! command -v exiftool >/dev/null 2>&1; then
    log_error "exiftool not installed. run: pkg install exiftool"
    exit 1
fi

start_spinner "syncing metadata dates"

exiftool -r -P -overwrite_original_in_place -d "%Y:%m:%d %H:%M:%S" -m -q \
"-AllDates<FileModifyDate" \
"-TrackCreateDate<FileModifyDate" \
"-TrackModifyDate<FileModifyDate" \
"-MediaCreateDate<FileModifyDate" \
"-MediaModifyDate<FileModifyDate" \
"-CreationTime<FileModifyDate" \
"$target" >/dev/null 2>&1 || true

stop_spinner "success" "metadata dates synced."

exit 0
