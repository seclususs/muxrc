########################
# Muxrc command & helper
########################

typeset -g MUXRC_DIR="${MUXRC_DIR:-${ZSH_CONFIG_DIR:+${ZSH_CONFIG_DIR:h}}}"
typeset -g MUXRC_DIR="${MUXRC_DIR:-$HOME/muxrc}"
source "${MUXRC_DIR}/sh/init.sh"

############
# Muxrc Sync
############
_muxrc_sync() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "usage: muxrc sync"
    echo "pull repository updates, run migrations, and sync plugins."
    return 0
  fi

  local muxrc_dir="${MUXRC_DIR}"
  local install_script="${muxrc_dir}/install.sh"
  local plugins_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins"
  [[ ! -d "$plugins_dir" && -d "$HOME/.zsh/plugins" ]] && plugins_dir="$HOME/.zsh/plugins"

  if [[ ! -d "$muxrc_dir" ]]; then
    log_error "muxrc dir not found."
    return 1
  fi

  local old_head=""
  local new_head=""
  old_head=$(git -C "$muxrc_dir" rev-parse HEAD 2> /dev/null)

  local pull_err
  pull_err=$(mktemp "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/pull.err.XXXXXX" 2> /dev/null || mktemp)

  start_spinner "pulling repository"
  if git -C "$muxrc_dir" pull --rebase --autostash -q 2> "$pull_err"; then
    new_head=$(git -C "$muxrc_dir" rev-parse HEAD 2> /dev/null)
    if [[ "$old_head" == "$new_head" ]]; then
      stop_spinner "success" "repository up to date."
    else
      stop_spinner "success" "repository updated."
    fi
    rm -f "$pull_err" 2> /dev/null
  else
    stop_spinner "error" "failed to pull repository."
    if [[ -s "$pull_err" ]]; then
      local err_line
      while IFS= read -r err_line; do
        [[ -n "$err_line" ]] && print -u2 "$err_line"
      done < "$pull_err"
    fi
    rm -f "$pull_err" 2> /dev/null
    return 1
  fi

  local plugins_changed=0
  if [[ -f "$muxrc_dir/bash/common/sync.sh" ]]; then
    local sync_out
    sync_out=$(mktemp "${TMPDIR:-/data/data/com.termux/files/usr/tmp}/sync.out.XXXXXX" 2> /dev/null || mktemp)
    bash "$muxrc_dir/bash/common/sync.sh" "$plugins_dir" 2>&1 | tee "$sync_out"
    if grep -q "updated " "$sync_out" 2> /dev/null || grep -q "cloned " "$sync_out" 2> /dev/null; then
      plugins_changed=1
      rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"* 2> /dev/null || true
    fi
    rm -f "$sync_out" 2> /dev/null
  fi

  if [[ "$old_head" == "$new_head" && $plugins_changed -eq 0 ]]; then
    log_success "everything up to date."
    return 0
  fi

  if [[ "$old_head" != "$new_head" ]]; then
    if [[ -f "$muxrc_dir/bash/common/migrate.sh" ]]; then
      start_spinner "checking migrations"
      bash "$muxrc_dir/bash/common/migrate.sh" > /dev/null 2>&1 || true
      stop_spinner "success" "migrations checked."
    fi

    if [[ -f "$install_script" ]]; then
      local old_inst=""
      local new_inst=""
      old_inst=$(git -C "$muxrc_dir" rev-parse "${old_head}:install.sh" 2> /dev/null || true)
      new_inst=$(git -C "$muxrc_dir" rev-parse "${new_head}:install.sh" 2> /dev/null || true)
      if [[ -n "$old_inst" && "$old_inst" != "$new_inst" ]]; then
        MUXRC_SKIP_PLUGIN_SYNC=1 bash "$install_script"
      fi
    fi
  fi

  local zshrc_file="${ZSH_CONFIG_DIR:-${muxrc_dir}/zsh}/.zshrc"
  if [[ -f "$zshrc_file" ]] && ! zsh -n "$zshrc_file" 2> /dev/null; then
    log_error "syntax check failed on .zshrc"
    log_warn "reload aborted for safety"
    return 1
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

run 'muxrc <command> -h' or '<prefix> -h' for details
EOF
}

###############
# Muxrc Command
###############
muxrc() {
  local subcmd="${1:-}"

  case "$subcmd" in
    sync | update)
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
      log_error "unknown command: $subcmd"
      return 1
      ;;
  esac
}
