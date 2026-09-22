#!/data/data/com.termux/files/usr/bin/bash

##############
# File Renamer
##############
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: file-renamer.sh <directory> <prefix>"
    exit 1
fi

dir="$1"
prefix="$2"

if [[ ! -d "$dir" ]]; then
    echo "Error: Directory '$dir' not found."
    exit 1
fi

declare -a old_names=()
declare -a new_names=()

echo "[*] Parsing dates..."

while IFS= read -r -d '' file; do
    date_str=$(exiftool -s -s -s -d "%Y%m%d_%H%M%S" -DateTimeOriginal "$file" 2>/dev/null || true)
    
    # Check EXIF CreateDate if null
    if [[ -z "$date_str" ]]; then
        date_str=$(exiftool -s -s -s -d "%Y%m%d_%H%M%S" -CreateDate "$file" 2>/dev/null || true)
    fi
    
    # Fallback to stat -c %W (birth) or %Y (mtime)
    if [[ -z "$date_str" ]]; then
        birth_epoch=$(stat -c %W "$file" 2>/dev/null || echo 0)
        if [[ "$birth_epoch" == "0" || "$birth_epoch" == "?" ]]; then
            birth_epoch=$(stat -c %Y "$file" 2>/dev/null || echo 0)
        fi
        
        if [[ "$birth_epoch" != "0" ]]; then
            date_str=$(date -d "@$birth_epoch" "+%Y%m%d_%H%M%S" 2>/dev/null || echo "UNKNOWN")
        else
            date_str="UNKNOWN"
        fi
    fi
    
    if [[ "$date_str" == "UNKNOWN" || -z "$date_str" ]]; then
        continue
    fi
    
    ext="${file##*.}"
    base_dir=$(dirname "$file")
    
    if [[ "$file" == *.* ]]; then
        new_name="${prefix}_${date_str}.${ext}"
    else
        new_name="${prefix}_${date_str}"
    fi
    
    new_path="$base_dir/$new_name"
    
    # Handle collisions in the proposed batch
    counter=1
    while [[ -e "$new_path" || " ${new_names[*]:-} " == *" $new_path "* ]]; do
        if [[ "$file" == *.* ]]; then
            new_name="${prefix}_${date_str}_${counter}.${ext}"
        else
            new_name="${prefix}_${date_str}_${counter}"
        fi
        new_path="$base_dir/$new_name"
        ((counter++))
    done
    
    if [[ "$file" != "$new_path" ]]; then
        old_names+=("$file")
        new_names+=("$new_path")
    fi
done < <(find "$dir" -maxdepth 1 -type f -print0)

if [[ ${#old_names[@]} -eq 0 ]]; then
    echo "No files require renaming."
    exit 0
fi

echo "=========================================="
echo "        Proposed File Name Changes        "
echo "=========================================="
for i in "${!old_names[@]}"; do
    old_base=$(basename "${old_names[$i]}")
    new_base=$(basename "${new_names[$i]}")
    printf "%-30s -> %s\n" "${old_base:0:30}" "$new_base"
done
echo "=========================================="

read -r -p "Confirm renaming? [y/N]: " conf
if [[ "$conf" =~ ^[Yy]$ ]]; then
    echo "[*] Executing rename..."
    for i in "${!old_names[@]}"; do
        mv -n "${old_names[$i]}" "${new_names[$i]}"
    done
    echo "[+] Done."
else
    echo "[-] Aborted by user."
fi
