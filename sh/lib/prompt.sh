#!/data/data/com.termux/files/usr/bin/sh

#####################################
# Interactive Prompt & Secret Helpers
#####################################

prompt_confirm() {
  local prompt_msg="${1:-are you sure?}"
  local default_ans="${2:-N}"
  local hint="[y/N]"
  case "${default_ans}" in
    [Yy]*) hint="[Y/n]" ;;
  esac

  log_prompt "${prompt_msg} ${hint}: "
  local answer=""
  read -r answer || true

  case "${answer}" in
    [Yy]*) return 0 ;;
    [Nn]*) return 1 ;;
    "")
      case "${default_ans}" in
        [Yy]*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

read_secret() {
  local prompt_text="${1:-}"
  local target_var="${2:-}"
  if [ -z "${target_var}" ]; then
    return 1
  fi

  local orig_tty=""
  orig_tty=$(stty -g 2> /dev/null || true)

  trap '
    if [ -n "${orig_tty}" ]; then
      stty "${orig_tty}" 2>/dev/null || stty sane 2>/dev/null
    fi
    exit 130
  ' INT TERM

  if [ -n "${prompt_text}" ]; then
    printf '%s' "${prompt_text}" >&2
  fi

  stty -echo 2> /dev/null || true
  local secret_val=""
  read -r secret_val || true
  local read_rc=$?

  if [ -n "${orig_tty}" ]; then
    stty "${orig_tty}" 2> /dev/null || stty sane 2> /dev/null
  else
    stty sane 2> /dev/null || true
  fi
  trap - INT TERM
  printf '\n' >&2

  eval "${target_var}=\${secret_val}"
  return "${read_rc}"
}

prompt_secret_confirmed() {
  local prompt_label="${1:-password}"
  local out_var="${2:-}"
  if [ -z "${out_var}" ]; then
    return 1
  fi

  local secret1="" secret2=""
  read_secret "enter ${prompt_label}: " secret1 || return 1
  if [ -z "${secret1}" ]; then
    log_error "${prompt_label} cannot be empty"
    return 1
  fi

  read_secret "confirm ${prompt_label}: " secret2 || return 1
  if [ "${secret1}" != "${secret2}" ]; then
    log_error "${prompt_label}s do not match"
    return 1
  fi

  eval "${out_var}=\${secret1}"
  return 0
}

prompt_ssh_hazard() {
  local warning="${1:-this will drop your ssh connection}"
  if ! is_ssh_session; then
    return 0
  fi

  log_warn "${warning}"
  prompt_confirm "continue?" "N"
}

confirm_ssh_hazard() {
  prompt_ssh_hazard "$@"
}
