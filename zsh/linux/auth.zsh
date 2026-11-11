###############################
# Shadow authentication helpers
###############################

_auth_get_shadow_file() {
  print -r -- "${PREFIX:-/data/data/com.termux/files/usr}/etc/shadow"
}

_auth_get_hash() {
  local shadow_file
  shadow_file="$(_auth_get_shadow_file)"
  [[ ! -f "$shadow_file" ]] && return 1

  local target_user="${1:-${USER:-$(whoami)}}"
  local hash=""
  hash=$(awk -F: -v u="$target_user" '$1 == u {print $2; exit}' "$shadow_file" 2> /dev/null)
  [[ -n "$hash" ]] || return 1
  print -r -- "$hash"
  return 0
}

_auth_verify_password() {
  local candidate="$1"
  local stored="$2"
  [[ -z "$candidate" || -z "$stored" ]] && return 1

  if [[ "$stored" == \$[0-9a-zA-Z]\$* ]]; then
    local salt=""
    salt=$(printf '%s' "$stored" | cut -d'$' -f3)
    local algo=""
    algo=$(printf '%s' "$stored" | cut -d'$' -f2)
    local flag="-6"
    [[ "$algo" == "5" ]] && flag="-5"
    [[ "$algo" == "1" ]] && flag="-1"

    local test_hash=""
    if command -v openssl > /dev/null 2>&1; then
      test_hash=$(printf '%s' "$candidate" | openssl passwd "$flag" -salt "$salt" -stdin 2> /dev/null)
    fi
    if [[ -n "$test_hash" && "$test_hash" == "$stored" ]]; then
      return 0
    fi
  fi

  return 1
}

_auth_read_secret() {
  local _prompt="${1:-}"
  local _target_var="$2"
  local orig_tty
  orig_tty=$(stty -g 2> /dev/null)

  local _rc=0
  {
    trap '[[ -n "$orig_tty" ]] && stty "$orig_tty" 2>/dev/null || stty sane 2>/dev/null; return 130' INT TERM
    if [[ -n "$_prompt" ]]; then
      read -rs "${_target_var}?$_prompt"
    else
      read -rs "${_target_var}"
    fi
    _rc=$?
  } always {
    trap - INT TERM
    [[ -n "$orig_tty" ]] && stty "$orig_tty" 2> /dev/null || stty sane 2> /dev/null
  }

  return $_rc
}
