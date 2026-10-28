#!/data/data/com.termux/files/usr/bin/bash

##########################
# Permanent Media Shredder
##########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd shred
}

validate_target_file() {
  local target_file="${1:-}"

  if [[ -z "${target_file}" ]]; then
    log_error "usage: $(basename "$0") <target_file>"
    return 1
  fi

  validate_file_writable "${target_file}"
}

confirm_destruction() {
  local target_file="${1:-}"

  if [[ -z "${target_file}" ]]; then
    return 1
  fi

  local confirm=""

  log_warn "permanently destroying:"
  log_warn "${target_file}"
  log_prompt "type 'shred' to confirm (or anything else to exit): "
  read -r confirm

  if [[ "${confirm}" == "shred" || "${confirm}" == "SHRED" ]]; then
    return 0
  fi
  return 1
}

execute_shred() {
  local target_file="${1:-}"

  if [[ -z "${target_file}" ]]; then
    return 1
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "shredding file"
  shred -u -z -n 3 -- "${target_file}"
  stop_spinner "success" "file destroyed."
  trap - EXIT
}

main() {
  local target_file="${1:-}"

  validate_target_file "${target_file}" || exit 1
  check_dependencies || exit 1

  if confirm_destruction "${target_file}"; then
    execute_shred "${target_file}"
  else
    log_warn "aborted."
    exit 1
  fi
}

main "$@"
