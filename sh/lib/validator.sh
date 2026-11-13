#!/data/data/com.termux/files/usr/bin/sh

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

  if [ -z "${dir_path}" ]; then
    log_error "empty directory path"
    return 1
  fi

  if [ ! -d "${dir_path}" ]; then
    log_error "directory not found: ${dir_path}"
    return 1
  fi

  if [ ! -r "${dir_path}" ]; then
    log_error "directory not readable: ${dir_path}"
    return 1
  fi

  return 0
}

########################################
# Verifies that a file is valid/readable
########################################
validate_file_readable() {
  local file_path="${1:-}"

  if [ -z "${file_path}" ]; then
    log_error "empty file path"
    return 1
  fi

  if [ ! -f "${file_path}" ]; then
    log_error "file not found: ${file_path}"
    return 1
  fi

  if [ ! -r "${file_path}" ]; then
    log_error "file not readable: ${file_path}"
    return 1
  fi

  return 0
}

########################################
# Verifies that a file is valid/writable
########################################
validate_file_writable() {
  local file_path="${1:-}"

  if [ -z "${file_path}" ]; then
    log_error "empty file path"
    return 1
  fi

  if [ ! -f "${file_path}" ]; then
    log_error "file not found: ${file_path}"
    return 1
  fi

  if [ ! -w "${file_path}" ]; then
    log_error "file not writable: ${file_path}"
    return 1
  fi

  return 0
}

################################################
# Verifies that a target file or dir is readable
################################################
validate_target_readable() {
  local target="${1:-}"

  if [ -z "${target}" ]; then
    log_error "empty target path"
    return 1
  fi

  if [ ! -e "${target}" ]; then
    log_error "target not found: ${target}"
    return 1
  fi

  if [ ! -r "${target}" ]; then
    log_error "target not readable: ${target}"
    return 1
  fi

  return 0
}

################################
# Verifies root or EUID 0 access
################################
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    log_error "root required"
    return 1
  fi
  return 0
}

#######################
# ssh session guardrail
#######################
is_ssh_session() {
  if [ -n "${SSH_CLIENT:-}" ] || [ -n "${SSH_TTY:-}" ] || [ -n "${SSH_CONNECTION:-}" ]; then
    return 0
  fi

  local pid="${PPID:-}"
  local depth=0
  while [ -n "${pid}" ] && [ "${depth}" -lt 4 ]; do
    case "${pid}" in
      '' | *[!0-9]*) break ;;
      *)
        if [ "${pid}" -le 1 ]; then
          break
        fi
        ;;
    esac
    if [ -r "/proc/${pid}/environ" ]; then
      if tr '\0' '\n' < "/proc/${pid}/environ" 2> /dev/null | grep -qE '^SSH_(CLIENT|TTY|CONNECTION)='; then
        return 0
      fi
    fi
    if [ -r "/proc/${pid}/status" ]; then
      pid=$(awk '/^PPid:[[:space:]]*/ {print $2; exit}' "/proc/${pid}/status" 2> /dev/null || true)
    else
      break
    fi
    depth=$((depth + 1))
  done

  return 1
}
