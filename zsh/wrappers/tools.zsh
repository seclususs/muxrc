#######################
# Custom tools wrappers
#######################

typeset -g MUXRC_DIR="${MUXRC_DIR:-${ZSH_CONFIG_DIR:+${ZSH_CONFIG_DIR:h}}}"
typeset -g MUXRC_DIR="${MUXRC_DIR:-$HOME/muxrc}"
source "${MUXRC_DIR}/lib/init.sh"

_muxrc_run_as_root() {
  if [[ "$EUID" -eq 0 ]]; then
    bash "$@"
  elif whence -p sudo > /dev/null 2>&1; then
    sudo bash "$@"
  else
    log_error "root access required (sudo not found)"
    return 1
  fi
}

###############
# Network Tools
###############
_net_help() {
  cat << 'EOF'
net: network opsec & privacy tools

usage: net <command> [args]

commands:
  sweep [cidr]         scan local arp subnet
  mac [action]         mac address spoofer
  identity [action]    rotate opsec identity
  killswitch [act]     firewall leak killswitch
  tor [action]         tor opsec service

run 'net <command> -h' for subcommand details
EOF
}

net() {
  local subcmd="${1:-}"

  case "$subcmd" in
    -h | --help)
      _net_help
      return 0
      ;;
    sweep)
      shift
      local cidr="${1:-}"
      if [[ "$cidr" == "-h" || "$cidr" == "--help" ]]; then
        bash "${MUXRC_DIR}/tools/sh/net/sweep.sh" -h
        return 0
      fi
      if whence -p sudo > /dev/null 2>&1; then
        sudo bash "${MUXRC_DIR}/tools/sh/net/sweep.sh" "$@"
      else
        bash "${MUXRC_DIR}/tools/sh/net/sweep.sh" "$@"
      fi
      ;;
    mac)
      shift
      local action="${1:-show}"
      if [[ "$action" == "-h" || "$action" == "--help" || "$action" == "show" ]]; then
        bash "${MUXRC_DIR}/tools/sh/net/mac.sh" "$@"
      else
        _muxrc_run_as_root "${MUXRC_DIR}/tools/sh/net/mac.sh" "$@"
      fi
      ;;
    identity)
      shift
      local action="${1:-show}"
      if [[ "$action" == "-h" || "$action" == "--help" || "$action" == "show" || "$action" == "status" ]]; then
        bash "${MUXRC_DIR}/tools/sh/net/identity.sh" "$@"
      else
        _muxrc_run_as_root "${MUXRC_DIR}/tools/sh/net/identity.sh" "$@"
      fi
      ;;
    killswitch)
      shift
      local action="${1:-status}"
      if [[ "$action" == "-h" || "$action" == "--help" || "$action" == "status" ]]; then
        bash "${MUXRC_DIR}/tools/sh/net/killswitch.sh" "$@"
      else
        _muxrc_run_as_root "${MUXRC_DIR}/tools/sh/net/killswitch.sh" "$@"
      fi
      ;;
    tor)
      shift
      bash "${MUXRC_DIR}/tools/sh/net/tor.sh" "$@"
      ;;
    "")
      _net_help
      return 1
      ;;
    *)
      log_error "unknown command: $subcmd (see: net -h)"
      return 1
      ;;
  esac
}

#############
# Media Tools
#############
_media_help() {
  cat << 'EOF'
media: media & file processing tools

usage: media <command> [args]

commands:
  dupes <dir>          find duplicate files
  strip <dir>          strip exif metadata
  spoof [pre] <target> inject decoy metadata
  sync <target>        sync dates to exif
  rename <dir> <pfx>   rename photos by date
  compress <video>     compress video to hevc

run 'media <command> -h' for subcommand details
EOF
}

media() {
  local subcmd="${1:-}"

  case "$subcmd" in
    -h | --help)
      _media_help
      return 0
      ;;
    dupes)
      shift
      bash "${MUXRC_DIR}/tools/sh/media/dupes.sh" "$@"
      ;;
    strip)
      shift
      bash "${MUXRC_DIR}/tools/sh/media/strip.sh" "$@"
      ;;
    spoof)
      shift
      if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        bash "${MUXRC_DIR}/tools/sh/media/spoof.sh" -h
        return 0
      fi
      if [[ $# -eq 0 ]]; then
        log_error "usage: media spoof [preset] <target> (see -h)"
        return 1
      fi

      bash "${MUXRC_DIR}/tools/sh/media/spoof.sh" "$@"
      ;;
    sync)
      shift
      bash "${MUXRC_DIR}/tools/sh/media/date-sync.sh" "$@"
      ;;
    rename)
      shift
      bash "${MUXRC_DIR}/tools/sh/media/rename.sh" "$@"
      ;;
    compress)
      shift
      bash "${MUXRC_DIR}/tools/sh/media/compress.sh" "$@"
      ;;
    dispatch | volume | play | monitor)
      # Pass-through to Android media framework command
      if [[ -x /system/bin/media ]]; then
        /system/bin/media "$@"
      else
        log_error "system media binary not found"
        return 1
      fi
      ;;
    "")
      _media_help
      return 1
      ;;
    *)
      if [[ -x /system/bin/media ]] && /system/bin/media "$@" 2> /dev/null; then
        return $?
      fi
      log_error "unknown command: $subcmd (see: media -h)"
      return 1
      ;;
  esac
}

################
# Security Tools
################
_sec_help() {
  cat << 'EOF'
sec: data security & privacy tools

usage: sec <command> [args]

commands:
  encrypt <file>       aes-256-cbc encrypt to vault
  decrypt <f> [out]    decrypt vault file
  stego                hide/extract in image
  shred <file>         secure permanent delete
  panic [flags]        emergency one-shot secure burn

run 'sec <command> -h' for subcommand details
EOF
}

sec() {
  local subcmd="${1:-}"

  case "$subcmd" in
    -h | --help)
      _sec_help
      return 0
      ;;
    encrypt)
      shift
      if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        bash "${MUXRC_DIR}/tools/sh/sec/crypt.sh" -h
        return 0
      fi
      if [[ $# -eq 0 ]]; then
        log_error "usage: sec encrypt <file> (see -h)"
        return 1
      fi

      local target_file="$1"
      if [[ ! -f "$target_file" ]]; then
        log_error "file '$target_file' not found"
        return 1
      fi

      local pass1 pass2
      log_prompt "enter encryption password: "
      read -rs pass1
      print -u2 ""

      log_prompt "confirm password: "
      read -rs pass2
      print -u2 ""

      if [[ -z "$pass1" ]]; then
        log_error "password cannot be empty"
        return 1
      fi

      if [[ "$pass1" != "$pass2" ]]; then
        log_error "passwords do not match"
        return 1
      fi

      MUXRC_CRYPT_PASS="$pass1" bash "${MUXRC_DIR}/tools/sh/sec/crypt.sh" --encrypt "$target_file"
      ;;
    decrypt)
      shift
      if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        bash "${MUXRC_DIR}/tools/sh/sec/crypt.sh" -h
        return 0
      fi
      if [[ $# -eq 0 ]]; then
        log_error "usage: sec decrypt <encrypted_file> [out] (see -h)"
        return 1
      fi

      local target_file="$1"
      local output_file="${2:-}"

      if [[ ! -f "$target_file" ]]; then
        log_error "file '$target_file' not found"
        return 1
      fi

      local pass
      log_prompt "enter decryption password: "
      read -rs pass
      print -u2 ""

      if [[ -z "$pass" ]]; then
        log_error "password cannot be empty"
        return 1
      fi

      MUXRC_CRYPT_PASS="$pass" bash "${MUXRC_DIR}/tools/sh/sec/crypt.sh" --decrypt "$target_file" "$output_file"
      ;;
    stego)
      shift
      bash "${MUXRC_DIR}/tools/sh/sec/stego.sh" "$@"
      ;;
    shred)
      shift
      bash "${MUXRC_DIR}/lib/shredder.sh" "$@"
      ;;
    panic)
      shift
      bash "${MUXRC_DIR}/tools/sh/sec/panic.sh" "$@"
      local exit_code=$?
      if [[ $exit_code -eq 0 ]]; then
        local arg
        local is_dry=0
        for arg in "$@"; do
          if [[ "$arg" == "-n" || "$arg" == "--dry-run" || "$arg" == "-h" || "$arg" == "--help" ]]; then
            is_dry=1
            break
          fi
        done
        if [[ $is_dry -eq 0 ]]; then
          HISTSIZE=0
          SAVEHIST=0
          if whence fc > /dev/null 2>&1; then
            fc -p
          fi
        fi
      fi
      return $exit_code
      ;;
    "")
      _sec_help
      return 1
      ;;
    *)
      log_error "unknown command: $subcmd (see: sec -h)"
      return 1
      ;;
  esac
}
