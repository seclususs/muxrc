#!/data/data/com.termux/files/usr/bin/bash

########################
# Binary Media Encrypter
########################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd openssl
}

validate_target_file() {
  local target_file="${1:-}"

  if [[ -z "${target_file}" ]]; then
    log_error "usage: $(basename "$0") <target_file>"
    return 1
  fi

  validate_file_readable "${target_file}"
}

validate_password() {
  if [[ -z "${MUXRC_CRYPT_PASS:-}" ]]; then
    log_error "password not provided in MUXRC_CRYPT_PASS."
    return 1
  fi
  return 0
}

ensure_vault_dir() {
  local vault_dir="${1:-}"

  if [[ -z "${vault_dir}" ]]; then
    log_error "vault directory not specified."
    return 1
  fi

  if [[ ! -d "${vault_dir}" ]]; then
    mkdir -p "${vault_dir}"
  fi

  if [[ ! -f "${vault_dir}/.nomedia" ]]; then
    touch "${vault_dir}/.nomedia"
  fi
}

encrypt_target_file() {
  local target_file="${1:-}"
  local vault_dir="${2:-}"

  if [[ -z "${target_file}" || -z "${vault_dir}" ]]; then
    log_error "missing encryption parameters."
    return 1
  fi

  local base_name
  local out_file

  base_name=$(basename "${target_file}")
  out_file="${vault_dir}/.${base_name}.enc"

  trap 'cleanup_spinner' EXIT
  start_spinner "encrypting ${base_name}"

  if openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -in "${target_file}" -out "${out_file}" -pass env:MUXRC_CRYPT_PASS; then
    stop_spinner "success" "encrypted: ${out_file}"
    trap - EXIT
    return 0
  else
    stop_spinner "error" "encryption failed."
    trap - EXIT
    return 1
  fi
}

main() {
  local target_file="${1:-}"
  local vault_dir="${HOME}/.vault"

  validate_target_file "${target_file}" || exit 1
  validate_password || exit 1
  check_dependencies || exit 1

  ensure_vault_dir "${vault_dir}"
  encrypt_target_file "${target_file}" "${vault_dir}" || exit 1
}

main "$@"
