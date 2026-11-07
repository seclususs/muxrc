#####################
# Root access wrapper
#####################

sudo() {
  setopt localoptions nomonitor
  zmodload zsh/datetime 2> /dev/null

  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "usage: sudo -h | -K | -k | -V"
    echo "usage: sudo -v [-AknS] [-g group] [-h host] [-p prompt] [-u user]"
    echo "usage: sudo -l [-AknS] [-g group] [-h host] [-p prompt] [-U user] [-u user] [command]"
    return 0
  fi

  if [[ "$1" == "-V" || "$1" == "--version" ]]; then
    echo "Sudo version 1.9.15p5"
    return 0
  fi

  local _sudo_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/muxrc"
  local _sudo_ts_file="$_sudo_cache_dir/sudo_ts"

  if [[ "$1" == "-k" || "$1" == "-K" ]]; then
    rm -f "$_sudo_ts_file" 2> /dev/null
    if [[ $# -eq 1 ]]; then
      return 0
    fi
    shift
  fi

  if [[ $# -eq 0 ]]; then
    print -u2 "usage: sudo -h | -K | -k | -V"
    print -u2 "usage: sudo -v [-AknS] [-g group] [-h host] [-p prompt] [-u user]"
    print -u2 "usage: sudo -l [-AknS] [-g group] [-h host] [-p prompt] [-U user] [-u user] [command]"
    return 1
  fi

  if [[ "$1" =~ ^(apt|apt-get|pkg)$ ]]; then
    command "$1" "${@:2}"
    return $?
  fi

  local current_user="${USER:-$(whoami)}"
  local SUDO_HASH=""
  SUDO_HASH=$(_auth_get_hash "$current_user")

  if [[ -z "$SUDO_HASH" ]]; then
    print -u2 "sudo: /"etc"/sudoers is world writable"
    return 1
  fi

  local attempts=0
  local max_attempts=3
  local authenticated=0
  local user_pass

  if [[ "$EUID" -eq 0 ]]; then
    authenticated=1
  elif [[ -f "$_sudo_ts_file" ]]; then
    local last_auth
    last_auth=$(< "$_sudo_ts_file" 2> /dev/null)
    if [[ -n "$last_auth" && "$last_auth" =~ ^[0-9]+$ ]]; then
      local now=${EPOCHSECONDS:-0}
      if ((now >= last_auth && now - last_auth <= 900)); then
        authenticated=1
      fi
    fi
  fi

  if ((authenticated == 0)); then
    while ((attempts < max_attempts)); do
      if ! _auth_read_secret "[sudo] password for $current_user: " user_pass; then
        print -u2 ""
        return 130
      fi
      print -u2 ""

      if _auth_verify_password "$user_pass" "$SUDO_HASH"; then
        authenticated=1
        if [[ "$EUID" -ne 0 ]]; then
          mkdir -p "$_sudo_cache_dir" 2> /dev/null
          print "$EPOCHSECONDS" > "$_sudo_ts_file" 2> /dev/null
          chmod 600 "$_sudo_ts_file" 2> /dev/null
        fi
        break
      else
        print -u2 "Sorry, try again."
        ((attempts++))
      fi
    done
  fi

  if ((authenticated == 0)); then
    print -u2 "sudo: $max_attempts incorrect password attempts"
    return 1
  fi

  if [[ "$1" == "-v" ]]; then
    return 0
  fi

  local su_bin=""
  if command -v su > /dev/null 2>&1; then
    su_bin="su"
  elif [[ -x /system/bin/su ]]; then
    su_bin="/system/bin/su"
  elif [[ -x /system/xbin/su ]]; then
    su_bin="/system/xbin/su"
  fi

  local termux_prefix="${PREFIX}"
  local env_vars="export PATH=\"$termux_prefix/bin:$termux_prefix/sbin:/system/bin:/system/xbin:\$PATH\"; export HOME=\"$HOME\"; export TERM=\"$TERM\"; export LANG=\"$LANG\"; unset LD_LIBRARY_PATH LD_PRELOAD; cd \"$PWD\";"

  if [[ "$1" == "su" || "$1" == "-s" || "$1" == "-i" ]]; then
    if [[ "$EUID" -eq 0 ]]; then
      print -u2 "sudo: already running as root (type 'exit' to return)"
      return 0
    fi
    local root_shell="${SHELL:-$termux_prefix/bin/zsh}"
    local shell_cmd="exec $root_shell"
    [[ "$1" == "-i" ]] && shell_cmd="exec $root_shell -l"

    if [[ -n "$su_bin" ]]; then
      command "$su_bin" -c "$env_vars $shell_cmd"
      return $?
    elif whence -p sudo > /dev/null 2>&1; then
      command sudo --shell=zsh su
      return $?
    else
      print -u2 "su: device is not rooted"
      return 1
    fi
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -E | --preserve-env) shift ;;
      -u | --user)
        if [[ $# -lt 2 ]]; then
          print -u2 "sudo: option requires an argument -- 'u'"
          return 1
        fi
        shift 2
        ;;
      --) shift; break ;;
      *) break ;;
    esac
  done

  if [[ $# -eq 0 ]]; then
    print -u2 "usage: sudo -h | -K | -k | -V"
    print -u2 "usage: sudo -v [-AknS] [-g group] [-h host] [-p prompt] [-u user]"
    print -u2 "usage: sudo -l [-AknS] [-g group] [-h host] [-p prompt] [-U user] [-u user] [command]"
    return 1
  fi

  if [[ -n "$su_bin" ]]; then
    local _cmd_payload="${(j: :)${(q)@}}"
    if [[ "$1" =~ ^(pm|cmd|am|svc|settings|content|input|dpm)$ ]]; then
      print -r -- "$env_vars $_cmd_payload" | command "$su_bin"
    else
      command "$su_bin" -c "$env_vars exec $_cmd_payload"
      return $?
    fi
  elif whence -p sudo > /dev/null 2>&1; then
    command sudo "$@"
    return $?
  else
    print -u2 "sudo: no root provider available on this device"
    return 1
  fi
}
