#####################
# Root switch wrapper
#####################

su() {
  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    cat << 'EOF'
Usage:
 su [options] [-] [<user> [<argument>...]]

Change the effective user ID and group ID to that of <user>.
A mere - implies -l. If <user> is not given, root is assumed.

Options:
 -m, -p, --preserve-environment  do not reset environment variables
 -g, --group <group>             specify the primary group
 -G, --supp-group <group>        specify a supplemental group
 -, -l, --login                  make the shell a login shell
 -c, --command <command>         pass a single command to the shell with -c
 --session-command <command>     pass a single command to the shell with -c
                                   and do not create a new session
 -f, --fast                      pass -f to the shell (for csh or tcsh)
 -s, --shell <shell>             run <shell> if /etc/shells allows it
 -P, --pty                       create a new pseudo-terminal

 -h, --help                      display this help
 -V, --version                   display version

For more details see su(1).
EOF
    return 0
  fi

  if [[ "$1" == "-V" || "$1" == "--version" ]]; then
    print "su from util-linux 2.39.3"
    return 0
  fi

  if [[ "$EUID" -eq 0 ]]; then
    if [[ $# -eq 0 || "$1" == "root" || "$1" == "-" || "$1" == "-l" || "$1" == "--login" ]]; then
      print -u2 "su: already running as root (type 'exit' to return)"
      return 0
    fi
  fi

  local current_user="${USER:-$(whoami)}"
  local SUDO_HASH=""
  SUDO_HASH=$(_auth_get_hash "$current_user")

  if [[ -z "$SUDO_HASH" ]]; then
    print -u2 "su: Authentication service cannot retrieve authentication info"
    return 1
  fi

  local _sudo_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/muxrc"
  local _sudo_ts_file="$_sudo_cache_dir/sudo_ts"
  local authenticated=0

  if [[ "$EUID" -eq 0 ]]; then
    authenticated=1
  elif [[ -n "${_SUDO_TS:-}" && "${_SUDO_TS}" =~ ^[0-9]+$ ]]; then
    local now=${EPOCHSECONDS:-0}
    if ((now >= _SUDO_TS && now - _SUDO_TS <= 900)); then
      authenticated=1
    fi
  fi

  if ((authenticated == 0)); then
    local user_pass
    if ! _auth_read_secret "Password: " user_pass; then
      print -u2 ""
      return 130
    fi
    print -u2 ""

    if ! _auth_verify_password "$user_pass" "$SUDO_HASH"; then
      print -u2 "su: Authentication failure"
      return 1
    fi

    if [[ "$EUID" -ne 0 ]]; then
      typeset -g _SUDO_TS=$EPOCHSECONDS
    fi
  fi

  local su_bin=""
  if command -v su > /dev/null 2>&1; then
    su_bin="su"
  elif [[ -x /system/bin/su ]]; then
    su_bin="/system/bin/su"
  elif [[ -x /system/xbin/su ]]; then
    su_bin="/system/xbin/su"
  fi

  if [[ -z "$su_bin" ]] && ! whence -p sudo > /dev/null 2>&1; then
    print -u2 "su: device is not rooted"
    return 1
  fi

  local is_login=0
  if [[ "$1" == "-" || "$1" == "-l" || "$1" == "--login" ]]; then
    is_login=1
    shift
  fi

  if [[ "$1" == "root" || "$1" == "${USER:-$(whoami)}" ]]; then
    shift
  fi

  local termux_prefix="${PREFIX}"
  local env_vars="export PATH=\"$termux_prefix/bin:$termux_prefix/sbin:/system/bin:/system/xbin:\$PATH\"; export HOME=\"$HOME\"; export TERM=\"$TERM\"; export LANG=\"$LANG\"; unset LD_LIBRARY_PATH LD_PRELOAD; cd \"$PWD\";"
  local root_shell="${SHELL:-$termux_prefix/bin/zsh}"

  if [[ "$1" == "-c" || "$1" == "--command" || "$1" == "--command="* ]]; then
    local cmd_str=""
    if [[ "$1" == "--command="* ]]; then
      cmd_str="${1#--command=}"
      shift
    else
      shift
      if [[ $# -eq 0 ]]; then
        print -u2 "su: option requires an argument -- 'c'"
        print -u2 "Try 'su --help' for more information."
        return 1
      fi
      cmd_str="$*"
    fi

    if [[ -n "$su_bin" ]]; then
      command "$su_bin" -c "$env_vars $cmd_str"
      return $?
    else
      command sudo zsh -c "$env_vars $cmd_str"
      return $?
    fi
  fi

  if [[ $# -eq 0 ]]; then
    local shell_cmd="exec $root_shell"
    ((is_login)) && shell_cmd="exec $root_shell -l"

    if [[ -n "$su_bin" ]]; then
      command "$su_bin" -c "$env_vars $shell_cmd"
      return $?
    else
      command sudo --shell=zsh su
      return $?
    fi
  fi

  if [[ -n "$su_bin" ]]; then
    command "$su_bin" -c "$env_vars exec ${(q)@}"
    return $?
  else
    command sudo "$@"
    return $?
  fi
}
