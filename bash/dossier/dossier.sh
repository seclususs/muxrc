#!/data/data/com.termux/files/usr/bin/bash

#####################
# Dossier Main Engine
#####################
set -euo pipefail

_dossier_engine_dir="${BASH_SOURCE[0]%/*}"
if [[ "${_dossier_engine_dir}" == "${BASH_SOURCE[0]}" ]]; then
  _dossier_engine_dir="."
fi
# shellcheck source=init.sh
source "${_dossier_engine_dir}/init.sh"
unset _dossier_engine_dir

DOSSIER_CONFIG_DIR="${DOSSIER_CONFIG_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/dossier}"
DOSSIER_CONFIG_FILE="${DOSSIER_CONFIG_FILE:-${DOSSIER_CONFIG_DIR}/config.env}"
DOSSIER_WORKSPACE="${DOSSIER_WORKSPACE:-}"

MAX_NAME_LEN=24
MAX_USERNAME_LEN=26
MAX_ADDR_LEN=60
MAX_PHONE_LEN=18
MAX_LABEL_LEN=12
MAX_EMAIL_LEN=35
MAX_PLATFORM_LEN=12
MAX_SOCUSER_LEN=20
MAX_URL_LEN=50

CLI_WORKSPACE_OVERRIDE=""

check_dependencies() {
  require_cmd jq
}

trim() {
  local var="${1:-}"
  var="${var#"${var%%[![:space:]]*}"}"
  var="${var%"${var##*[![:space:]]}"}"
  printf '%s' "${var}"
}

clean_url_display() {
  local url="${1:-}"
  url="${url#https://}"
  url="${url#http://}"
  url="${url#www.}"
  url="${url%/}"
  printf '%s' "${url}"
}

slugify() {
  local input="${1:-}"
  local clean
  clean=$(printf '%s' "${input}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')
  if [[ ${#clean} -gt ${MAX_USERNAME_LEN} ]]; then
    clean="${clean:0:${MAX_USERNAME_LEN}}"
    clean="${clean%-}"
  fi
  if [[ -z "${clean}" ]]; then
    clean="identity"
  fi
  printf '%s' "${clean}"
}

copy_to_clipboard() {
  local text="${1:-}"
  if command -v termux-clipboard-set > /dev/null 2>&1; then
    printf '%s' "${text}" | termux-clipboard-set
    return 0
  elif command -v wl-copy > /dev/null 2>&1; then
    printf '%s' "${text}" | wl-copy
    return 0
  elif command -v xclip > /dev/null 2>&1; then
    printf '%s' "${text}" | xclip -selection clipboard
    return 0
  elif command -v pbcopy > /dev/null 2>&1; then
    printf '%s' "${text}" | pbcopy
    return 0
  elif [[ -w /dev/clipboard ]]; then
    printf '%s' "${text}" > /dev/clipboard
    return 0
  fi
  return 1
}

load_workspace() {
  if [[ -n "${CLI_WORKSPACE_OVERRIDE}" ]]; then
    DOSSIER_WORKSPACE="${CLI_WORKSPACE_OVERRIDE}"
    return 0
  fi

  if [[ -n "${DOSSIER_WORKSPACE:-}" ]]; then
    return 0
  fi

  if [[ -f "${DOSSIER_CONFIG_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${DOSSIER_CONFIG_FILE}"
    if [[ -n "${DOSSIER_WORKSPACE:-}" ]]; then
      return 0
    fi
  fi

  prompt_workspace_setup
}

save_workspace_config() {
  local target_dir="${1:-}"
  if [[ -z "${target_dir}" ]]; then
    log_error "workspace path is empty"
    return 1
  fi

  mkdir -p "${DOSSIER_CONFIG_DIR}"
  local tmp_cfg
  tmp_cfg=$(mktemp "${DOSSIER_CONFIG_DIR}/config.XXXXXX")
  printf 'DOSSIER_WORKSPACE="%s"\n' "${target_dir}" > "${tmp_cfg}"
  mv -f "${tmp_cfg}" "${DOSSIER_CONFIG_FILE}"
  DOSSIER_WORKSPACE="${target_dir}"
  log_success "workspace config saved"
}

prompt_workspace_setup() {
  log_info "no workspace configured"
  log_prompt "enter workspace directory: "
  local input_dir=""
  read -r input_dir || true
  input_dir=$(trim "${input_dir}")

  if [[ -z "${input_dir}" ]]; then
    input_dir="${HOME}/dossier"
  fi

  if [[ "${input_dir}" == ~* ]]; then
    input_dir="${HOME}${input_dir#"~"}"
  fi

  mkdir -p "${input_dir}"
  save_workspace_config "${input_dir}"
}

resolve_unique_slug() {
  local base_slug="${1:-}"
  local workspace_dir="${2:-}"
  local candidate="${base_slug}"
  local counter=2

  while [[ -f "${workspace_dir}/${candidate}.json" ]]; do
    candidate="${base_slug}-${counter}"
    counter=$((counter + 1))
  done

  printf '%s' "${candidate}"
}

find_dossier_file() {
  local query="${1:-}"
  local workspace_dir="${2:-}"

  if [[ -z "${query}" ]]; then
    return 1
  fi

  local exact_file="${workspace_dir}/${query}.json"
  if [[ -f "${exact_file}" ]]; then
    printf '%s' "${exact_file}"
    return 0
  fi

  local -a matches=()
  local file
  for file in "${workspace_dir}"/*.json; do
    [[ -e "${file}" ]] || break
    local bname="${file##*/}"
    bname="${bname%.json}"
    if [[ "${bname}" == *"${query}"* ]]; then
      matches+=("${file}")
    fi
  done

  if [[ ${#matches[@]} -eq 1 ]]; then
    printf '%s' "${matches[0]}"
    return 0
  elif [[ ${#matches[@]} -gt 1 ]]; then
    log_warn "multiple dossiers match '${query}':"
    local m
    for m in "${matches[@]}"; do
      local mb="${m##*/}"
      printf '  * %s\n' "${mb%.json}" >&2
    done
    return 2
  fi

  return 1
}

read_capped_input() {
  local prompt_label="${1:-}"
  local max_len="${2:-30}"
  local is_required="${3:-0}"
  local var_out="${4:-}"

  while true; do
    log_prompt "${prompt_label}: "
    local val=""
    read -r val || true
    val=$(trim "${val}")

    if [[ -z "${val}" ]]; then
      if [[ "${is_required}" -eq 1 ]]; then
        log_error "value cannot be empty"
        continue
      else
        eval "${var_out}=''"
        return 0
      fi
    fi

    if [[ ${#val} -gt ${max_len} ]]; then
      log_warn "max ${max_len} chars allowed"
      continue
    fi

    eval "${var_out}=\${val}"
    return 0
  done
}

cmd_help() {
  cat << 'EOF'
dossier: personal identity manager

Usage:
  dossier                     Launch interactive menu
  dossier ls, list            List all dossiers
  dossier <name>              Display parsed card
  dossier <name> --raw        Output raw JSON
  dossier cp <name> [target]  Copy link to clipboard

Options:
  -w, --workspace <path>      Use custom workspace
  -h, --help                  Show this help text

Examples:
  dossier                     (interactive wizard)
  dossier ls
  dossier john-doe
  dossier cp john-doe         (link picker)
  dossier cp john-doe github
EOF
}

cmd_list() {
  load_workspace
  local ws="${DOSSIER_WORKSPACE}"

  if [[ ! -d "${ws}" ]]; then
    log_warn "workspace directory missing"
    return 0
  fi

  local -a files=("${ws}"/*.json)
  if [[ ! -e "${files[0]}" ]]; then
    printf 'WORKSPACE: %s (0 files)\n' "${ws}"
    printf '%s\n' '--------------------------------------------------'
    printf 'no dossiers found.\n'
    return 0
  fi

  printf 'WORKSPACE: %s (%d files)\n' "${ws}" "${#files[@]}"
  printf '%s\n' '--------------------------------------------------'
  printf '%-20s  %-20s\n' "NAME" "USERNAME"
  printf '%s\n' '--------------------------------------------------'

  local f
  for f in "${files[@]}"; do
    local d_name="" d_user=""
    d_name=$(jq -r '.name // ""' "${f}" 2> /dev/null || true)
    d_user=$(jq -r '.username // ""' "${f}" 2> /dev/null || true)

    if [[ -z "${d_user}" ]]; then
      d_user="${f##*/}"
      d_user="${d_user%.json}"
    fi

    if [[ ${#d_name} -gt 20 ]]; then
      d_name="${d_name:0:18}.."
    fi
    if [[ ${#d_user} -gt 20 ]]; then
      d_user="${d_user:0:18}.."
    fi

    printf '%-20s  %-20s\n' "${d_name}" "${d_user}"
  done
  printf '%s\n' '--------------------------------------------------'
  printf 'Total: %d dossiers\n' "${#files[@]}"
}

cmd_show() {
  local query="${1:-}"
  load_workspace
  local ws="${DOSSIER_WORKSPACE}"

  local target_file=""
  if ! target_file=$(find_dossier_file "${query}" "${ws}"); then
    log_error "dossier not found: ${query}"
    return 1
  fi

  local name address
  name=$(jq -r '.name // ""' "${target_file}")
  address=$(jq -r '.address // ""' "${target_file}")

  printf '==================================================\n'
  printf 'DOSSIER: %s\n' "${name}"
  printf '==================================================\n'

  if [[ -n "${address}" ]]; then
    local -a words=()
    read -r -a words <<< "${address}"
    local first_line=1
    local cur_line=""
    local max_w=48
    local pfx="Address : "
    local ind="          "

    local w
    for w in "${words[@]}"; do
      if [[ "${first_line}" -eq 1 ]]; then
        if [[ $((${#cur_line} + ${#w} + ${#pfx} + 1)) -le ${max_w} ]]; then
          if [[ -z "${cur_line}" ]]; then
            cur_line="${w}"
          else
            cur_line="${cur_line} ${w}"
          fi
        else
          printf '%s%s\n' "${pfx}" "${cur_line}"
          first_line=0
          cur_line="${w}"
        fi
      else
        if [[ $((${#cur_line} + ${#w} + ${#ind} + 1)) -le ${max_w} ]]; then
          if [[ -z "${cur_line}" ]]; then
            cur_line="${w}"
          else
            cur_line="${cur_line} ${w}"
          fi
        else
          printf '%s%s\n' "${ind}" "${cur_line}"
          cur_line="${w}"
        fi
      fi
    done

    if [[ -n "${cur_line}" ]]; then
      if [[ "${first_line}" -eq 1 ]]; then
        printf '%s%s\n' "${pfx}" "${cur_line}"
      else
        printf '%s%s\n' "${ind}" "${cur_line}"
      fi
    fi
  else
    printf 'Address : (none)\n'
  fi

  local phone_lines
  phone_lines=$(jq -r '.phones[]? | "\(.number // "")\t\(.label // "mobile")\t\(.whatsapp // false)"' "${target_file}")
  if [[ -z "${phone_lines}" ]]; then
    printf 'Phone   : (none)\n'
  else
    local p_first=1
    while IFS=$'\t' read -r pnum plabel pwa; do
      [[ -n "${pnum}" ]] || continue
      local meta="${plabel}"
      if [[ "${pwa}" == "true" ]]; then
        meta="${meta}, WA"
      fi
      if [[ "${p_first}" -eq 1 ]]; then
        printf 'Phone   : %s (%s)\n' "${pnum}" "${meta}"
        p_first=0
      else
        printf '          %s (%s)\n' "${pnum}" "${meta}"
      fi
    done <<< "${phone_lines}"
  fi

  local email_lines
  email_lines=$(jq -r '.emails[]? | "\(.address // "")\t\(.label // "personal")"' "${target_file}")
  if [[ -z "${email_lines}" ]]; then
    printf 'Email   : (none)\n'
  else
    local e_first=1
    while IFS=$'\t' read -r eaddr elabel; do
      [[ -n "${eaddr}" ]] || continue
      if [[ "${e_first}" -eq 1 ]]; then
        printf 'Email   : %s (%s)\n' "${eaddr}" "${elabel}"
        e_first=0
      else
        printf '          %s (%s)\n' "${eaddr}" "${elabel}"
      fi
    done <<< "${email_lines}"
  fi

  local soc_lines
  soc_lines=$(jq -r '.socials[]? | "\(.platform // "")\t\(.username // "")\t\(.url // "")"' "${target_file}")
  if [[ -z "${soc_lines}" ]]; then
    printf 'Social  : (none)\n'
  else
    local s_first=1
    while IFS=$'\t' read -r splat suser surl; do
      [[ -n "${splat}" || -n "${suser}" || -n "${surl}" ]] || continue
      local s_display=""
      if [[ -n "${suser}" ]]; then
        s_display="@${suser} (${splat})"
      else
        s_display="$(clean_url_display "${surl}") (${splat})"
      fi
      if [[ "${s_first}" -eq 1 ]]; then
        printf 'Social  : %s\n' "${s_display}"
        s_first=0
      else
        printf '          %s\n' "${s_display}"
      fi
    done <<< "${soc_lines}"
  fi

  local link_lines
  link_lines=$(jq -r '.links[]? | "\(.label // "link")\t\(.url // "")"' "${target_file}")
  if [[ -z "${link_lines}" ]]; then
    printf 'Link    : (none)\n'
  else
    local l_first=1
    while IFS=$'\t' read -r llabel lurl; do
      [[ -n "${lurl}" ]] || continue
      local clean_l
      clean_l=$(clean_url_display "${lurl}")
      if [[ "${l_first}" -eq 1 ]]; then
        printf 'Link    : %s (%s)\n' "${clean_l}" "${llabel}"
        l_first=0
      else
        printf '          %s (%s)\n' "${clean_l}" "${llabel}"
      fi
    done <<< "${link_lines}"
  fi
  printf '==================================================\n'
}

cmd_raw() {
  local query="${1:-}"
  load_workspace
  local ws="${DOSSIER_WORKSPACE}"

  local target_file=""
  if ! target_file=$(find_dossier_file "${query}" "${ws}"); then
    log_error "dossier not found: ${query}"
    return 1
  fi

  jq . "${target_file}"
}

cmd_copy() {
  local query="${1:-}"
  local target_key="${2:-}"
  load_workspace
  local ws="${DOSSIER_WORKSPACE}"

  local target_file=""
  if ! target_file=$(find_dossier_file "${query}" "${ws}"); then
    log_error "dossier not found: ${query}"
    return 1
  fi

  local d_name
  d_name=$(jq -r '.name // "Dossier"' "${target_file}")

  local -a items_label=()
  local -a items_val=()

  local soc_data
  soc_data=$(jq -r '.socials[]? | select(.url != null and .url != "") | "social:\(.platform // "link")\t\(.url)"' "${target_file}")
  if [[ -n "${soc_data}" ]]; then
    while IFS=$'\t' read -r s_lbl s_val; do
      [[ -n "${s_lbl}" && -n "${s_val}" ]] || continue
      items_label+=("${s_lbl}")
      items_val+=("${s_val}")
    done <<< "${soc_data}"
  fi

  local link_data
  link_data=$(jq -r '.links[]? | select(.url != null and .url != "") | "link:\(.label // "link")\t\(.url)"' "${target_file}")
  if [[ -n "${link_data}" ]]; then
    while IFS=$'\t' read -r l_lbl l_val; do
      [[ -n "${l_lbl}" && -n "${l_val}" ]] || continue
      items_label+=("${l_lbl}")
      items_val+=("${l_val}")
    done <<< "${link_data}"
  fi

  local phone_data
  phone_data=$(jq -r '.phones[]? | select(.number != null and .number != "") | "phone:\(.label // "phone")\t\(.number)"' "${target_file}")
  if [[ -n "${phone_data}" ]]; then
    while IFS=$'\t' read -r p_lbl p_val; do
      [[ -n "${p_lbl}" && -n "${p_val}" ]] || continue
      items_label+=("${p_lbl}")
      items_val+=("${p_val}")
    done <<< "${phone_data}"
  fi

  local email_data
  email_data=$(jq -r '.emails[]? | select(.address != null and .address != "") | "email:\(.label // "email")\t\(.address)"' "${target_file}")
  if [[ -n "${email_data}" ]]; then
    while IFS=$'\t' read -r e_lbl e_val; do
      [[ -n "${e_lbl}" && -n "${e_val}" ]] || continue
      items_label+=("${e_lbl}")
      items_val+=("${e_val}")
    done <<< "${email_data}"
  fi

  if [[ ${#items_val[@]} -eq 0 ]]; then
    log_warn "no links or fields to copy"
    return 0
  fi

  local selected_val=""
  if [[ -n "${target_key}" ]]; then
    local idx
    for ((idx = 0; idx < ${#items_label[@]}; idx++)); do
      local cur_lbl="${items_label[idx]}"
      if [[ "${cur_lbl,,}" == *"${target_key,,}"* ]]; then
        selected_val="${items_val[idx]}"
        break
      fi
    done

    if [[ -z "${selected_val}" ]]; then
      log_error "target not found: ${target_key}"
      return 1
    fi
  else
    printf 'Available items for %s:\n' "${d_name}"
    local p
    for ((p = 0; p < ${#items_label[@]}; p++)); do
      printf ' [%d] %-14s : %s\n' "$((p + 1))" "${items_label[p]}" "${items_val[p]}"
    done
    printf ' [0] Cancel\n'
    printf '%s\n' '--------------------------------------------------'

    log_prompt "select item to copy [0-%d]: " "${#items_label[@]}"
    local choice=""
    read -r choice || true
    choice=$(trim "${choice}")

    if [[ -z "${choice}" || "${choice}" == "0" ]]; then
      return 0
    fi

    if ! [[ "${choice}" =~ ^[0-9]+$ ]] || [[ "${choice}" -gt ${#items_label[@]} ]]; then
      log_error "invalid selection"
      return 1
    fi

    selected_val="${items_val[$((choice - 1))]}"
  fi

  if copy_to_clipboard "${selected_val}"; then
    log_success "copied to clipboard: ${selected_val}"
  else
    log_warn "clipboard tool unavailable"
    printf '%s\n' "${selected_val}"
  fi
}

cmd_new() {
  load_workspace
  local ws="${DOSSIER_WORKSPACE}"
  mkdir -p "${ws}"

  printf 'Target workspace: %s\n\n' "${ws}"

  local name="" address=""
  read_capped_input "Full name" "${MAX_NAME_LEN}" 1 name
  read_capped_input "Address" "${MAX_ADDR_LEN}" 0 address

  local base_slug
  base_slug=$(slugify "${name}")
  local unique_slug
  unique_slug=$(resolve_unique_slug "${base_slug}" "${ws}")

  if [[ "${base_slug}" != "${unique_slug}" ]]; then
    log_warn "'${base_slug}' already exists"
    if ! prompt_confirm "save as '${unique_slug}'?" "Y"; then
      log_warn "operation cancelled"
      return 0
    fi
  fi

  local phones_json="[]"
  printf '\n--- PHONE NUMBERS (press Enter to finish) ---\n'
  local phone_idx=1
  while true; do
    local p_num="" p_lbl="" p_wa="false"
    read_capped_input "Phone ${phone_idx} number" "${MAX_PHONE_LEN}" 0 p_num
    [[ -z "${p_num}" ]] && break

    read_capped_input "Phone ${phone_idx} label (default: mobile)" "${MAX_LABEL_LEN}" 0 p_lbl
    [[ -z "${p_lbl}" ]] && p_lbl="mobile"

    if prompt_confirm "connected to WhatsApp?" "Y"; then
      p_wa="true"
    fi

    phones_json=$(printf '%s' "${phones_json}" | jq \
      --arg lbl "${p_lbl}" \
      --arg num "${p_num}" \
      --argjson wa "${p_wa}" \
      '. += [{"label": $lbl, "number": $num, "whatsapp": $wa}]')
    phone_idx=$((phone_idx + 1))
  done

  local socials_json="[]"
  printf '\n--- SOCIAL MEDIA (press Enter to finish) ---\n'
  local soc_idx=1
  while true; do
    local s_plat="" s_user="" s_url=""
    read_capped_input "Social ${soc_idx} platform" "${MAX_PLATFORM_LEN}" 0 s_plat
    [[ -z "${s_plat}" ]] && break

    read_capped_input "Social ${soc_idx} username" "${MAX_SOCUSER_LEN}" 0 s_user

    local suggested_url=""
    case "${s_plat,,}" in
      github) suggested_url="https://github.com/${s_user}" ;;
      telegram) suggested_url="https://t.me/${s_user}" ;;
      instagram) suggested_url="https://instagram.com/${s_user}" ;;
      x | twitter) suggested_url="https://x.com/${s_user}" ;;
      linkedin) suggested_url="https://linkedin.com/in/${s_user}" ;;
    esac

    if [[ -n "${suggested_url}" ]]; then
      read_capped_input "Social ${soc_idx} URL (default: ${suggested_url})" "${MAX_URL_LEN}" 0 s_url
      [[ -z "${s_url}" ]] && s_url="${suggested_url}"
    else
      read_capped_input "Social ${soc_idx} URL" "${MAX_URL_LEN}" 0 s_url
    fi

    socials_json=$(printf '%s' "${socials_json}" | jq \
      --arg plat "${s_plat}" \
      --arg user "${s_user}" \
      --arg url "${s_url}" \
      '. += [{"platform": $plat, "username": $user, "url": $url}]')
    soc_idx=$((soc_idx + 1))
  done

  local emails_json="[]"
  printf '\n--- EMAIL ADDRESSES (press Enter to finish) ---\n'
  local email_idx=1
  while true; do
    local e_addr="" e_lbl=""
    read_capped_input "Email ${email_idx} address" "${MAX_EMAIL_LEN}" 0 e_addr
    [[ -z "${e_addr}" ]] && break

    read_capped_input "Email ${email_idx} label (default: personal)" "${MAX_LABEL_LEN}" 0 e_lbl
    [[ -z "${e_lbl}" ]] && e_lbl="personal"

    emails_json=$(printf '%s' "${emails_json}" | jq \
      --arg lbl "${e_lbl}" \
      --arg addr "${e_addr}" \
      '. += [{"label": $lbl, "address": $addr}]')
    email_idx=$((email_idx + 1))
  done

  local links_json="[]"
  printf '\n--- LINKS (press Enter to finish) ---\n'
  local link_idx=1
  while true; do
    local l_lbl="" l_url=""
    read_capped_input "Link ${link_idx} label (default: website)" "${MAX_LABEL_LEN}" 0 l_lbl
    [[ -z "${l_lbl}" ]] && break

    read_capped_input "Link ${link_idx} URL" "${MAX_URL_LEN}" 0 l_url

    links_json=$(printf '%s' "${links_json}" | jq \
      --arg lbl "${l_lbl}" \
      --arg url "${l_url}" \
      '. += [{"label": $lbl, "url": $url}]')
    link_idx=$((link_idx + 1))
  done

  printf '\n'
  if ! prompt_confirm "save dossier to ${unique_slug}.json?" "Y"; then
    log_warn "save cancelled"
    return 0
  fi

  local now_iso
  now_iso=$(date -Iseconds 2> /dev/null || date +"%Y-%m-%dT%H:%M:%S%z")

  local final_file="${ws}/${unique_slug}.json"
  local tmp_f
  tmp_f=$(mktemp "${ws}/dossier.XXXXXX")

  jq -n \
    --arg name "${name}" \
    --arg username "${unique_slug}" \
    --arg address "${address}" \
    --argjson phones "${phones_json}" \
    --argjson socials "${socials_json}" \
    --argjson emails "${emails_json}" \
    --argjson links "${links_json}" \
    --arg now "${now_iso}" \
    '{
      name: $name,
      username: $username,
      address: $address,
      phones: $phones,
      socials: $socials,
      emails: $emails,
      links: $links,
      created_at: $now,
      updated_at: $now
    }' > "${tmp_f}"

  mv -f "${tmp_f}" "${final_file}"
  log_success "dossier created: ${unique_slug}.json"
}

cmd_append() {
  load_workspace
  local ws="${DOSSIER_WORKSPACE}"

  local -a files=("${ws}"/*.json)
  if [[ ! -e "${files[0]}" ]]; then
    log_warn "no dossiers available to append"
    return 0
  fi

  log_prompt "target dossier name/username: "
  local target_query=""
  read -r target_query || true
  target_query=$(trim "${target_query}")

  local target_file=""
  if ! target_file=$(find_dossier_file "${target_query}" "${ws}"); then
    log_error "dossier not found"
    return 1
  fi

  local d_name
  d_name=$(jq -r '.name // "Dossier"' "${target_file}")

  printf '\nAppend data to %s:\n' "${d_name}"
  printf ' [1] Phone number\n'
  printf ' [2] Social media\n'
  printf ' [3] Email address\n'
  printf ' [4] Web link\n'
  printf ' [0] Cancel\n'
  printf '%s\n' '--------------------------------------------------'

  log_prompt "select field to append [0-4]: "
  local choice=""
  read -r choice || true
  choice=$(trim "${choice}")

  local now_iso
  now_iso=$(date -Iseconds 2> /dev/null || date +"%Y-%m-%dT%H:%M:%S%z")
  local tmp_mod
  tmp_mod=$(mktemp "${ws}/append.XXXXXX")

  case "${choice}" in
    1)
      local p_num="" p_lbl="" p_wa="false"
      read_capped_input "Phone number" "${MAX_PHONE_LEN}" 1 p_num
      read_capped_input "Label (default: mobile)" "${MAX_LABEL_LEN}" 0 p_lbl
      [[ -z "${p_lbl}" ]] && p_lbl="mobile"
      if prompt_confirm "connected to WhatsApp?" "Y"; then
        p_wa="true"
      fi

      jq --arg lbl "${p_lbl}" --arg num "${p_num}" --argjson wa "${p_wa}" --arg now "${now_iso}" \
        '.phones += [{"label": $lbl, "number": $num, "whatsapp": $wa}] | .updated_at = $now' \
        "${target_file}" > "${tmp_mod}"
      mv -f "${tmp_mod}" "${target_file}"
      log_success "phone appended successfully"
      ;;
    2)
      local s_plat="" s_user="" s_url=""
      read_capped_input "Platform" "${MAX_PLATFORM_LEN}" 1 s_plat
      read_capped_input "Username" "${MAX_SOCUSER_LEN}" 0 s_user
      read_capped_input "URL link" "${MAX_URL_LEN}" 0 s_url

      jq --arg plat "${s_plat}" --arg user "${s_user}" --arg url "${s_url}" --arg now "${now_iso}" \
        '.socials += [{"platform": $plat, "username": $user, "url": $url}] | .updated_at = $now' \
        "${target_file}" > "${tmp_mod}"
      mv -f "${tmp_mod}" "${target_file}"
      log_success "social appended successfully"
      ;;
    3)
      local e_addr="" e_lbl=""
      read_capped_input "Email address" "${MAX_EMAIL_LEN}" 1 e_addr
      read_capped_input "Label (default: personal)" "${MAX_LABEL_LEN}" 0 e_lbl
      [[ -z "${e_lbl}" ]] && e_lbl="personal"

      jq --arg lbl "${e_lbl}" --arg addr "${e_addr}" --arg now "${now_iso}" \
        '.emails += [{"label": $lbl, "address": $addr}] | .updated_at = $now' \
        "${target_file}" > "${tmp_mod}"
      mv -f "${tmp_mod}" "${target_file}"
      log_success "email appended successfully"
      ;;
    4)
      local l_lbl="" l_url=""
      read_capped_input "Label" "${MAX_LABEL_LEN}" 1 l_lbl
      read_capped_input "URL link" "${MAX_URL_LEN}" 1 l_url

      jq --arg lbl "${l_lbl}" --arg url "${l_url}" --arg now "${now_iso}" \
        '.links += [{"label": $lbl, "url": $url}] | .updated_at = $now' \
        "${target_file}" > "${tmp_mod}"
      mv -f "${tmp_mod}" "${target_file}"
      log_success "link appended successfully"
      ;;
    0 | "")
      rm -f "${tmp_mod}"
      return 0
      ;;
    *)
      rm -f "${tmp_mod}"
      log_error "invalid option"
      return 1
      ;;
  esac
}

cmd_edit() {
  load_workspace
  local ws="${DOSSIER_WORKSPACE}"

  log_prompt "target dossier to edit: "
  local target_query=""
  read -r target_query || true
  target_query=$(trim "${target_query}")

  local target_file=""
  if ! target_file=$(find_dossier_file "${target_query}" "${ws}"); then
    log_error "dossier not found"
    return 1
  fi

  local editor_bin="${EDITOR:-nano}"
  local tmp_edit
  tmp_edit=$(mktemp "${ws}/edit.XXXXXX")
  cp -f "${target_file}" "${tmp_edit}"

  while true; do
    "${editor_bin}" "${tmp_edit}"
    if jq empty "${tmp_edit}" 2> /dev/null; then
      local now_iso
      now_iso=$(date -Iseconds 2> /dev/null || date +"%Y-%m-%dT%H:%M:%S%z")
      local tmp_stamped
      tmp_stamped=$(mktemp "${ws}/edit_stamp.XXXXXX")
      jq --arg now "${now_iso}" '.updated_at = $now' "${tmp_edit}" > "${tmp_stamped}"
      mv -f "${tmp_stamped}" "${target_file}"
      rm -f "${tmp_edit}"
      log_success "dossier updated successfully"
      return 0
    else
      log_error "invalid json syntax"
      if prompt_confirm "re-open editor to fix?" "Y"; then
        continue
      else
        rm -f "${tmp_edit}"
        log_warn "changes discarded"
        return 1
      fi
    fi
  done
}

cmd_delete() {
  load_workspace
  local ws="${DOSSIER_WORKSPACE}"

  log_prompt "target dossier to delete: "
  local target_query=""
  read -r target_query || true
  target_query=$(trim "${target_query}")

  local target_file=""
  if ! target_file=$(find_dossier_file "${target_query}" "${ws}"); then
    log_error "dossier not found"
    return 1
  fi

  local bname="${target_file##*/}"
  if prompt_confirm "permanently delete ${bname}?" "N"; then
    rm -f "${target_file}"
    log_success "dossier deleted: ${bname}"
  else
    log_warn "deletion aborted"
  fi
}

cmd_set_workspace() {
  load_workspace
  printf 'Current workspace: %s\n' "${DOSSIER_WORKSPACE}"
  log_prompt "enter new workspace path: "
  local new_path=""
  read -r new_path || true
  new_path=$(trim "${new_path}")

  if [[ -z "${new_path}" ]]; then
    log_warn "no path entered, keeping current"
    return 0
  fi

  if [[ "${new_path}" == ~* ]]; then
    new_path="${HOME}${new_path#"~"}"
  fi

  mkdir -p "${new_path}"
  save_workspace_config "${new_path}"
}

cmd_menu() {
  load_workspace
  while true; do
    printf '\n==================================================\n'
    printf '                    DOSSIER\n'
    printf '   Workspace: %s\n' "${DOSSIER_WORKSPACE}"
    printf '==================================================\n'
    printf ' [1] New dossier\n'
    printf ' [2] Append data to dossier\n'
    printf ' [3] Edit dossier in editor\n'
    printf ' [4] Delete dossier\n'
    printf ' [5] Set workspace path\n'
    printf ' [0] Exit\n'
    printf '%s\n' '--------------------------------------------------'

    log_prompt "Select [0-5]: "
    local choice=""
    read -r choice || true
    choice=$(trim "${choice}")

    case "${choice}" in
      1) cmd_new ;;
      2) cmd_append ;;
      3) cmd_edit ;;
      4) cmd_delete ;;
      5) cmd_set_workspace ;;
      0 | "exit" | "q")
        log_info "bye!"
        break
        ;;
      *)
        log_error "invalid selection"
        ;;
    esac
  done
}

main() {
  check_dependencies

  while [[ $# -gt 0 ]]; do
    case "${1}" in
      -w | --workspace)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "missing workspace argument"
          exit 1
        fi
        CLI_WORKSPACE_OVERRIDE="${1}"
        shift
        ;;
      -h | --help)
        cmd_help
        exit 0
        ;;
      ls | list)
        shift
        cmd_list "$@"
        exit 0
        ;;
      cp | copy)
        shift
        if [[ $# -eq 0 ]]; then
          log_error "usage: dossier cp <name> [target]"
          exit 1
        fi
        cmd_copy "$@"
        exit 0
        ;;
      *)
        break
        ;;
    esac
  done

  if [[ $# -eq 0 ]]; then
    if [[ -n "${CLI_WORKSPACE_OVERRIDE}" ]]; then
      save_workspace_config "${CLI_WORKSPACE_OVERRIDE}"
      exit 0
    fi
    cmd_menu
    exit 0
  fi

  local target_arg="${1}"
  shift

  if [[ "${1:-}" == "--raw" || "${1:-}" == "--json" ]]; then
    cmd_raw "${target_arg}"
    exit 0
  fi

  cmd_show "${target_arg}"
}

main "$@"
