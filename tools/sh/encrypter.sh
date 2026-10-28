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
    log_error "usage: $(basename "$0") [--encrypt|--decrypt] <target_file> [output_file]"
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

  if [[ -e "${out_file}" ]]; then
    local overwrite=""
    log_prompt "vault file '${out_file}' already exists. overwrite? [y/N]: "
    read -r overwrite
    if [[ ! "${overwrite:-}" =~ ^[Yy]$ ]]; then
      log_warn "aborted."
      return 1
    fi
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "encrypting ${base_name}"

  if openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -in "${target_file}" -out "${out_file}" -pass env:MUXRC_CRYPT_PASS; then
    chmod 600 "${out_file}"
    stop_spinner "success" "encrypted: ${out_file}"
    trap - EXIT
    return 0
  else
    stop_spinner "error" "encryption failed."
    trap - EXIT
    rm -f "${out_file}" 2> /dev/null || true
    return 1
  fi
}

decrypt_target_file() {
  local target_file="${1:-}"
  local out_file="${2:-}"

  if [[ -z "${target_file}" ]]; then
    log_error "missing target file for decryption."
    return 1
  fi

  if [[ -z "${out_file}" ]]; then
    local base_name
    base_name=$(basename "${target_file}")
    base_name="${base_name#.}"
    base_name="${base_name%.enc}"
    out_file="./${base_name}"
  fi

  if [[ -e "${out_file}" ]]; then
    local overwrite=""
    log_prompt "output '${out_file}' already exists. overwrite? [y/N]: "
    read -r overwrite
    if [[ ! "${overwrite:-}" =~ ^[Yy]$ ]]; then
      log_warn "aborted."
      return 1
    fi
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "decrypting $(basename "${target_file}")"

  if openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in "${target_file}" -out "${out_file}" -pass env:MUXRC_CRYPT_PASS; then
    stop_spinner "success" "decrypted: ${out_file}"
    trap - EXIT
    return 0
  else
    stop_spinner "error" "decryption failed. invalid password or corrupt file."
    trap - EXIT
    rm -f "${out_file}" 2> /dev/null || true
    return 1
  fi
}

main() {
  local mode="--encrypt"
  local target_file=""
  local output_file=""
  local data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/muxrc"
  local vault_dir="${data_dir}/vault"
  if [[ ! -d "${vault_dir}" && -d "${HOME}/.vault" ]]; then
    vault_dir="${HOME}/.vault"
  fi

  if [[ "${1:-}" == "--decrypt" || "${1:-}" == "-d" ]]; then
    mode="--decrypt"
    shift
  elif [[ "${1:-}" == "--encrypt" || "${1:-}" == "-e" ]]; then
    mode="--encrypt"
    shift
  fi

  target_file="${1:-}"
  output_file="${2:-}"

  validate_target_file "${target_file}" || exit 1
  validate_password || exit 1
  check_dependencies || exit 1

  if [[ "${mode}" == "--encrypt" ]]; then
    ensure_vault_dir "${vault_dir}"
    encrypt_target_file "${target_file}" "${vault_dir}" || exit 1
  else
    decrypt_target_file "${target_file}" "${output_file}" || exit 1
  fi

  unset MUXRC_CRYPT_PASS || true
}

main "$@"
