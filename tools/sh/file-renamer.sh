#!/data/data/com.termux/files/usr/bin/bash

##############
# File Renamer
##############
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd exiftool stat date find mv
}

validate_inputs() {
  local target_dir="${1:-}"
  local prefix="${2:-}"

  if [[ -z "${target_dir}" || -z "${prefix}" ]]; then
    log_error "usage: $(basename "$0") <directory> <prefix>"
    return 1
  fi

  validate_dir_readable "${target_dir}"
}

extract_timestamp() {
  local file="${1}"
  local date_str=""
  local birth_epoch="0"

  date_str=$(exiftool -s3 -d "%Y%m%d_%H%M%S" -DateTimeOriginal -CreateDate "${file}" 2> /dev/null | head -n 1 || true)

  if [[ -z "${date_str}" ]]; then
    birth_epoch=$(stat -c %W "${file}" 2> /dev/null || echo 0)
    if [[ "${birth_epoch}" == "0" || "${birth_epoch}" == "?" ]]; then
      birth_epoch=$(stat -c %Y "${file}" 2> /dev/null || echo 0)
    fi

    if [[ "${birth_epoch}" != "0" ]]; then
      date_str=$(date -d "@${birth_epoch}" "+%Y%m%d_%H%M%S" 2> /dev/null || echo "UNKNOWN")
    else
      date_str="UNKNOWN"
    fi
  fi

  echo "${date_str}"
}

build_unique_target_path() {
  local file="${1}"
  local prefix="${2}"
  local date_str="${3}"
  local -n _out_ref="${4}"
  local -n _seen_ref="${5}"
  local ext=""
  local base_dir
  local new_name
  local new_path
  local counter=1

  base_dir=$(dirname "${file}")

  if [[ "${file}" == *.* ]]; then
    ext="${file##*.}"
    new_name="${prefix}_${date_str}.${ext}"
  else
    new_name="${prefix}_${date_str}"
  fi

  new_path="${base_dir}/${new_name}"

  while [[ -e "${new_path}" || -n "${_seen_ref[${new_path}]:-}" ]]; do
    if [[ -n "${ext}" ]]; then
      new_name="${prefix}_${date_str}_${counter}.${ext}"
    else
      new_name="${prefix}_${date_str}_${counter}"
    fi
    new_path="${base_dir}/${new_name}"
    ((counter++))
  done

  _seen_ref["${new_path}"]=1
  _out_ref="${new_path}"
}

display_proposed_changes() {
  local -n _old_ref="$1"
  local -n _new_ref="$2"
  local i
  local old_base
  local new_base

  log_info "proposed changes:"
  for i in "${!_old_ref[@]}"; do
    old_base=$(basename "${_old_ref[${i}]}")
    new_base=$(basename "${_new_ref[${i}]}")
    printf "%-30s -> %s\n" "${old_base:0:30}" "${new_base}" >&2
  done
}

apply_renames() {
  local -n _old_targets="$1"
  local -n _new_targets="$2"
  local conf=""
  local i

  log_prompt "confirm rename? [y/n]: "
  read -r conf

  if [[ "${conf}" =~ ^[Yy]$ ]]; then
    log_info "executing rename..."
    for i in "${!_old_targets[@]}"; do
      mv -n "${_old_targets[${i}]}" "${_new_targets[${i}]}"
    done
    log_success "done."
  else
    log_warn "aborted."
  fi
}

main() {
  local dir="${1:-}"
  local prefix="${2:-}"
  local file
  local date_str
  local new_path=""
  local -a file_list=()
  local -a old_names=()
  local -a new_names=()
  local -A seen_targets=()
  local idx=0
  local total=0

  validate_inputs "${dir}" "${prefix}" || exit 1
  check_dependencies || exit 1

  mapfile -d '' file_list < <(find "${dir}" -maxdepth 1 -type f -print0)
  total=${#file_list[@]}

  if [[ "${total}" -eq 0 ]]; then
    log_info "no files to rename."
    exit 0
  fi

  for file in "${file_list[@]}"; do
    idx=$((idx + 1))
    log_progress "${idx}" "${total}" "parsing dates"

    date_str=$(extract_timestamp "${file}")
    if [[ "${date_str}" == "UNKNOWN" || -z "${date_str}" ]]; then
      continue
    fi

    build_unique_target_path "${file}" "${prefix}" "${date_str}" new_path seen_targets

    if [[ "${file}" != "${new_path}" ]]; then
      old_names+=("${file}")
      new_names+=("${new_path}")
    fi
  done

  clear_progress
  log_success "parsing complete."

  if [[ ${#old_names[@]} -eq 0 ]]; then
    log_info "no files to rename."
    exit 0
  fi

  display_proposed_changes old_names new_names
  apply_renames old_names new_names
}

main "$@"
