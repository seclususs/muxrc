#!/data/data/com.termux/files/usr/bin/bash

#####################
# Steganography Vault
#####################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd steghide shred
}

prompt_passphrase_confirmed() {
  local pass=""
  local pass_conf=""

  log_prompt "passphrase: "
  read -r -s pass
  echo >&2
  if [[ -z "${pass}" ]]; then
    log_error "passphrase cannot be empty."
    return 1
  fi

  log_prompt "confirm passphrase: "
  read -r -s pass_conf
  echo >&2
  if [[ "${pass}" != "${pass_conf}" ]]; then
    log_error "passphrases do not match."
    return 1
  fi

  echo "${pass}"
  return 0
}

embed_data() {
  local opsec_dir="${1:-}"

  if [[ -z "${opsec_dir}" ]]; then
    log_error "missing opsec directory parameter."
    return 1
  fi

  local cover=""
  local embed_opt=""
  local embed_file=""
  local secret_text=""
  local pass=""

  log_prompt "path to cover image: "
  read -r cover
  if [[ ! -f "${cover}" ]]; then
    log_error "cover image not found."
    return 1
  fi

  log_info "what to embed?"
  log_info "1) text string"
  log_info "2) file"
  log_prompt "select [1/2]: "
  read -r embed_opt

  if [[ "${embed_opt}" == "1" ]]; then
    embed_file="${opsec_dir}/secret-payload.txt"
    trap 'shred -u "${embed_file}" 2>/dev/null || true; cleanup_spinner' EXIT INT TERM
    log_prompt "text to hide: "
    read -r secret_text
    touch "${embed_file}"
    chmod 600 "${embed_file}"
    echo "${secret_text}" > "${embed_file}"
  elif [[ "${embed_opt}" == "2" ]]; then
    log_prompt "path to file to hide: "
    read -r embed_file
    if [[ ! -f "${embed_file}" ]]; then
      log_error "file to embed not found."
      return 1
    fi
  else
    log_error "invalid option."
    return 1
  fi

  if ! pass=$(prompt_passphrase_confirmed); then
    if [[ "${embed_opt}" == "1" && -f "${embed_file}" ]]; then
      shred -u "${embed_file}" 2> /dev/null || true
      trap - EXIT INT TERM
    fi
    return 1
  fi

  trap '[[ "${embed_opt}" == "1" && -f "${embed_file}" ]] && shred -u "${embed_file}" 2>/dev/null || true; cleanup_spinner' EXIT
  start_spinner "embedding data"
  local embed_success=0
  if steghide embed -ef "${embed_file}" -cf "${cover}" -p "${pass}"; then
    stop_spinner "success" "embedded into ${cover}"
    embed_success=1
  else
    stop_spinner "error" "steghide failed."
  fi
  trap - EXIT

  if [[ "${embed_opt}" == "1" && -f "${embed_file}" ]]; then
    shred -u "${embed_file}"
    trap - INT TERM
  fi

  [[ ${embed_success} -eq 1 ]] || return 1
}

extract_data() {
  local extract_dir="${1:-}"

  if [[ -z "${extract_dir}" ]]; then
    log_error "missing extraction directory parameter."
    return 1
  fi

  local stego_img=""
  local stego_img_abs=""
  local pass=""

  log_prompt "path to stego-image: "
  read -r stego_img
  if [[ ! -f "${stego_img}" ]]; then
    log_error "stego-image not found."
    return 1
  fi

  stego_img_abs=$(realpath "${stego_img}")

  log_prompt "decryption passphrase: "
  read -r -s pass
  echo >&2
  if [[ -z "${pass}" ]]; then
    log_error "passphrase cannot be empty."
    return 1
  fi

  trap 'cleanup_spinner' EXIT
  start_spinner "extracting data"
  local extract_success=0
  pushd "${extract_dir}" > /dev/null
  if steghide extract -sf "${stego_img_abs}" -f -p "${pass}"; then
    stop_spinner "success" "extracted to ${extract_dir}"
    extract_success=1
  else
    stop_spinner "error" "extraction failed."
  fi
  popd > /dev/null
  trap - EXIT

  [[ ${extract_success} -eq 1 ]] || return 1
}

main() {
  local cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/muxrc"
  local opsec_dir="${cache_dir}/run"
  local extract_dir="${HOME}/muxrc-out/extracted"
  local opt=""

  check_dependencies || exit 1

  mkdir -p "${opsec_dir}"
  mkdir -p "${extract_dir}"

  log_info "steganography vault"
  log_info "1) embed data"
  log_info "2) extract data"
  log_info "0) exit"
  log_prompt "select [1/2/0]: "
  read -r opt

  if [[ "${opt}" == "1" ]]; then
    embed_data "${opsec_dir}"
  elif [[ "${opt}" == "2" ]]; then
    extract_data "${extract_dir}"
  elif [[ "${opt}" == "0" ]]; then
    log_warn "exiting..."
    exit 0
  else
    log_error "invalid option."
    exit 1
  fi
}

main "$@"
