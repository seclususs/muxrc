#!/data/data/com.termux/files/usr/bin/bash

########################
# Duplicate File Cleaner
########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd find stat sha256sum awk sort xargs
}

validate_target_dir() {
  local target_dir="${1:-}"

  if [[ -z "${target_dir}" ]]; then
    log_error "usage: $(basename "$0") <directory>"
    return 1
  fi

  validate_dir_readable "${target_dir}"
}

scan_file_sizes() {
  local target_dir="${1:-}"
  local tmp_dir="${2:-}"

  if [[ -z "${target_dir}" || -z "${tmp_dir}" ]]; then
    return 1
  fi

  start_spinner "scanning '${target_dir}'"
  find "${target_dir}" -type f -size +0c -print0 | xargs -r0 stat -c '%s %n' > "${tmp_dir}/all_files.txt"
  stop_spinner "success" "scanning complete."

  awk '{size=$1; count[size]++} END {for(s in count) if(count[s]>1) print s}' "${tmp_dir}/all_files.txt" > "${tmp_dir}/dup_sizes.txt"
}

hash_potential_duplicates() {
  local tmp_dir="${1:-}"

  if [[ -z "${tmp_dir}" ]]; then
    return 1
  fi

  local -a candidates=()
  mapfile -t candidates < <(awk 'NR==FNR {dup[$1]; next} $1 in dup { print substr($0, length($1)+2) }' "${tmp_dir}/dup_sizes.txt" "${tmp_dir}/all_files.txt")

  local total=${#candidates[@]}
  local idx=0
  local file

  : > "${tmp_dir}/hashed.txt"

  for file in "${candidates[@]}"; do
    ((idx++))
    log_progress "${idx}" "${total}" "hashing duplicates"
    sha256sum "${file}" >> "${tmp_dir}/hashed.txt"
  done

  clear_progress
  log_success "hashing complete."

  awk '{hash=$1; count[hash]++} END {for(h in count) if(count[h]>1) print h}' "${tmp_dir}/hashed.txt" > "${tmp_dir}/dup_hashes.txt"
}

display_duplicates_and_collect_deletions() {
  local tmp_dir="${1:-}"

  if [[ -z "${tmp_dir}" ]]; then
    return 1
  fi

  local total_dupe_sets=0
  local current_hash=""
  local hash
  local file
  local line

  : > "${tmp_dir}/to_delete.txt"
  log_warn "duplicates:"

  awk 'NR==FNR { dup[$1]; next } $1 in dup { print }' "${tmp_dir}/dup_hashes.txt" "${tmp_dir}/hashed.txt" \
    | sort -k1,1 > "${tmp_dir}/dup_files.txt"

  while IFS= read -r line; do
    hash="${line:0:64}"
    file="${line:66}"

    if [[ "${hash}" != "${current_hash}" ]]; then
      current_hash="${hash}"
      total_dupe_sets=$((total_dupe_sets + 1))
      log_info "[group ${total_dupe_sets}] hash: ${hash:0:8}..."
      log_success "keep: ${file}"
    else
      log_warn "del : ${file}"
      echo "${file}" >> "${tmp_dir}/to_delete.txt"
    fi
  done < "${tmp_dir}/dup_files.txt"
}

confirm_and_delete() {
  local delete_list="${1:-}"

  if [[ -z "${delete_list}" || ! -f "${delete_list}" ]]; then
    return 0
  fi

  local total_to_delete
  local confirm=""

  total_to_delete=$(wc -l < "${delete_list}")
  if [[ "${total_to_delete}" -eq 0 ]]; then
    return 0
  fi

  log_prompt "delete ${total_to_delete} files? [y/n]: "
  read -r confirm

  if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    log_info "cleaning..."
    xargs -r -d '\n' rm -f < "${delete_list}"
    log_success "deleted ${total_to_delete} files."
  else
    log_warn "aborted."
  fi
}

main() {
  local target_dir="${1:-}"
  local tmp_dir

  validate_target_dir "${target_dir}" || exit 1
  check_dependencies || exit 1

  tmp_dir=$(mktemp -d)
  trap 'rm -rf "${tmp_dir}"; cleanup_spinner' EXIT

  scan_file_sizes "${target_dir}" "${tmp_dir}"
  if [[ ! -s "${tmp_dir}/dup_sizes.txt" ]]; then
    log_success "no duplicates found."
    exit 0
  fi

  hash_potential_duplicates "${tmp_dir}"
  if [[ ! -s "${tmp_dir}/dup_hashes.txt" ]]; then
    log_success "no exact duplicates found."
    exit 0
  fi

  display_duplicates_and_collect_deletions "${tmp_dir}"
  confirm_and_delete "${tmp_dir}/to_delete.txt"
}

main "$@"
