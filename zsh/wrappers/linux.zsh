########################
# Linux command wrappers
########################

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

  local _sudo_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/muxrc"
  local HASH_FILE="$_sudo_cfg_dir/sudo_hash"
  [[ ! -f "$HASH_FILE" && -f "$HOME/.sudo_hash" ]] && HASH_FILE="$HOME/.sudo_hash"
  local SUDO_HASH=""
  [[ -f "$HASH_FILE" ]] && SUDO_HASH=$(< "$HASH_FILE" 2> /dev/null)

  if [[ -z "$SUDO_HASH" ]]; then
    print -u2 "sudo: /"etc"/sudoers is world writable"
    return 1
  fi

  local attempts=0
  local max_attempts=3
  local authenticated=0
  local current_user="${USER:-$(whoami)}"
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
      if ! read -rs "user_pass?[sudo] password for $current_user: "; then
        print -u2 ""
        return 1
      fi
      print -u2 ""

      local input_hash
      input_hash=$(echo -n "$user_pass" | sha256sum | awk '{print $1}')
      if [[ "$input_hash" == "$SUDO_HASH" ]]; then
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

  if [[ "$1" == "su" || "$1" == "-s" || "$1" == "-i" ]]; then
    if [[ "$EUID" -eq 0 ]]; then
      print -u2 "sudo: already running as root (type 'exit' to return)"
      return 0
    fi
    if whence -p sudo > /dev/null 2>&1; then
      command sudo --shell=zsh su
      return $?
    elif command -v su > /dev/null 2>&1; then
      command su -c "exec zsh"
      return $?
    else
      print -u2 "su: device is not rooted"
      return 1
    fi
  fi

  if whence -p sudo > /dev/null 2>&1; then
    command sudo "$@"
    return $?
  fi

  local termux_prefix="${PREFIX}"
  local env_vars="export PATH=/system/bin:/system/xbin:$PATH:$termux_prefix/bin; export HOME=\"$HOME\"; export TERM=\"$TERM\"; export LANG=\"$LANG\"; unset LD_LIBRARY_PATH LD_PRELOAD; cd \"$PWD\";"

  if command -v su > /dev/null 2>&1; then
    if [[ "$1" =~ ^(pm|cmd|am|svc|settings|content|input|dpm)$ ]]; then
      print -r "$env_vars ${(q)@}" | command su
    else
      command su -c "$env_vars exec ${(q)@}"
      return $?
    fi
  else
    print -u2 "sudo: no root provider available on this device"
    return 1
  fi
}

#####################
# Root switch wrapper
#####################
su() {
  if [[ "$EUID" -eq 0 ]]; then
    if [[ $# -eq 0 || "$1" == "root" || "$1" == "-" || "$1" == "-l" ]]; then
      print -u2 "su: already running as root (type 'exit' to return)"
      return 0
    else
      if command -v su > /dev/null 2>&1; then
        command su "$@"
        return $?
      else
        print -u2 "su: device is not rooted"
        return 1
      fi
    fi
  fi

  local _sudo_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/muxrc"
  local HASH_FILE="$_sudo_cfg_dir/sudo_hash"
  [[ ! -f "$HASH_FILE" && -f "$HOME/.sudo_hash" ]] && HASH_FILE="$HOME/.sudo_hash"
  local SUDO_HASH=""
  [[ -f "$HASH_FILE" ]] && SUDO_HASH=$(< "$HASH_FILE" 2> /dev/null)

  if [[ -z "$SUDO_HASH" ]]; then
    print -u2 "su: Authentication service cannot retrieve authentication info"
    return 1
  fi

  local _sudo_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/muxrc"
  local _sudo_ts_file="$_sudo_cache_dir/sudo_ts"
  local authenticated=0

  if [[ -f "$_sudo_ts_file" ]]; then
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
    local user_pass
    if ! read -rs "user_pass?Password: "; then
      print -u2 ""
      return 1
    fi
    print -u2 ""

    local input_hash
    input_hash=$(echo -n "$user_pass" | sha256sum | awk '{print $1}')
    if [[ "$input_hash" != "$SUDO_HASH" ]]; then
      print -u2 "su: Authentication failure"
      return 1
    fi

    mkdir -p "$_sudo_cache_dir" 2> /dev/null
    print "$EPOCHSECONDS" > "$_sudo_ts_file" 2> /dev/null
    chmod 600 "$_sudo_ts_file" 2> /dev/null
  fi

  if [[ $# -gt 0 && "$1" != "root" && "$1" != "-" && "$1" != "-l" ]]; then
    if whence -p sudo > /dev/null 2>&1; then
      command sudo "$@"
      return $?
    elif command -v su > /dev/null 2>&1; then
      command su "$@"
      return $?
    else
      print -u2 "su: device is not rooted"
      return 1
    fi
  fi

  if whence -p sudo > /dev/null 2>&1; then
    command sudo --shell=zsh su
    return $?
  elif command -v su > /dev/null 2>&1; then
    command su -c "exec zsh"
    return $?
  else
    print -u2 "su: device is not rooted"
    return 1
  fi
}

#########################
# Service manager wrapper
#########################
systemctl() {
  if [[ $# -lt 2 ]]; then
    echo "Usage: systemctl {start|stop|restart|status|enable|disable} <service>"
    return 1
  fi

  local action="$1"
  local service="$2"

  case "$action" in
    start) command sv up "$service" 2> /dev/null ;;
    stop) command sv down "$service" 2> /dev/null ;;
    restart) command sv restart "$service" 2> /dev/null ;;
    status) command sv status "$service" ;;
    enable)
      if [ -d "$PREFIX/share/termux-services/$service" ]; then
        ln -sf "$PREFIX/share/termux-services/$service" "$PREFIX/var/service/"
        echo "Created symlink /"etc"/systemd/system/multi-user.target.wants/${service}.service → /"lib"/systemd/system/${service}.service."
      else
        echo "Failed to enable unit: Unit file ${service}.service does not exist."
      fi
      ;;
    disable)
      rm -f "$PREFIX/var/service/$service"
      echo "Removed /"etc"/systemd/system/multi-user.target.wants/${service}.service."
      ;;
    *)
      echo "Unknown operation '$action'."
      return 1
      ;;
  esac
}

#########################
# Package manager wrapper
#########################
apt() {
  if [[ "$1" =~ ^(install|search|update|upgrade|remove|autoremove|clean)$ ]]; then
    command pkg "$@"
  else
    command apt "$@"
  fi
}

####################
# Legacy apt wrapper
####################
apt-get() { apt "$@"; }

#######################
# Fallback ping command
#######################
ping() {
  local -a args=("$@")
  if [[ ! " ${args[*]} " =~ [[:space:]]-c[[:space:]] ]]; then
    args=(-c 4 "${args[@]}")
  fi

  if command ping "${args[@]}"; then
    return 0
  fi

  local code=$?
  if [[ -x /system/bin/ping ]] && /system/bin/ping "${args[@]}"; then
    return 0
  fi

  if command -v su > /dev/null 2>&1; then
    su -c "/system/bin/ping ${(q)args[@]}"
    return $?
  fi

  return $code
}

###########################
# Safe permissions modifier
###########################
chmod() {
  if [[ "$*" == *"/sdcard/"* || "$*" == *"/storage/emulated/"* || "$*" == *"$HOME/storage/"* || "$*" == *"/storage/"* ]]; then
    return 0
  fi
  command chmod "$@"
}

##########################
# Dummy ownership function
##########################
chown() {
  return 0
}

#####################
# File opener wrapper
#####################
xdg-open() {
  if command -v termux-open > /dev/null 2>&1; then
    command termux-open "$@"
  else
    echo "xdg-open: command not found. Please run: apt install termux-api"
    return 127
  fi
}

#############################
# Universal archive extractor
#############################
ex() {
  if [[ -f $1 ]]; then
    case $1 in
      *.tar.bz2) tar xjf "$1" ;;
      *.tar.gz) tar xzf "$1" ;;
      *.bz2) bunzip2 "$1" ;;
      *.rar) unrar x "$1" ;;
      *.gz) gunzip "$1" ;;
      *.tar) tar xf "$1" ;;
      *.tbz2) tar xjf "$1" ;;
      *.tgz) tar xzf "$1" ;;
      *.zip) unzip "$1" ;;
      *.Z) uncompress "$1" ;;
      *.7z) 7z x "$1" ;;
      *) echo "ex: '$1' has unknown archive format." ;;
    esac
  else
    echo "ex: '$1' is not a valid file."
  fi
}

###########################
# Command not found handler
###########################
command_not_found_handler() {
  local cmd="$1"
  local matches
  matches=$(pkg search "$cmd" 2> /dev/null | grep "^$cmd/")

  if [[ -n "$matches" ]]; then
    echo "zsh: command not found: $cmd"
    echo "Did you mean to install it? Try: pkg install $cmd"
  else
    echo "zsh: command not found: $cmd"
  fi

  return 127
}

###########################
# Notification task wrapper
###########################
notify-task() {
  (($# == 0)) && {
    echo "usage: notify-task <cmd> [args...]"
    return 1
  }

  local label="$*"
  local start=$(date +%s)

  "$@"
  local code=$?
  local secs=$(($(date +%s) - start))
  local task_status="done in ${secs}s"
  ((code != 0)) && task_status="failed (exit ${code}) after ${secs}s"

  termux-vibrate -d 250 > /dev/null 2>&1
  command -v termux-notification > /dev/null 2>&1 && termux-notification --id notify-task --title "${label:0:40}" --content "$task_status"
  return $code
}

###########################
# Clipboard history helpers
###########################
CLIP_HISTORY_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/muxrc/clip_history.log"

clip-save() {
  mkdir -p "${CLIP_HISTORY_FILE:h}"
  local cur=$(termux-clipboard-get 2> /dev/null)
  [[ -z "$cur" ]] && return
  [[ "$(tail -n1 "$CLIP_HISTORY_FILE" 2> /dev/null)" != "$cur" ]] && echo "$cur" >> "$CLIP_HISTORY_FILE"
}

clip-watch() {
  while true; do
    clip-save
    sleep 2
  done
}

clip-pick() {
  [[ -f "$CLIP_HISTORY_FILE" ]] || return 1
  local pick=$(tac "$CLIP_HISTORY_FILE" | fzf --prompt="clip> ")
  [[ -n "$pick" ]] && echo -n "$pick" | termux-clipboard-set && termux-toast "copied"
}

########################
# Safe trash and untrash
########################
TRASH_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"

trash() {
  mkdir -p "$TRASH_DIR"
  local f
  for f in "$@"; do
    [[ -e "$f" ]] || {
      echo "trash: no such file: $f"
      continue
    }
    mv -- "$f" "$TRASH_DIR/${f:t}.$(date +%s)"
  done
}

untrash() {
  local search_dirs=()
  [[ -d "$TRASH_DIR" ]] && search_dirs+=("$TRASH_DIR")
  [[ -d "$HOME/.trash" && "$HOME/.trash" != "$TRASH_DIR" ]] && search_dirs+=("$HOME/.trash")
  local item
  item=$(for d in "${search_dirs[@]}"; do ls -1t "$d" 2> /dev/null; done | fzf --prompt="restore> ") || return
  if [[ -n "$item" ]]; then
    if [[ -e "$TRASH_DIR/$item" ]]; then
      mv -- "$TRASH_DIR/$item" "./${item%.*}"
    elif [[ -e "$HOME/.trash/$item" ]]; then
      mv -- "$HOME/.trash/$item" "./${item%.*}"
    fi
  fi
}

#####################
# Network info helper
#####################
net-info() {
  command -v termux-wifi-connectioninfo > /dev/null 2>&1 || {
    echo "net-info: needs termux-api"
    return 1
  }
  command -v jq > /dev/null 2>&1 || {
    echo "net-info: needs jq"
    return 1
  }
  local ip=$(termux-wifi-connectioninfo | jq -r '.ip // empty')
  [[ -z "$ip" || "$ip" == null ]] && {
    echo "net-info: no wifi ip"
    return 1
  }
  local cmd="ssh ${USER:-$(whoami)}@${ip} -p 8022"
  echo "$cmd"
  command -v termux-toast > /dev/null 2>&1 && termux-toast "$cmd" || true
}
