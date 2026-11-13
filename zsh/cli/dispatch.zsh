#####################
# Custom tools router
#####################

typeset -g MUXRC_DIR="${MUXRC_DIR:-${ZSH_CONFIG_DIR:+${ZSH_CONFIG_DIR:h}}}"
typeset -g MUXRC_DIR="${MUXRC_DIR:-$HOME/muxrc}"
source "${MUXRC_DIR}/sh/init.sh"

_run_as_root() {
  if [[ "$EUID" -eq 0 ]]; then
    bash "$@"
  elif (( $+functions[sudo] )) || whence sudo > /dev/null 2>&1; then
    sudo bash "$@"
  else
    log_error "root required"
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
  remote [action]      ssh remote manager

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
        bash "${MUXRC_DIR}/bash/net/sweep.sh" -h
        return 0
      fi
      if [[ "$EUID" -eq 0 ]]; then
        bash "${MUXRC_DIR}/bash/net/sweep.sh" "$@"
      elif [[ -x /system/bin/su || -x /system/xbin/su || -n "$(whence -p sudo 2>/dev/null)" ]]; then
        sudo bash "${MUXRC_DIR}/bash/net/sweep.sh" "$@"
      else
        bash "${MUXRC_DIR}/bash/net/sweep.sh" "$@"
      fi
      ;;
    mac)
      shift
      local action="${1:-show}"
      if [[ "$action" == "-h" || "$action" == "--help" || "$action" == "show" ]]; then
        bash "${MUXRC_DIR}/bash/net/mac.sh" "$@"
      else
        _run_as_root "${MUXRC_DIR}/bash/net/mac.sh" "$@"
      fi
      ;;
    identity)
      shift
      local action="${1:-show}"
      if [[ "$action" == "-h" || "$action" == "--help" || "$action" == "show" || "$action" == "status" ]]; then
        bash "${MUXRC_DIR}/bash/net/identity.sh" "$@"
      else
        _run_as_root "${MUXRC_DIR}/bash/net/identity.sh" "$@"
      fi
      ;;
    killswitch)
      shift
      local action="${1:-status}"
      if [[ "$action" == "-h" || "$action" == "--help" || "$action" == "status" ]]; then
        bash "${MUXRC_DIR}/bash/net/killswitch.sh" "$@"
      else
        _run_as_root "${MUXRC_DIR}/bash/net/killswitch.sh" "$@"
      fi
      ;;
    tor)
      shift
      bash "${MUXRC_DIR}/bash/net/tor.sh" "$@"
      ;;
    remote)
      shift
      bash "${MUXRC_DIR}/bash/net/remote.sh" "$@"
      ;;
    "")
      _net_help
      return 1
      ;;
    *)
      log_error "unknown command: $subcmd"
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
  strip <target>       strip exif metadata (file/dir)
  spoof [pre] <target> inject decoy metadata (file/dir)
  sync <target>        sync dates to exif (file/dir)
  rename <dir> <pfx>   rename photos by date
  compress <target>    compress video to hevc (file/dir)

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
      bash "${MUXRC_DIR}/bash/media/dupes.sh" "$@"
      ;;
    strip)
      shift
      bash "${MUXRC_DIR}/bash/media/strip.sh" "$@"
      ;;
    spoof)
      shift
      bash "${MUXRC_DIR}/bash/media/spoof.sh" "$@"
      ;;
    sync)
      shift
      bash "${MUXRC_DIR}/bash/media/date-sync.sh" "$@"
      ;;
    rename)
      shift
      bash "${MUXRC_DIR}/bash/media/rename.sh" "$@"
      ;;
    compress)
      shift
      bash "${MUXRC_DIR}/bash/media/compress.sh" "$@"
      ;;
    dispatch | volume | play | monitor)
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
      log_error "unknown command: $subcmd"
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
      bash "${MUXRC_DIR}/bash/sec/crypt.sh" --encrypt "$@"
      ;;
    decrypt)
      shift
      bash "${MUXRC_DIR}/bash/sec/crypt.sh" --decrypt "$@"
      ;;
    stego)
      shift
      bash "${MUXRC_DIR}/bash/sec/stego.sh" "$@"
      ;;
    shred)
      shift
      bash "${MUXRC_DIR}/bash/sec/shred.sh" "$@"
      ;;
    panic)
      shift
      bash "${MUXRC_DIR}/bash/sec/panic.sh" "$@"
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
      log_error "unknown command: $subcmd"
      return 1
      ;;
  esac
}
