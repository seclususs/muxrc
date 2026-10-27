#######################
# Custom tools wrappers
#######################

typeset -g MUXRC_DIR="${MUXRC_DIR:-$HOME/muxrc}"
source "${MUXRC_DIR}/lib/init.sh"

########################
# Duplicate File Cleaner
########################
clean-dupes() {
  if [[ $# -eq 0 ]]; then
    log_error "usage: clean-dupes <target_directory>"
    return 1
  fi

  local target_dir="$1"

  if [[ ! -d "$target_dir" ]]; then
    log_error "directory '$target_dir' not found"
    return 1
  fi

  if [[ ! -r "$target_dir" ]]; then
    log_error "directory '$target_dir' is not readable"
    return 1
  fi

  bash "${MUXRC_DIR}/tools/sh/clean-dupes.sh" "$target_dir"
}

#######################
# EXIF Metadata Cleaner
#######################
clean-meta() {
  if [[ $# -eq 0 ]]; then
    log_error "usage: clean-meta <target_directory>"
    return 1
  fi

  local target_dir="$1"

  if [[ ! -d "$target_dir" ]]; then
    log_error "directory '$target_dir' not found"
    return 1
  fi

  bash "${MUXRC_DIR}/tools/sh/exif-cleaner.sh" "$target_dir"
}

#####################
# Steganography Vault
#####################
stego-vault() {
  bash "${MUXRC_DIR}/tools/sh/steganography.sh"
}

##############
# File Renamer
##############
rename-by-date() {
  if [[ $# -lt 2 ]]; then
    log_error "usage: rename-by-date <directory> <prefix>"
    return 1
  fi

  local target_dir="$1"
  local prefix="$2"

  if [[ ! -d "$target_dir" ]]; then
    log_error "directory '$target_dir' not found"
    return 1
  fi

  bash "${MUXRC_DIR}/tools/sh/file-renamer.sh" "$target_dir" "$prefix"
}

##############
# EXIF Spoofer
##############
spoof-meta() {
  if [[ $# -lt 2 ]]; then
    log_error "usage: spoof-meta <preset_name_or_path> <image_or_directory>"
    return 1
  fi

  local preset_input="$1"
  local image_file="$2"
  local preset_file=""

  local clean_name="${preset_input%.json}"
  local user_preset="${XDG_CONFIG_HOME:-$HOME/.config}/muxrc/presets/${clean_name}.json"
  local repo_preset="${MUXRC_DIR}/tools/presets/${clean_name}.json"

  if [[ -f "$preset_input" ]]; then
    preset_file="$preset_input"
  elif [[ -f "$user_preset" ]]; then
    preset_file="$user_preset"
  elif [[ -f "$repo_preset" ]]; then
    preset_file="$repo_preset"
  fi

  if [[ -z "$preset_file" || ! -f "$preset_file" ]]; then
    log_error "preset '$preset_input' not found in presets or local path"
    return 1
  fi

  if [[ ! -e "$image_file" ]]; then
    log_error "target '$image_file' not found"
    return 1
  fi

  if ! command -v jq > /dev/null 2>&1; then
    log_error "jq not installed. run: pkg install jq"
    return 1
  fi

  bash "${MUXRC_DIR}/tools/sh/exif-spoofer.sh" "$preset_file" "$image_file"
}

########################
# Binary Media Encrypter
########################
media-crypt() {
  if [[ $# -eq 0 ]]; then
    log_error "usage: media-crypt <target_file>"
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

  MUXRC_CRYPT_PASS="$pass1" bash "${MUXRC_DIR}/tools/sh/encrypter.sh" "$target_file"
}

########################
# Binary Media Decrypter
########################
media-decrypt() {
  if [[ $# -eq 0 ]]; then
    log_error "usage: media-decrypt <encrypted_file> [output_file]"
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

  MUXRC_CRYPT_PASS="$pass" bash "${MUXRC_DIR}/tools/sh/encrypter.sh" --decrypt "$target_file" "$output_file"
}

##########################
# Permanent Media Shredder
##########################
shred-file() {
  if [[ $# -eq 0 ]]; then
    log_error "usage: shred-file <file_path>"
    return 1
  fi

  local target_file="$1"

  if [[ ! -f "$target_file" ]]; then
    log_error "file '$target_file' not found"
    return 1
  fi

  if ! command -v shred > /dev/null 2>&1; then
    log_error "coreutils not installed. run: pkg install coreutils"
    return 1
  fi

  bash "${MUXRC_DIR}/tools/sh/shredder.sh" "$target_file"
}

##########################
# HEVC Video Re-compressor
##########################
video-compress() {
  if [[ $# -eq 0 ]]; then
    log_error "usage: video-compress <video_file>"
    return 1
  fi

  local target_file="$1"

  if [[ ! -f "$target_file" ]]; then
    log_error "file '$target_file' not found"
    return 1
  fi

  bash "${MUXRC_DIR}/tools/sh/video-compress.sh" "$target_file"
}

###########################
# Local Network ARP Sweeper
###########################
net-sweep() {
  if ! command -v nmap > /dev/null 2>&1; then
    log_error "nmap not installed. run: pkg install nmap"
    return 1
  fi

  local cidr
  cidr=$(ip route show 2> /dev/null | grep -v 'default' | grep -vE 'dev (lo|tun|tap|wg)' | awk '{print $1}' | head -n 1)

  if [[ -z "$cidr" ]] && command -v termux-wifi-connectioninfo > /dev/null 2>&1; then
    local wifi_ip
    wifi_ip=$(termux-wifi-connectioninfo 2> /dev/null | jq -r '.ip // empty' 2> /dev/null)
    if [[ -n "$wifi_ip" && "$wifi_ip" != "null" ]]; then
      cidr="${wifi_ip%.*}.0/24"
      log_info "detected wifi subnet: $cidr"
    fi
  fi

  if [[ -z "$cidr" ]] && command -v sudo > /dev/null 2>&1; then
    log_info "auto-detecting subnet requires root..."
    cidr=$(sudo ip route show 2> /dev/null | grep -v 'default' | grep -vE 'dev (lo|tun|tap|wg)' | awk '{print $1}' | head -n 1)
  fi

  if [[ -z "$cidr" ]]; then
    log_warn "could not auto-detect valid local subnet."
    log_prompt "enter subnet manually (e.g. 192.168.1.0/24): "
    read -r cidr
  fi

  if [[ -z "$cidr" ]]; then
    log_error "subnet cannot be empty."
    return 1
  fi

  log_info "executing arp sweep on $cidr..."
  if command -v sudo > /dev/null 2>&1; then
    sudo bash "${MUXRC_DIR}/tools/sh/arp-sweeper.sh" "$cidr"
  else
    bash "${MUXRC_DIR}/tools/sh/arp-sweeper.sh" "$cidr"
  fi
}

###################
# Tor Privacy Setup
###################
tor-start() {
  bash "${MUXRC_DIR}/tools/sh/tor-setup.sh" start
}

tor-stop() {
  bash "${MUXRC_DIR}/tools/sh/tor-setup.sh" stop
}

tor-run() {
  if [[ $# -eq 0 ]]; then
    log_error "usage: tor-run <command> [args...]"
    return 1
  fi

  bash "${MUXRC_DIR}/tools/sh/tor-setup.sh" run "$@"
}

tor-check() {
  bash "${MUXRC_DIR}/tools/sh/tor-setup.sh" check
}

###############
# Clean History
###############
clean-history() {
  log_info "cleaning history..."

  local hfile="${HISTFILE:-${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history}"
  rm -f "$hfile" "${hfile}.LOCK" "$HOME/.zsh_history" "$HOME/.zsh_history.LOCK" "$HOME/.zsh_history_root" "$HOME/.zsh_history_root.LOCK" 2> /dev/null

  log_success "history cleaned. reloading shell..."
  exec zsh
}

################
# Meta Date Sync
################
date-sync() {
  if [[ $# -eq 0 ]]; then
    log_error "usage: date-sync <file_or_directory>"
    return 1
  fi

  local target="$1"

  if [[ ! -e "$target" ]]; then
    log_error "target '$target' not found"
    return 1
  fi

  bash "${MUXRC_DIR}/tools/sh/date-sync.sh" "$target"
}

######################
# Wi-Fi MAC Spoof Tool
######################
mac-spoof() {
  local action="${1:-show}"

  if [[ "$action" != "show" && "$action" != "-h" && "$action" != "--help" && "$action" != "help" ]]; then
    if [[ "$EUID" -ne 0 ]] && ! whence -p sudo > /dev/null 2>&1 && ! whence -p su > /dev/null 2>&1 && [[ ! -x /system/bin/su ]]; then
      log_error "root access is required to modify mac address"
      return 1
    fi
  fi

  if [[ "$EUID" -ne 0 && "$action" != "show" && "$action" != "-h" && "$action" != "--help" && "$action" != "help" ]] && command -v sudo > /dev/null 2>&1; then
    sudo bash "${MUXRC_DIR}/tools/sh/mac-spoof.sh" "$@"
  else
    bash "${MUXRC_DIR}/tools/sh/mac-spoof.sh" "$@"
  fi
}

#######################
# Network Identity Tool
#######################
net-identity() {
  local action="${1:-show}"

  if [[ "$action" != "show" && "$action" != "status" && "$action" != "-h" && "$action" != "--help" && "$action" != "help" ]]; then
    if [[ "$EUID" -ne 0 ]] && ! whence -p sudo > /dev/null 2>&1 && ! whence -p su > /dev/null 2>&1 && [[ ! -x /system/bin/su ]]; then
      log_error "root access is required to modify network identity"
      return 1
    fi
  fi

  if [[ "$EUID" -ne 0 && "$action" != "show" && "$action" != "status" && "$action" != "-h" && "$action" != "--help" && "$action" != "help" ]] && command -v sudo > /dev/null 2>&1; then
    sudo bash "${MUXRC_DIR}/tools/sh/net-identity.sh" "$@"
  else
    bash "${MUXRC_DIR}/tools/sh/net-identity.sh" "$@"
  fi
}

#########################
# Network Killswitch Tool
#########################
net-killswitch() {
  local action="${1:-status}"

  if [[ "$action" != "status" && "$action" != "-h" && "$action" != "--help" && "$action" != "help" ]]; then
    if [[ "$EUID" -ne 0 ]] && ! whence -p sudo > /dev/null 2>&1 && ! whence -p su > /dev/null 2>&1 && [[ ! -x /system/bin/su ]]; then
      log_error "root access is required to modify firewall killswitch"
      return 1
    fi
  fi

  if [[ "$EUID" -ne 0 && "$action" != "status" && "$action" != "-h" && "$action" != "--help" && "$action" != "help" ]] && command -v sudo > /dev/null 2>&1; then
    sudo bash "${MUXRC_DIR}/tools/sh/net-killswitch.sh" "$@"
  else
    bash "${MUXRC_DIR}/tools/sh/net-killswitch.sh" "$@"
  fi
}
