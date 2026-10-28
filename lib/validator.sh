#!/data/data/com.termux/files/usr/bin/bash

###########
# Validator
###########

#######################################
# Verifies that required commands exist
#######################################
require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" > /dev/null 2>&1; then
      log_error "missing required command: ${cmd}"
      return 1
    fi
  done
  return 0
}

#############################################
# Verifies that a directory is valid/readable
#############################################
validate_dir_readable() {
  local dir_path="${1:-}"

  if [[ -z "${dir_path}" ]]; then
    log_error "directory path cannot be empty."
    return 1
  fi

  if [[ ! -d "${dir_path}" ]]; then
    log_error "directory '${dir_path}' not found."
    return 1
  fi

  if [[ ! -r "${dir_path}" ]]; then
    log_error "directory '${dir_path}' is not readable."
    return 1
  fi

  return 0
}

########################################
# Verifies that a file is valid/readable
########################################
validate_file_readable() {
  local file_path="${1:-}"

  if [[ -z "${file_path}" ]]; then
    log_error "file path cannot be empty."
    return 1
  fi

  if [[ ! -f "${file_path}" ]]; then
    log_error "file '${file_path}' not found."
    return 1
  fi

  if [[ ! -r "${file_path}" ]]; then
    log_error "file '${file_path}' is not readable."
    return 1
  fi

  return 0
}

########################################
# Verifies that a file is valid/writable
########################################
validate_file_writable() {
  local file_path="${1:-}"

  if [[ -z "${file_path}" ]]; then
    log_error "file path cannot be empty."
    return 1
  fi

  if [[ ! -f "${file_path}" ]]; then
    log_error "file '${file_path}' not found."
    return 1
  fi

  if [[ ! -w "${file_path}" ]]; then
    log_error "file '${file_path}' is not writable."
    return 1
  fi

  return 0
}

################################
# Verifies root or EUID 0 access
################################
require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "root access required (run via sudo)"
    return 1
  fi
  return 0
}
