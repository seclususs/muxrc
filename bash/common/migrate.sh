#!/data/data/com.termux/files/usr/bin/bash

######################
# XDG Legacy Migration
######################
set -euo pipefail

source "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")/../../sh/init.sh"

migrate_shadow() {
  local prefix_dir="${PREFIX:-/data/data/com.termux/files/usr}"
  local target_file="${prefix_dir}/etc/shadow"
  local legacy_config="${XDG_CONFIG_HOME:-${HOME}/.config}/muxrc/sudo_hash"
  local legacy_home="${HOME}/.sudo_hash"

  local legacy_file=""
  if [[ -f "${legacy_config}" ]]; then
    legacy_file="${legacy_config}"
  elif [[ -f "${legacy_home}" ]]; then
    legacy_file="${legacy_home}"
  fi

  if [[ -n "${legacy_file}" ]]; then
    mkdir -p "${prefix_dir}/etc"
    if [[ ! -f "${target_file}" ]]; then
      local raw_hash
      raw_hash=$(head -n 1 "${legacy_file}" 2> /dev/null | tr -d '[:space:]')
      if [[ -n "${raw_hash}" ]]; then
        local current_user="${USER:-$(whoami 2> /dev/null || id -un 2> /dev/null || echo "termux")}"
        local days_since_epoch=$(($(date +%s 2> /dev/null || echo 0) / 86400))
        local tmp_file
        tmp_file=$(mktemp "${prefix_dir}/etc/shadow.XXXXXX" 2> /dev/null || mktemp "${TMPDIR:-/tmp}/shadow.XXXXXX")
        printf '%s:%s:%s:0:99999:7:::\n' "${current_user}" "${raw_hash}" "${days_since_epoch}" > "${tmp_file}"
        chmod 600 "${tmp_file}"
        mv -f "${tmp_file}" "${target_file}"
        log_success "migrated sudo_hash to ${target_file}"
      fi
    fi
    rm -f "${legacy_config}" "${legacy_home}" 2> /dev/null || true
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
    log_success "migrated zsh plugins"
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
    log_success "migrated zsh history"
  fi

  if [[ -f "${HOME}/.zsh_history_root" ]]; then
    mkdir -p "${state_dir}"
    if [[ ! -f "${state_dir}/history_root" ]]; then
      mv "${HOME}/.zsh_history_root" "${state_dir}/history_root"
    else
      rm -f "${HOME}/.zsh_history_root" 2> /dev/null || true
    fi
    log_success "migrated zsh root history"
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
      shopt -s dotglob nullglob
      local item
      for item in "${legacy_dir}"/*; do
        [[ -e "${item}" ]] && mv -n "${item}" "${target_dir}/" 2> /dev/null || true
      done
      shopt -u dotglob nullglob
      rmdir "${legacy_dir}" 2> /dev/null || true
    fi
    log_success "migrated trash to xdg"
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
      shopt -s dotglob nullglob
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
      shopt -u dotglob nullglob
      rmdir "${legacy_dir}" 2> /dev/null || true
    fi
    log_success "migrated vault to xdg"
  fi
}

cleanup_legacy_dirs() {
  local cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}"
  local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/muxrc"
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}/muxrc"

  rm -f "${cache_dir}/gemini_cooldown" "${cache_dir}/muxrc/gemini_cooldown" 2> /dev/null || true
  rm -f "${cache_dir}/muxrc/last_model" 2> /dev/null || true
  rm -f "${config_dir}/ai.env" "${HOME}/.gemini_ai_env" 2> /dev/null || true
  rm -f "${state_dir}/ai-audit.log" 2> /dev/null || true

  local legacy_clip="${cache_dir}/clip_history.log"
  local new_clip="${cache_dir}/muxrc/clip_history.log"
  if [[ -f "${legacy_clip}" ]]; then
    mkdir -p "${cache_dir}/muxrc"
    if [[ ! -f "${new_clip}" ]]; then
      mv "${legacy_clip}" "${new_clip}"
    else
      rm -f "${legacy_clip}" 2> /dev/null || true
    fi
  fi

  if [[ -f "${cache_dir}/sudo_ts" ]]; then
    rm -f "${cache_dir}/sudo_ts" 2> /dev/null || true
  fi

  local pfile
  for pfile in "${cache_dir}"/ai_phase_*; do
    [[ -f "${pfile}" ]] && rm -f "${pfile}" 2> /dev/null || true
  done

  rm -f "${HOME}/.zsh_history.LOCK" "${HOME}/.zsh_history_root.LOCK" 2> /dev/null || true

  if [[ -d "${HOME}/.muxrc" ]]; then
    rm -rf "${HOME}/.muxrc" 2> /dev/null || true
  fi

  [[ -d "${HOME}/.zsh" ]] && rmdir "${HOME}/.zsh" 2> /dev/null || true
  [[ -d "${HOME}/.trash" ]] && rmdir "${HOME}/.trash" 2> /dev/null || true
  [[ -d "${HOME}/.vault" ]] && rmdir "${HOME}/.vault" 2> /dev/null || true
  [[ -L "${HOME}/.tmux.conf" || -f "${HOME}/.tmux.conf" ]] && rm -f "${HOME}/.tmux.conf" 2> /dev/null || true
  [[ -d "${HOME}/.sessions" ]] && rmdir "${HOME}/.sessions" 2> /dev/null || true
}

migrate_magisk_boot() {
  local magisk_service_dir="/data/adb/service.d"
  local magisk_runner="${magisk_service_dir}/muxrc-boot.sh"
  local repo_dir
  repo_dir="$(dirname "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")")")"
  local source_runner="${repo_dir}/sh/boot/magisk-boot.sh"

  if [[ -f "${source_runner}" ]] && command -v su > /dev/null 2>&1 && su -c true 2> /dev/null; then
    if su -c "[ -d '${magisk_service_dir}' ]" 2> /dev/null; then
      if su -c "[ -f '${magisk_runner}' ]" 2> /dev/null; then
        su -c "cp '${source_runner}' '${magisk_runner}'" 2> /dev/null || true
        su -c "chmod 755 '${magisk_runner}'" 2> /dev/null || true
      fi
    fi
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "usage: migrate.sh [-h|--help]"
    echo "run legacy xdg path migrations for muxrc."
    exit 0
  fi

  migrate_shadow
  migrate_zsh_plugins
  migrate_zsh_history
  migrate_trash
  migrate_vault
  migrate_magisk_boot
  cleanup_legacy_dirs
}

main "$@"
