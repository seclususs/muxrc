#!/data/data/com.termux/files/usr/bin/bash

########################
# Duplicate File Cleaner
########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd find stat sha256sum awk
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
  find "${target_dir}" -type f -print0 | xargs -0 stat -c '%s %n' > "${tmp_dir}/all_files.txt"
  stop_spinner "success" "scanning complete."

  awk '{size=$1; count[size]++} END {for(s in count) if(count[s]>1) print s}' "${tmp_dir}/all_files.txt" > "${tmp_dir}/dup_sizes.txt"
}

hash_potential_duplicates() {
  local tmp_dir="${1:-}"

  if [[ -z "${tmp_dir}" ]]; then
    return 1
  fi

  start_spinner "hashing duplicates"
  awk 'NR==FNR {dup[$1]; next} $1 in dup { print substr($0, length($1)+2) }' "${tmp_dir}/dup_sizes.txt" "${tmp_dir}/all_files.txt" \
    | tr '\n' '\0' | xargs -0 sha256sum > "${tmp_dir}/hashed.txt"
  stop_spinner "success" "hashing complete."

  awk '{hash=$1; count[hash]++} END {for(h in count) if(count[h]>1) print h}' "${tmp_dir}/hashed.txt" > "${tmp_dir}/dup_hashes.txt"
}

display_duplicates_and_collect_deletions() {
  local tmp_dir="${1:-}"

  if [[ -z "${tmp_dir}" ]]; then
    return 1
  fi

  local total_dupe_sets=0
  local hash
  local -a files=()
  local i

  : > "${tmp_dir}/to_delete.txt"
  log_warn "duplicates:"

  while read -r hash; do
    total_dupe_sets=$((total_dupe_sets + 1))
    log_info "[group ${total_dupe_sets}] hash: ${hash:0:8}..."

    awk -v h="${hash}" '$1==h { print substr($0, length($1)+3) }' "${tmp_dir}/hashed.txt" > "${tmp_dir}/current_set.txt"
    mapfile -t files < "${tmp_dir}/current_set.txt"

    log_success "keep: ${files[0]}"

    for i in "${!files[@]}"; do
      if [[ ${i} -ne 0 ]]; then
        log_warn "del : ${files[${i}]}"
        echo "${files[${i}]}" >> "${tmp_dir}/to_delete.txt"
      fi
    done
  done < "${tmp_dir}/dup_hashes.txt"
}

confirm_and_delete() {
  local delete_list="${1:-}"

  if [[ -z "${delete_list}" || ! -f "${delete_list}" ]]; then
    return 0
  fi

  local total_to_delete
  local confirm=""
  local file

  total_to_delete=$(wc -l < "${delete_list}")
  if [[ "${total_to_delete}" -eq 0 ]]; then
    return 0
  fi

  log_prompt "delete ${total_to_delete} files? [y/n]: "
  read -r confirm

  if [[ "${confirm:-}" =~ ^[Yy]$ ]]; then
    log_info "cleaning..."
    while IFS= read -r file; do
      rm -f "${file}"
    done < "${delete_list}"
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
