#!/data/data/com.termux/files/usr/bin/bash

########################
# Duplicate File Cleaner
########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

target_dir="${1:-}"
if [[ -z "$target_dir" ]]; then
    log_error "usage: $(basename "$0") <directory>"
    exit 1
fi

if [[ ! -d "$target_dir" ]]; then
    log_error "directory '$target_dir' not found."
    exit 1
fi

log_info "scanning '$target_dir'..."

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

find "$target_dir" -type f -print0 | xargs -0 stat -c '%s %n' > "$tmp_dir/all_files.txt"

awk '{size=$1; count[size]++} END {for(s in count) if(count[s]>1) print s}' "$tmp_dir/all_files.txt" > "$tmp_dir/dup_sizes.txt"

if [[ ! -s "$tmp_dir/dup_sizes.txt" ]]; then
    log_success "no duplicates found."
    exit 0
fi

log_info "hashing..."

awk 'NR==FNR {dup[$1]; next} $1 in dup { print substr($0, length($1)+2) }' "$tmp_dir/dup_sizes.txt" "$tmp_dir/all_files.txt" | \
tr '\n' '\0' | xargs -0 sha256sum > "$tmp_dir/hashed.txt"

awk '{hash=$1; count[hash]++} END {for(h in count) if(count[h]>1) print h}' "$tmp_dir/hashed.txt" > "$tmp_dir/dup_hashes.txt"

if [[ ! -s "$tmp_dir/dup_hashes.txt" ]]; then
    log_success "no exact duplicates found."
    exit 0
fi

log_warn "duplicates:"

> "$tmp_dir/to_delete.txt"
total_dupe_sets=0

while read -r hash; do
    total_dupe_sets=$((total_dupe_sets + 1))
    echo "[group $total_dupe_sets] Hash: ${hash:0:8}..."
    
    awk -v h="$hash" '$1==h { print substr($0, length($1)+3) }' "$tmp_dir/hashed.txt" > "$tmp_dir/current_set.txt"
    
    mapfile -t files < "$tmp_dir/current_set.txt"
    
    log_success "keep: ${files[0]}"
    
    for i in "${!files[@]}"; do
        if [[ $i -ne 0 ]]; then
            log_warn "del : ${files[$i]}"
            echo "${files[$i]}" >> "$tmp_dir/to_delete.txt"
        fi
    done
    echo ""
done < "$tmp_dir/dup_hashes.txt"

total_to_delete=$(wc -l < "$tmp_dir/to_delete.txt")

read -r -p "delete $total_to_delete files? [y/N]: " confirm

if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    log_info "cleaning..."
    while IFS= read -r file; do
        rm -f "$file"
    done < "$tmp_dir/to_delete.txt"
    log_success "deleted $total_to_delete files."
else
    log_info "aborted."
fi

exit 0
