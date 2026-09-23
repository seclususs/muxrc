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

if [[ ! -d "$target_dir" ]]; then
    echo "Error: Directory '$target_dir' not found."
    exit 1
fi

echo "[*] Scanning for files in '$target_dir'..."

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

find "$target_dir" -type f -print0 | xargs -0 stat -c '%s %n' > "$tmp_dir/all_files.txt"

awk '{size=$1; count[size]++} END {for(s in count) if(count[s]>1) print s}' "$tmp_dir/all_files.txt" > "$tmp_dir/dup_sizes.txt"

if [[ ! -s "$tmp_dir/dup_sizes.txt" ]]; then
    echo "    [+] No duplicate file sizes found. Directory is clean."
    exit 0
fi

echo "[*] Hashing files with identical sizes..."

awk 'NR==FNR {dup[$1]; next} $1 in dup { print substr($0, length($1)+2) }' "$tmp_dir/dup_sizes.txt" "$tmp_dir/all_files.txt" | \
tr '\n' '\0' | xargs -0 sha256sum > "$tmp_dir/hashed.txt"

awk '{hash=$1; count[hash]++} END {for(h in count) if(count[h]>1) print h}' "$tmp_dir/hashed.txt" > "$tmp_dir/dup_hashes.txt"

if [[ ! -s "$tmp_dir/dup_hashes.txt" ]]; then
    echo "    [+] No identical files found after hash verification."
    exit 0
fi

echo ""
echo "[!] Duplicate files found:"

> "$tmp_dir/to_delete.txt"
total_dupe_sets=0

while read -r hash; do
    ((total_dupe_sets++))
    echo "[Group $total_dupe_sets] Hash: ${hash:0:8}..."
    
    awk -v h="$hash" '$1==h { print substr($0, length($1)+3) }' "$tmp_dir/hashed.txt" > "$tmp_dir/current_set.txt"
    
    mapfile -t files < "$tmp_dir/current_set.txt"
    
    echo "    [+] KEEP: ${files[0]}"
    
    for i in "${!files[@]}"; do
        if [[ $i -ne 0 ]]; then
            echo "    [-] DEL : ${files[$i]}"
            echo "${files[$i]}" >> "$tmp_dir/to_delete.txt"
        fi
    done
    echo ""
done < "$tmp_dir/dup_hashes.txt"

total_to_delete=$(wc -l < "$tmp_dir/to_delete.txt")

read -r -p "    [?] Do you want to clean these $total_to_delete duplicate files? [y/N]: " confirm

if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    echo "[*] Cleaning up duplicates..."
    while IFS= read -r file; do
        rm -f "$file"
    done < "$tmp_dir/to_delete.txt"
    echo "    [+] Successfully deleted $total_to_delete duplicate files."
else
    echo "    [*] Operation cancelled. No files were deleted."
fi
