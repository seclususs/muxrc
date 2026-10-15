#!/data/data/com.termux/files/usr/bin/bash

######################
# XDG Legacy Migration
######################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

migrate_sudo_hash() {
  local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/muxrc"
  local target_file="${config_dir}/sudo_hash"
  local legacy_file="${HOME}/.sudo_hash"

  if [[ -f "${legacy_file}" ]]; then
    mkdir -p "${config_dir}"
    if [[ ! -f "${target_file}" ]]; then
      mv "${legacy_file}" "${target_file}"
    else
      rm -f "${legacy_file}" 2> /dev/null || true
    fi
    chmod 600 "${target_file}" 2> /dev/null || true
    log_success "migrated sudo_hash to ~/.config/muxrc/sudo_hash"
  fi
}

migrate_ai_env() {
  local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/muxrc"
  local target_file="${config_dir}/ai.env"
  local legacy_file="${HOME}/.gemini_ai_env"

  if [[ -f "${legacy_file}" ]]; then
    mkdir -p "${config_dir}"
    if [[ ! -f "${target_file}" ]]; then
      mv "${legacy_file}" "${target_file}"
    else
      rm -f "${legacy_file}" 2> /dev/null || true
    fi
    chmod 600 "${target_file}" 2> /dev/null || true
    log_success "migrated gemini config to ~/.config/muxrc/ai.env"
  fi
}

migrate_zsh_plugins() {
  local data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}"
  local target_dir="${data_dir}/zsh/plugins"
  local legacy_dir="${HOME}/.zsh/plugins"

  if [[ -d "${legacy_dir}" ]]; then
    mkdir -p "${data_dir}/zsh"
    if [[ ! -d "${target_dir}" ]]; then
      mv "${legacy_dir}" "${target_dir}"
    else
      local item
      for item in "${legacy_dir}"/*; do
        if [[ -e "${item}" ]]; then
          local bname
          bname="$(basename "${item}")"
          if [[ ! -e "${target_dir}/${bname}" ]]; then
            mv "${item}" "${target_dir}/"
          fi
        fi
      done
      rm -rf "${legacy_dir}" 2> /dev/null || true
    fi
    log_success "migrated zsh plugins to ~/.local/share/zsh/plugins"
    rmdir "${HOME}/.zsh" 2> /dev/null || true
  fi
}

migrate_zsh_history() {
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/zsh"

  if [[ -f "${HOME}/.zsh_history" ]]; then
    mkdir -p "${state_dir}"
    if [[ ! -f "${state_dir}/history" ]]; then
      mv "${HOME}/.zsh_history" "${state_dir}/history"
    else
      rm -f "${HOME}/.zsh_history" 2> /dev/null || true
    fi
    log_success "migrated zsh history to ~/.local/state/zsh/history"
  fi

  if [[ -f "${HOME}/.zsh_history_root" ]]; then
    mkdir -p "${state_dir}"
    if [[ ! -f "${state_dir}/history_root" ]]; then
      mv "${HOME}/.zsh_history_root" "${state_dir}/history_root"
    else
      rm -f "${HOME}/.zsh_history_root" 2> /dev/null || true
    fi
    log_success "migrated zsh root history to ~/.local/state/zsh/history_root"
  fi
}

migrate_trash() {
  local data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}"
  local target_dir="${data_dir}/Trash"
  local legacy_dir="${HOME}/.trash"

  if [[ -d "${legacy_dir}" ]]; then
    mkdir -p "${data_dir}"
    if [[ ! -d "${target_dir}" ]]; then
      mv "${legacy_dir}" "${target_dir}"
    else
      local item
      for item in "${legacy_dir}"/*; do
        [[ -e "${item}" ]] && mv -n "${item}" "${target_dir}/" 2> /dev/null || true
      done
      rm -rf "${legacy_dir}" 2> /dev/null || true
    fi
    log_success "migrated trash to ~/.local/share/Trash"
  fi
}

migrate_vault() {
  local data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/muxrc"
  local target_dir="${data_dir}/vault"
  local legacy_dir="${HOME}/.vault"

  if [[ -d "${legacy_dir}" ]]; then
    mkdir -p "${data_dir}"
    if [[ ! -d "${target_dir}" ]]; then
      mv "${legacy_dir}" "${target_dir}"
    else
      local item
      for item in "${legacy_dir}"/*; do
        if [[ -e "${item}" ]]; then
          local bname
          bname="$(basename "${item}")"
          if [[ ! -e "${target_dir}/${bname}" ]]; then
            mv "${item}" "${target_dir}/"
          fi
        fi
      done
      rm -rf "${legacy_dir}" 2> /dev/null || true
    fi
    log_success "migrated vault to ~/.local/share/muxrc/vault"
  fi
}

cleanup_legacy_dirs() {
  if [[ -d "${HOME}/.muxrc" ]]; then
    rmdir "${HOME}/.muxrc/run" 2> /dev/null || true
    rmdir "${HOME}/.muxrc" 2> /dev/null || true
  fi
}

main() {
  migrate_sudo_hash
  migrate_ai_env
  migrate_zsh_plugins
  migrate_zsh_history
  migrate_trash
  migrate_vault
  cleanup_legacy_dirs
}

main "$@"
