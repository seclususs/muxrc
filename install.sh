#!/data/data/com.termux/files/usr/bin/bash

##################
# Termux Installer
##################
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
source "${SCRIPT_DIR}/sh/init.sh"

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

  local preset
  local bname
  if [[ -d "${dotfiles_dir}/assets/presets" ]]; then
    for preset in "${dotfiles_dir}/assets/presets"/*.json; do
      if [[ -f "${preset}" ]]; then
        bname="$(basename "${preset}")"
        if [[ ! -f "${HOME}/.config/muxrc/presets/${bname}" ]]; then
          cp "${preset}" "${HOME}/.config/muxrc/presets/${bname}"
        fi
      fi
    done
  fi

  touch "${HOME}/.hushlogin"
}

setup_sudo_wrapper() {
  local sudo_pass=""
  local sudo_pass_confirm=""
  local prefix_dir="${PREFIX:-/data/data/com.termux/files/usr}"
  local shadow_dir="${prefix_dir}/etc"
  local shadow_file="${shadow_dir}/shadow"

  mkdir -p "${shadow_dir}"

  if [[ -f "${shadow_file}" || -f "${HOME}/.config/muxrc/sudo_hash" || -f "${HOME}/.sudo_hash" ]]; then
    return 0
  fi

  log_prompt "create your sudo password: "
  read -r -s sudo_pass
  echo ""
  log_prompt "confirm sudo password: "
  read -r -s sudo_pass_confirm
  echo ""

  if [[ -z "${sudo_pass}" ]]; then
    log_error "password cannot be empty"
    return 1
  elif [[ "${sudo_pass}" == "${sudo_pass_confirm}" ]]; then
    local hash=""
    if command -v openssl > /dev/null 2>&1; then
      hash=$(printf '%s' "${sudo_pass}" | openssl passwd -6 -stdin 2> /dev/null || true)
    fi
    if [[ -z "${hash}" ]]; then
      log_error "password hashing failed"
      return 1
    fi

    local current_user="${USER:-$(whoami 2> /dev/null || id -un 2> /dev/null || echo "termux")}"
    local days_since_epoch=$(($(date +%s 2> /dev/null || echo 0) / 86400))
    local tmp_file
    tmp_file=$(mktemp "${shadow_dir}/shadow.XXXXXX" 2> /dev/null || mktemp "${TMPDIR:-/tmp}/shadow.XXXXXX")
    printf '%s:%s:%s:0:99999:7:::\n' "${current_user}" "${hash}" "${days_since_epoch}" > "${tmp_file}"
    chmod 600 "${tmp_file}"
    mv -f "${tmp_file}" "${shadow_file}"

    local termux_passwd="${prefix_dir}/bin/passwd"
    if [[ -x "${termux_passwd}" ]]; then
      printf '%s\n%s\n' "${sudo_pass}" "${sudo_pass}" | "${termux_passwd}" > /dev/null 2>&1 || true
    fi

    rm -f "${HOME}/.config/muxrc/sudo_hash" "${HOME}/.sudo_hash" 2> /dev/null || true
    log_success "shadow password configured."
  else
    log_error "passwords mismatch. please retry."
    return 1
  fi
}

setup_sudo_config() {
  local config_dir="${HOME}/.config/sudo"
  local config_file="${config_dir}/sudo.config"

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
  fi
}

setup_zsh_plugins() {
  local zsh_plugins_dir="${1:-}"

  if [[ -z "${zsh_plugins_dir}" ]]; then
    log_error "plugins directory not specified."
    return 1
  fi

  if [[ "${MUXRC_SKIP_PLUGIN_SYNC:-0}" == "1" ]]; then
    return 0
  fi

  bash "${SCRIPT_DIR}/bash/common/sync.sh" "${zsh_plugins_dir}"
}

setup_storage_symlinks() {
  local dir_name
  local target_path
  local home_ctx

  local -A storage_dirs=(
    ["Workspace"]="/storage/emulated/0/Workspace"
  )

  home_ctx=$(stat -c %C "${HOME}" 2> /dev/null || true)

  for dir_name in "${!storage_dirs[@]}"; do
    target_path="${storage_dirs[${dir_name}]}"
    if [[ ! -d "${target_path}" ]]; then
      mkdir -p "${target_path}" 2> /dev/null || true
    fi
    ln -sfn "${target_path}" "${HOME}/${dir_name}"
    if [[ -n "${home_ctx}" && "${home_ctx}" != "?" ]]; then
      chcon -h "${home_ctx}" "${HOME}/${dir_name}" 2> /dev/null || true
    fi
  done
}

symlink_configurations() {
  local dotfiles_dir="${1:-}"

  if [[ -z "${dotfiles_dir}" ]]; then
    log_error "dotfiles directory not specified."
    return 1
  fi

  local tmp_check="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
  if [[ "${dotfiles_dir}" == "${tmp_check}"* ]]; then
    return 0
  fi

  if [[ "${dotfiles_dir}" -ef "${HOME}" ]]; then
    return 0
  fi

  ln -sfn "${dotfiles_dir}/zsh/.zshrc" "${HOME}/.zshrc"
  ln -sfn "${dotfiles_dir}/colors/.dircolors" "${HOME}/.dircolors"
  ln -sfn "${dotfiles_dir}/termux/colors.properties" "${HOME}/.termux/colors.properties"
  ln -sfn "${dotfiles_dir}/termux/termux.properties" "${HOME}/.termux/termux.properties"
  ln -sfn "${dotfiles_dir}/nano/.nanorc" "${HOME}/.nanorc"

  local home_ctx
  if home_ctx=$(stat -c %C "${HOME}" 2> /dev/null) && [[ -n "${home_ctx}" && "${home_ctx}" != "?" ]]; then
    chcon -h "${home_ctx}" "${HOME}/.zshrc" "${HOME}/.dircolors" "${HOME}/.termux/colors.properties" "${HOME}/.termux/termux.properties" "${HOME}/.nanorc" 2> /dev/null || true
  fi
}

setup_boot_services() {
  local dotfiles_dir="${1:-}"

  if [[ -z "${dotfiles_dir}" ]]; then
    log_error "dotfiles directory not specified."
    return 1
  fi

  local tmp_check="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
  if [[ "${dotfiles_dir}" == "${tmp_check}"* ]]; then
    return 0
  fi

  mkdir -p "${HOME}/.termux/boot"
  ln -sfn "${dotfiles_dir}/sh/boot/start-sshd" "${HOME}/.termux/boot/start-sshd"
  chmod +x "${dotfiles_dir}/sh/boot/start-sshd" 2> /dev/null || true

  local home_ctx
  if home_ctx=$(stat -c %C "${HOME}" 2> /dev/null) && [[ -n "${home_ctx}" && "${home_ctx}" != "?" ]]; then
    chcon -h "${home_ctx}" "${HOME}/.termux/boot/start-sshd" 2> /dev/null || true
  fi

  local magisk_service_dir="/data/adb/service.d"
  local magisk_runner="${magisk_service_dir}/muxrc-boot.sh"

  if command -v su > /dev/null 2>&1 && su -c true 2> /dev/null; then
    if su -c "[ -d '${magisk_service_dir}' ]" 2> /dev/null; then
      su -c "cp '${dotfiles_dir}/sh/boot/magisk-boot.sh' '${magisk_runner}'" 2> /dev/null \
        && su -c "chmod 755 '${magisk_runner}'" 2> /dev/null || true
    fi
  fi
}

setup_nerd_font() {
  if [[ ! -f "${HOME}/.termux/font.ttf" ]]; then
    log_info "installing jetbrains mono font..."
    if ! wget -q --show-progress -O "${HOME}/.termux/font.ttf" \
      "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.4.0/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFont-Regular.ttf"; then
      log_warn "font download failed, skipping."
      rm -f "${HOME}/.termux/font.ttf" 2> /dev/null || true
    fi
    termux-reload-settings 2> /dev/null || true
  fi
}

setup_default_shell() {
  if [[ "${SHELL:-}" != */zsh ]]; then
    chsh -s zsh
  fi
}

main() {
  local dotfiles_dir="${SCRIPT_DIR}"
  local zsh_plugins_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/zsh/plugins"

  trap 'cleanup_spinner' EXIT

  setup_storage
  enable_repos
  install_packages

  if [[ -f "${SCRIPT_DIR}/bash/common/migrate.sh" ]]; then
    bash "${SCRIPT_DIR}/bash/common/migrate.sh"
  fi

  setup_directories "${dotfiles_dir}" "${zsh_plugins_dir}"
  setup_sudo_wrapper
  setup_sudo_config
  setup_zsh_plugins "${zsh_plugins_dir}"
  setup_storage_symlinks
  symlink_configurations "${dotfiles_dir}"
  setup_boot_services "${dotfiles_dir}"
  setup_nerd_font
  setup_default_shell

  log_success "install done. restart termux"
  trap - EXIT
}

main "$@"
