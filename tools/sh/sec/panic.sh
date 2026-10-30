#!/data/data/com.termux/files/usr/bin/bash

################
# Panic Protocol
################
set -euo pipefail

_panic_dir="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
source "${_panic_dir}/../../../lib/init.sh"
if [[ -f "${_panic_dir}/../../../lib/shredder.sh" ]]; then
  source "${_panic_dir}/../../../lib/shredder.sh"
fi

usage() {
  echo "usage: sec panic [-f|--force] [-n|--dry-run]"
  echo "emergency one-shot secure wipe of credentials, history, and vault."
}

get_targets() {
  local data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}"
  local config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}"
  local state_dir="${XDG_STATE_HOME:-${HOME}/.local/state}"
  local cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}"
  local -a candidates=()

  # Vault and encrypted storage
  candidates+=("${data_dir}/muxrc/vault")
  candidates+=("${HOME}/.vault")

  # Cryptographic keys and identities
  candidates+=("${HOME}/.ssh")
  candidates+=("${HOME}/.gnupg")

  # Auth credentials and tokens
  candidates+=("${HOME}/.git-credentials")
  candidates+=("${HOME}/.netrc")
  candidates+=("${HOME}/.config/gh/hosts.yml")
  candidates+=("${HOME}/.aws/credentials")
  candidates+=("${config_dir}/muxrc/ai.env")
  candidates+=("${HOME}/.gemini_ai_env")
  candidates+=("${config_dir}/muxrc/sudo_hash")
  candidates+=("${HOME}/.sudo_hash")

  # Shell histories and project trash
  candidates+=("${state_dir}/zsh/history")
  candidates+=("${state_dir}/zsh/history_root")
  candidates+=("${HOME}/.zsh_history")
  candidates+=("${HOME}/.zsh_history_root")
  candidates+=("${HOME}/.bash_history")
  if [[ -n "${HISTFILE:-}" && "${HISTFILE}" != "${HOME}/.zsh_history" && "${HISTFILE}" != "${HOME}/.bash_history" ]]; then
    candidates+=("${HISTFILE}")
  fi
  candidates+=("${state_dir}/muxrc/ai-audit.log")
  candidates+=("${cache_dir}/muxrc/clip_history.log")
  candidates+=("${data_dir}/Trash")
  candidates+=("${HOME}/.trash")

  local item
  for item in "${candidates[@]}"; do
    if [[ -e "${item}" || -L "${item}" ]]; then
      printf '%s\n' "${item}"
    fi
  done
}

shred_target() {
  local target="${1:-}"
  local dry_run="${2:-0}"

  if [[ ! -e "${target}" && ! -L "${target}" ]]; then
    return 0
  fi

  if [[ -f "${target}" || -L "${target}" ]]; then
    if ((dry_run == 1)); then
      log_info "[dry-run] would shred: ${target}"
      return 0
    fi
    shred_file "${target}" 1
    rm -f "${target}" 2> /dev/null || true
    return 0
  fi

  if [[ -d "${target}" ]]; then
    if ((dry_run == 1)); then
      log_info "[dry-run] would shred directory: ${target}"
      return 0
    fi

    local file
    while IFS= read -r -d '' file; do
      shred_file "${file}" 1
    done < <(find "${target}" ! -type d -print0 2> /dev/null)

    rm -rf "${target}" 2> /dev/null || true
  fi
}

wipe_clipboard() {
  local dry_run="${1:-0}"

  if command -v termux-clipboard-set > /dev/null 2>&1; then
    if ((dry_run == 1)); then
      log_info "[dry-run] would wipe android clipboard"
      return 0
    fi
    printf "" | termux-clipboard-set 2> /dev/null || true
    log_success "clipboard wiped"
  else
    log_warn "termux-clipboard-set not found (clipboard not wiped)"
  fi
}

confirm_panic() {
  local confirm=""

  log_warn "emergency panic: permanently destroying credentials, history, and vault"
  log_prompt "type 'PANIC' to confirm: "
  read -r confirm

  [[ "${confirm}" == "PANIC" ]]
}

main() {
  local force=0
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h | --help)
        usage
        return 0
        ;;
      -f | --force)
        force=1
        ;;
      -n | --dry-run)
        dry_run=1
        ;;
      -*)
        log_error "unknown option: $1 (see -h)"
        return 1
        ;;
      *)
        log_error "unexpected argument: $1 (see -h)"
        return 1
        ;;
    esac
    shift
  done

  local -a targets=()
  local target
  while IFS= read -r target; do
    [[ -n "${target}" ]] && targets+=("${target}")
  done < <(get_targets)

  if [[ ${#targets[@]} -eq 0 ]]; then
    log_info "no sensitive targets found to destroy"
    wipe_clipboard "${dry_run}"
    return 0
  fi

  if ((dry_run == 1)); then
    log_info "panic dry-run simulation:"
    for target in "${targets[@]}"; do
      shred_target "${target}" 1
    done
    wipe_clipboard 1
    log_success "dry-run complete: 0 files modified"
    return 0
  fi

  if ((force == 0)); then
    log_warn "the following targets will be permanently destroyed:"
    for target in "${targets[@]}"; do
      log_warn "  - ${target}"
    done

    if ! confirm_panic; then
      log_warn "aborted"
      return 1
    fi
  fi

  log_info "executing panic protocol..."
  for target in "${targets[@]}"; do
    log_info "destroying: ${target}"
    shred_target "${target}" 0
  done

  wipe_clipboard 0
  log_success "panic protocol complete: credentials and vault destroyed"
}

main "$@"
