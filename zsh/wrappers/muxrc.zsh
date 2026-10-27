########################
# Muxrc command & helper
########################

typeset -g MUXRC_DIR="${MUXRC_DIR:-$HOME/muxrc}"
source "${MUXRC_DIR}/lib/init.sh"

############
# Muxrc Sync
############
_muxrc_sync() {
  log_info "syncing muxrc..."

  local muxrc_dir="${MUXRC_DIR}"
  local install_script="${muxrc_dir}/install.sh"
  local plugins_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
  [[ ! -d "$plugins_dir" && -d "$HOME/.zsh/plugins" ]] && plugins_dir="$HOME/.zsh/plugins"
  local old_hash=""
  local new_hash=""

  if [[ ! -d "$muxrc_dir" ]]; then
    log_error "muxrc dir not found."
    return 1
  fi

  if [[ -f "$install_script" ]]; then
    old_hash=$(sha256sum "$install_script" 2> /dev/null | awk '{print $1}')
  fi

  start_spinner "pulling repository"
  if git -C "$muxrc_dir" pull -q; then
    stop_spinner "success" "repository updated."
  else
    stop_spinner "error" "failed to pull repository."
    return 1
  fi

  if [[ -f "$muxrc_dir/tools/sh/muxrc/migrate.sh" ]]; then
    log_info "checking migrations..."
    bash "$muxrc_dir/tools/sh/muxrc/migrate.sh"
  fi

  if [[ -f "$muxrc_dir/tools/sh/muxrc/sync-plugins.sh" ]]; then
    log_info "syncing zsh plugins..."
    bash "$muxrc_dir/tools/sh/muxrc/sync-plugins.sh" "$plugins_dir"
  fi

  if [[ -f "$install_script" ]]; then
    new_hash=$(sha256sum "$install_script" 2> /dev/null | awk '{print $1}')
    if [[ "$old_hash" != "$new_hash" ]]; then
      log_info "install.sh updated. executing..."
      bash "$install_script"
    else
      log_warn "install.sh unchanged. skipping."
    fi
  fi

  log_success "sync complete. reloading shell..."
  exec zsh
}

############
# Muxrc Help
############
_muxrc_help() {
  cat << 'EOF'
muxrc - termux environment & dotfiles manager

usage:
  muxrc <command> [args]

commands:
  sync                            update dotfiles and plugins to latest version
  help                            show this help message

tools:
  clean-dupes <dir>               find and clean duplicate files
  clean-history                   clean zsh history and reload shell
  clean-meta <dir>                remove camera and location metadata from photos
  date-sync <target>              sync photo metadata dates with file timestamps
  media-crypt <file>              encrypt private file
  media-decrypt <file> [output]   decrypt private file
  net-sweep                       discover devices connected to local network
  rename-by-date <dir> <prefix>   organize photos by capture date
  shred-file <file>               permanently destroy sensitive file
  spoof-meta <preset> <file>      replace photo metadata with dummy device info
  stego-vault                     hide or extract secret data in pictures
  tor-check                       verify tor network connectivity and exit ip
  tor-run <cmd> [args...]         run command anonymously through tor
  tor-start                       start anonymous tor proxy session
  tor-stop                        stop anonymous tor proxy session
  video-compress <file>           compress video to hevc preserving metadata

ai:
  cmd-fix [hint]                  diagnose runtime error and suggest fix (alias: ??)
  ai-toggle                       toggle gemini assistant and auto-correct
  ai-model [name|--list|...]      view or switch active gemini model
  ai-key [-c|--check]             set or verify gemini api key securely
EOF
}

###############
# Muxrc Command
###############
muxrc() {
  local subcmd="${1:-}"

  case "$subcmd" in
    sync)
      shift
      _muxrc_sync "$@"
      ;;
    help | -h | --help)
      _muxrc_help
      ;;
    "")
      _muxrc_help
      ;;
    *)
      log_error "unknown command: $subcmd"
      log_info "run 'muxrc help' for usage."
      return 1
      ;;
  esac
}

########################
# Backward Compatibility
########################
muxrc-sync() {
  muxrc sync "$@"
}
