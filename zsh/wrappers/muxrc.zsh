########################
# Muxrc command & helper
########################

typeset -g MUXRC_DIR="${MUXRC_DIR:-${ZSH_CONFIG_DIR:+${ZSH_CONFIG_DIR:h}}}"
typeset -g MUXRC_DIR="${MUXRC_DIR:-$HOME/muxrc}"
source "${MUXRC_DIR}/lib/init.sh"

############
# Muxrc Sync
############
_muxrc_sync() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "usage: muxrc sync"
    echo "pull repository updates, run migrations, and sync plugins."
    return 0
  fi

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

  if [[ -f "$muxrc_dir/lib/migrate.sh" ]]; then
    log_info "checking migrations..."
    bash "$muxrc_dir/lib/migrate.sh"
  fi

  if [[ -f "$muxrc_dir/lib/sync.sh" ]]; then
    log_info "syncing zsh plugins..."
    bash "$muxrc_dir/lib/sync.sh" "$plugins_dir"
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

#############
# Muxrc Clean
#############
_muxrc_clean() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "usage: muxrc clean"
    echo "clear active and backup shell history files."
    return 0
  fi

  log_info "cleaning shell history..."

  local hfile="${HISTFILE:-${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history}"
  rm -f "$hfile" "${hfile}.LOCK" "$HOME/.zsh_history" "$HOME/.zsh_history.LOCK" "$HOME/.zsh_history_root" "$HOME/.zsh_history_root.LOCK" 2> /dev/null

  log_success "history cleaned. reloading shell..."
  exec zsh
}

############
# Muxrc Help
############
_muxrc_help() {
  cat << 'EOF'
muxrc: termux environment manager

usage: muxrc <command> [args]

commands:
  sync                    update dotfiles & plugins
  clean                   clear shell history

tools:
  net <command>           network opsec & tor (-h)
  media <command>         media processing & exif (-h)
  sec <command>           data security & privacy (-h)

ai:
  cmd-fix [hint]          diagnose error & fix (??)
  ai-toggle               toggle gemini assistant
  ai-model [name]         view or switch model
  ai-key [-c]             set or verify api key

run 'muxrc <command> -h' or '<prefix> -h' for details
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
    clean)
      shift
      _muxrc_clean "$@"
      ;;
    -h | --help)
      _muxrc_help
      ;;
    "")
      _muxrc_help
      ;;
    *)
      log_error "unknown command: $subcmd (see: muxrc -h)"
      return 1
      ;;
  esac
}
