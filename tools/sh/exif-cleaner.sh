#!/data/data/com.termux/files/usr/bin/bash

#######################
# EXIF Metadata Cleaner
#######################
set -euo pipefail

target_dir="$1"
output_dir="$HOME/muxrc/tools/output/stripped"

exiftool -all= -o "$output_dir/" "$target_dir" || true
