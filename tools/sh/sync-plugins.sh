#!/data/data/com.termux/files/usr/bin/bash

###################
# Zsh Plugin Syncer
###################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

check_dependencies() {
  require_cmd git
}

sync_plugins() {
  local plugins_dir="${1:-${HOME}/.zsh/plugins}"

  mkdir -p "${plugins_dir}"

  local -A official_plugins=(
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
    ["zsh-completions"]="https://github.com/zsh-users/zsh-completions.git"
    ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search.git"
    ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab.git"
    ["zsh-autopair"]="https://github.com/hlissner/zsh-autopair.git"
  )

  local -a official_keys=()
  local key
  for key in "${!official_plugins[@]}"; do
    official_keys+=("${key}")
  done

  local -a custom_plugins=()
  local item
  for item in "${plugins_dir}"/*; do
    if [[ -d "${item}/.git" ]]; then
      local base_name
      base_name="$(basename "${item}")"
      if [[ -z "${official_plugins[${base_name}]:-}" ]]; then
        custom_plugins+=("${base_name}")
      fi
    fi
  done

  local total=$((${#official_keys[@]} + ${#custom_plugins[@]}))
  local idx=0
  local plugin_name
  local plugin_url
  local target_dir

  trap 'cleanup_spinner' EXIT

  for plugin_name in "${official_keys[@]}"; do
    idx=$((idx + 1))
    plugin_url="${official_plugins[${plugin_name}]}"
    target_dir="${plugins_dir}/${plugin_name}"

    if [[ ! -d "${target_dir}" ]]; then
      start_spinner "cloning ${plugin_name} (${idx}/${total})"
      if git clone -q --depth 1 "${plugin_url}" "${target_dir}"; then
        stop_spinner "success" "cloned ${plugin_name}"
      else
        stop_spinner "error" "failed to clone ${plugin_name}"
      fi
    else
      start_spinner "updating ${plugin_name} (${idx}/${total})"
      if git -C "${target_dir}" pull -q --rebase; then
        stop_spinner "success" "updated ${plugin_name}"
      else
        stop_spinner "error" "failed to update ${plugin_name}"
      fi
    fi
  done

  for plugin_name in "${custom_plugins[@]}"; do
    idx=$((idx + 1))
    target_dir="${plugins_dir}/${plugin_name}"
    start_spinner "updating ${plugin_name} (${idx}/${total})"
    if git -C "${target_dir}" pull -q --rebase; then
      stop_spinner "success" "updated ${plugin_name}"
    else
      stop_spinner "error" "failed to update ${plugin_name}"
    fi
  done

  trap - EXIT
}

main() {
  check_dependencies || exit 1
  sync_plugins "$@"
}

main "$@"
