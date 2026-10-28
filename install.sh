#!/data/data/com.termux/files/usr/bin/bash

##################
# Termux Installer
##################
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "${SCRIPT_DIR}/lib/init.sh"

setup_storage() {
  if [[ ! -d "${HOME}/storage" ]]; then
    log_info "requesting storage permission..."
    termux-setup-storage
    sleep 2
  fi
}

enable_repos() {
  local sources_dir="${PREFIX:-/data/data/com.termux/files/usr}/etc/apt/sources.list.d"
  if [[ -f "${sources_dir}/root.list" && -f "${sources_dir}/x11.list" ]]; then
    log_info "extra repos already enabled, skipping."
    return 0
  fi

  start_spinner "enabling extra repos"
  export DEBIAN_FRONTEND=noninteractive
  pkg update -y -o Dpkg::Options::="--force-confold" > /dev/null 2>&1 || true
  pkg install -y -o Dpkg::Options::="--force-confold" root-repo x11-repo > /dev/null 2>&1 || true
  pkg upgrade -y -o Dpkg::Options::="--force-confold" > /dev/null 2>&1 || true
  stop_spinner "success" "repos enabled."
}

install_packages() {
  local -a pkgs=(
    zsh git wget curl ncurses-utils bc coreutils findutils grep sed gawk jq
    termux-exec termux-api termux-services nano fzf openssh unzip tar p7zip
    unrar exiftool steghide openssl-tool nmap tor proxychains-ng ffmpeg
    sudo
  )
  local -a missing_pkgs=()
  local pkg

  for pkg in "${pkgs[@]}"; do
    if ! dpkg -s "${pkg}" > /dev/null 2>&1; then
      missing_pkgs+=("${pkg}")
    fi
  done

  if [[ ${#missing_pkgs[@]} -eq 0 ]]; then
    log_info "all packages already installed, skipping."
    return 0
  fi

  start_spinner "installing missing packages"
  pkg install -y -o Dpkg::Options::="--force-confold" "${missing_pkgs[@]}" > /dev/null 2>&1 || true
  stop_spinner "success" "packages installed."
}

setup_directories() {
  local dotfiles_dir="${1:-}"
  local zsh_plugins_dir="${2:-}"

  if [[ -z "${dotfiles_dir}" || -z "${zsh_plugins_dir}" ]]; then
    log_error "missing directory parameters."
    return 1
  fi

  mkdir -p "${HOME}/.config/muxrc/presets"
  mkdir -p "${HOME}/.config/sudo"
  mkdir -p "${HOME}/.cache/muxrc/run"
  mkdir -p "${HOME}/.local/share/muxrc/vault"
  mkdir -p "${HOME}/.local/share/Trash"
  mkdir -p "${zsh_plugins_dir}"
  mkdir -p "${HOME}/.local/state/zsh"
  mkdir -p "${HOME}/.termux/boot"
  mkdir -p "${HOME}/muxrc-out/stripped"
  mkdir -p "${HOME}/muxrc-out/decoys"
  mkdir -p "${HOME}/muxrc-out/extracted"

  if [[ -f "${dotfiles_dir}/tools/presets/iphone-nyc.json" && ! -f "${HOME}/.config/muxrc/presets/iphone-nyc.json" ]]; then
    cp "${dotfiles_dir}/tools/presets/iphone-nyc.json" "${HOME}/.config/muxrc/presets/iphone-nyc.json"
  fi

  log_info "muting termux motd..."
  touch "${HOME}/.hushlogin"
}

setup_sudo_wrapper() {
  local reset_sudo="y"
  local sudo_pass=""
  local sudo_pass_confirm=""
  local sudo_hash_dir="${HOME}/.config/muxrc"
  local sudo_hash_file="${sudo_hash_dir}/sudo_hash"

  mkdir -p "${sudo_hash_dir}"

  log_info "setting up sudo wrapper..."
  if [[ -f "${sudo_hash_file}" || -f "${HOME}/.sudo_hash" ]]; then
    log_prompt "sudo pass configured. overwrite? [y/N]: "
    read -r reset_sudo
  fi

  if [[ "${reset_sudo:-}" =~ ^[Yy]$ ]]; then
    log_prompt "create your sudo password: "
    read -r -s sudo_pass
    echo ""
    log_prompt "confirm sudo password: "
    read -r -s sudo_pass_confirm
    echo ""

    if [[ "${sudo_pass}" == "${sudo_pass_confirm}" ]]; then
      echo -n "${sudo_pass}" | sha256sum | awk '{print $1}' > "${sudo_hash_file}"
      chmod 600 "${sudo_hash_file}"
      log_success "sudo hash generated."
    else
      log_error "passwords mismatch. please retry."
    fi
  else
    log_warn "keeping existing sudo password."
  fi
}

setup_sudo_config() {
  local config_dir="${HOME}/.config/sudo"
  local config_file="${config_dir}/sudo.config"

  log_info "configuring sudo environment..."
  mkdir -p "${config_dir}"
  if [[ ! -f "${config_file}" ]]; then
    cat << 'EOF' > "${config_file}"
SUDO__SHELL_HOME="$SUDO__TERMUX_HOME"
SUDO__SHELLS_AUTOMATICALLY_CREATE_RC_FILES=0
SUDO__SHELLS_AUTOMATICALLY_CREATE_HISTORY_FILES=0
SUDO__SHELLS_HISTORY_ENABLED=0
EOF
    chmod 600 "${config_file}"
    log_success "sudo environment configured."
  else
    log_warn "keeping existing sudo.config."
  fi
}

setup_zsh_plugins() {
  local zsh_plugins_dir="${1:-}"

  if [[ -z "${zsh_plugins_dir}" ]]; then
    log_error "plugins directory not specified."
    return 1
  fi

  log_info "fetching zsh plugins..."
  bash "${SCRIPT_DIR}/lib/sync.sh" "${zsh_plugins_dir}"
}

setup_storage_symlinks() {
  local dir_name
  local target_path

  log_info "creating storage symlinks..."
  local -A storage_dirs=(
    ["Workspace"]="/storage/emulated/0/Workspace"
  )

  for dir_name in "${!storage_dirs[@]}"; do
    target_path="${storage_dirs[${dir_name}]}"
    if [[ ! -d "${target_path}" ]]; then
      if mkdir -p "${target_path}" 2> /dev/null; then
        log_success "created ${target_path}"
      else
        log_warn "could not create ${target_path} (check storage permissions)."
      fi
    else
      log_warn "${target_path} already exists, skipping."
    fi
    ln -sfn "${target_path}" "${HOME}/${dir_name}"
  done
}

symlink_configurations() {
  local dotfiles_dir="${1:-}"

  if [[ -z "${dotfiles_dir}" ]]; then
    log_error "dotfiles directory not specified."
    return 1
  fi

  log_info "symlinking configurations..."
  ln -sf "${dotfiles_dir}/zsh/.zshrc" "${HOME}/.zshrc"
  ln -sf "${dotfiles_dir}/colors/.dircolors" "${HOME}/.dircolors"
  ln -sf "${dotfiles_dir}/termux/colors.properties" "${HOME}/.termux/colors.properties"
  ln -sf "${dotfiles_dir}/termux/termux.properties" "${HOME}/.termux/termux.properties"
  ln -sf "${dotfiles_dir}/nano/.nanorc" "${HOME}/.nanorc"

  ln -sf "${dotfiles_dir}/boot/start-sshd" "${HOME}/.termux/boot/start-sshd"
  chmod +x "${dotfiles_dir}/boot/start-sshd"
}

setup_nerd_font() {
  if [[ ! -f "${HOME}/.termux/font.ttf" ]]; then
    log_info "installing jetbrains mono font..."
    if ! wget -q --show-progress -O "${HOME}/.termux/font.ttf" \
      "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.4.0/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFont-Regular.ttf"; then
      log_warn "font download failed, skipping."
      rm -f "${HOME}/.termux/font.ttf" 2> /dev/null || true
    fi
  else
    log_warn "font already installed, skipping."
  fi

  termux-reload-settings 2> /dev/null || true
}

setup_default_shell() {
  if [[ "${SHELL:-}" != */zsh ]]; then
    log_info "changing default shell..."
    chsh -s zsh
  fi
}

setup_gemini_env() {
  local dotfiles_dir="${1:-}"
  local reset_gemini="y"
  local enable_ai=""
  local gemini_key=""
  local ai_config_dir="${HOME}/.config/muxrc"
  local ai_env_file="${ai_config_dir}/ai.env"

  if [[ -z "${dotfiles_dir}" ]]; then
    log_error "dotfiles directory not specified."
    return 1
  fi

  mkdir -p "${ai_config_dir}"

  log_info "setting up gemini ai assistant..."
  if [[ -f "${ai_env_file}" || -f "${HOME}/.gemini_ai_env" ]]; then
    log_prompt "gemini config exists. overwrite? [y/N]: "
    read -r reset_gemini
  fi

  if [[ "${reset_gemini:-}" =~ ^[Yy]$ ]]; then
    log_prompt "setup gemini ai assistant? [y/N]: "
    read -r enable_ai
    if [[ "${enable_ai:-}" =~ ^[Yy]$ ]]; then
      log_prompt "gemini api key: "
      read -r -s gemini_key
      echo
      {
        printf 'GEMINI_API_KEY=%q\n' "${gemini_key}"
        echo "GEMINI_MODEL=\"gemini-3.5-flash-lite\""
        echo "AI_ENABLED=1"
        echo "AI_AUTOCORRECT_ENABLED=1"
      } > "${ai_env_file}"
      chmod 600 "${ai_env_file}"
      log_success "gemini config saved."
    fi
  else
    log_warn "keeping existing gemini config."
  fi
}

main() {
  local dotfiles_dir="${SCRIPT_DIR}"
  local zsh_plugins_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/zsh/plugins"

  trap 'cleanup_spinner' EXIT

  setup_storage
  enable_repos
  install_packages

  if [[ -f "${SCRIPT_DIR}/lib/migrate.sh" ]]; then
    bash "${SCRIPT_DIR}/lib/migrate.sh"
  fi

  setup_directories "${dotfiles_dir}" "${zsh_plugins_dir}"
  setup_sudo_wrapper
  setup_sudo_config
  setup_zsh_plugins "${zsh_plugins_dir}"
  setup_storage_symlinks
  symlink_configurations "${dotfiles_dir}"
  setup_nerd_font
  setup_default_shell
  setup_gemini_env "${dotfiles_dir}"

  log_success "installation complete! please restart termux."
  trap - EXIT
}

main "$@"
