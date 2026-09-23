#!/data/data/com.termux/files/usr/bin/bash

########################
# Duplicate File Cleaner
########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

target_dir="${1:-}"
if [[ -z "$target_dir" ]]; then
    log_error "Usage: $(basename "$0") <directory>"
    exit 1
fi

if [[ ! -d "$target_dir" ]]; then
    log_error "Error: Directory '$target_dir' not found."
    exit 1
fi

log_info "Scanning for files in '$target_dir'..."

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

find "$target_dir" -type f -print0 | xargs -0 stat -c '%s %n' > "$tmp_dir/all_files.txt"

awk '{size=$1; count[size]++} END {for(s in count) if(count[s]>1) print s}' "$tmp_dir/all_files.txt" > "$tmp_dir/dup_sizes.txt"

if [[ ! -s "$tmp_dir/dup_sizes.txt" ]]; then
    log_success "No duplicate file sizes found. Directory is clean."
    exit 0
fi

log_info "Hashing files with identical sizes..."

awk 'NR==FNR {dup[$1]; next} $1 in dup { print substr($0, length($1)+2) }' "$tmp_dir/dup_sizes.txt" "$tmp_dir/all_files.txt" | \
tr '\n' '\0' | xargs -0 sha256sum > "$tmp_dir/hashed.txt"

awk '{hash=$1; count[hash]++} END {for(h in count) if(count[h]>1) print h}' "$tmp_dir/hashed.txt" > "$tmp_dir/dup_hashes.txt"

if [[ ! -s "$tmp_dir/dup_hashes.txt" ]]; then
    log_success "No identical files found after hash verification."
    exit 0
fi

echo ""
log_warn "Duplicate files found:"

> "$tmp_dir/to_delete.txt"
total_dupe_sets=0

while read -r hash; do
    total_dupe_sets=$((total_dupe_sets + 1))
    echo "[Group $total_dupe_sets] Hash: ${hash:0:8}..."
    
    awk -v h="$hash" '$1==h { print substr($0, length($1)+3) }' "$tmp_dir/hashed.txt" > "$tmp_dir/current_set.txt"
    
    mapfile -t files < "$tmp_dir/current_set.txt"
    
    log_success "KEEP: ${files[0]}"
    
    for i in "${!files[@]}"; do
        if [[ $i -ne 0 ]]; then
            log_warn "DEL : ${files[$i]}"
            echo "${files[$i]}" >> "$tmp_dir/to_delete.txt"
        fi
    done
    echo ""
done < "$tmp_dir/dup_hashes.txt"

total_to_delete=$(wc -l < "$tmp_dir/to_delete.txt")

read -r -p "    [?] Do you want to clean these $total_to_delete duplicate files? [y/N]: " confirm

if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    log_info "Cleaning up duplicates..."
    while IFS= read -r file; do
        rm -f "$file"
    done < "$tmp_dir/to_delete.txt"
    log_success "Successfully deleted $total_to_delete duplicate files."
else
    log_info "Operation cancelled. No files were deleted."
fi
