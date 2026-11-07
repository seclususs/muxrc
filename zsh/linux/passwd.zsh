#########################
# Password change wrapper
#########################

passwd() {
  setopt localoptions nomonitor
  zmodload zsh/datetime 2> /dev/null

  if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    print "Usage: passwd [options] [LOGIN]"
    print ""
    print "Change user password."
    print ""
    print "Options:"
    print "  -h, --help    display this help message and exit"
    print "  -S, --status  report password status on the named account"
    return 0
  fi

  local current_user="${USER:-$(whoami)}"
  local target_user="${1:-$current_user}"
  local shadow_file=""
  shadow_file="$(_auth_get_shadow_file)"

  if [[ "$1" == "-S" || "$1" == "--status" ]]; then
    target_user="${2:-$current_user}"
    local stored_hash=""
    stored_hash=$(_auth_get_hash "$target_user")
    if [[ -n "$stored_hash" ]]; then
      local last_changed="0"
      if [[ -f "$shadow_file" ]]; then
        last_changed=$(awk -F: -v u="$target_user" '$1 == u {print $3; exit}' "$shadow_file" 2> /dev/null)
        [[ -z "$last_changed" ]] && last_changed=$(awk -F: 'NR==1 {print $3; exit}' "$shadow_file" 2> /dev/null)
      fi
      local date_str=""
      if [[ -n "$last_changed" && "$last_changed" =~ ^[0-9]+$ && "$last_changed" -gt 0 ]]; then
        local epoch_sec=$(( last_changed * 86400 ))
        date_str=$(date -d "@$epoch_sec" +%m/%d/%Y 2> /dev/null || date +%m/%d/%Y 2> /dev/null)
      else
        date_str=$(date +%m/%d/%Y 2> /dev/null)
      fi
      print "$target_user P $date_str 0 99999 7 -1"
    else
      print "$target_user NP $(date +%m/%d/%Y 2> /dev/null) 0 99999 7 -1"
    fi
    return 0
  fi

  if [[ "$target_user" != "$current_user" && "$target_user" != "root" && "$EUID" -ne 0 ]]; then
    print -u2 "passwd: You may not view or modify password information for $target_user."
    return 1
  fi

  print "Changing password for $target_user."

  local stored_hash=""
  stored_hash=$(_auth_get_hash "$target_user")

  if [[ "$EUID" -ne 0 && -n "$stored_hash" ]]; then
    local current_pass=""
    if ! _auth_read_secret "Current password: " current_pass; then
      print -u2 ""
      return 130
    fi
    print -u2 ""

    if ! _auth_verify_password "$current_pass" "$stored_hash"; then
      print -u2 "passwd: Authentication failure"
      return 1
    fi
  fi

  local new_pass=""
  local confirm_pass=""

  if ! _auth_read_secret "New password: " new_pass; then
    print -u2 ""
    return 130
  fi
  print -u2 ""

  if [[ -z "$new_pass" ]]; then
    print -u2 "passwd: password unchanged"
    return 1
  fi

  if ! _auth_read_secret "Retype new password: " confirm_pass; then
    print -u2 ""
    return 130
  fi
  print -u2 ""

  if [[ "$new_pass" != "$confirm_pass" ]]; then
    print -u2 "passwd: Have you been chewing garlic?"
    print -u2 "passwd: password unchanged"
    return 1
  fi

  local new_hash=""
  if command -v openssl > /dev/null 2>&1; then
    new_hash=$(printf '%s' "$new_pass" | openssl passwd -6 -stdin 2> /dev/null)
  fi
  if [[ -z "$new_hash" ]]; then
    new_hash=$(printf '%s' "$new_pass" | sha256sum 2> /dev/null | awk '{print $1}')
  fi

  if [[ -z "$new_hash" ]]; then
    print -u2 "passwd: Authentication token manipulation error"
    return 1
  fi

  local shadow_dir="${shadow_file:h}"
  mkdir -p "$shadow_dir" 2> /dev/null
  local tmp_file=""
  tmp_file=$(mktemp "$shadow_dir/shadow.XXXXXX" 2> /dev/null || mktemp "${TMPDIR:-/tmp}/shadow.XXXXXX" 2> /dev/null)

  local cur_epoch=${EPOCHSECONDS:-0}
  if (( cur_epoch == 0 )); then
    cur_epoch=$(date +%s 2> /dev/null || echo 0)
  fi
  local days_since_epoch=$(( cur_epoch / 86400 ))
  local shadow_entry="$target_user:$new_hash:$days_since_epoch:0:99999:7:::"

  if [[ -f "$shadow_file" ]]; then
    local updated=0
    local line=""
    while IFS= read -r line || [[ -n "$line" ]]; do
      local u="${line%%:*}"
      if [[ "$u" == "$target_user" ]]; then
        print -r -- "$shadow_entry" >> "$tmp_file"
        updated=1
      elif [[ -n "$line" ]]; then
        print -r -- "$line" >> "$tmp_file"
      fi
    done < "$shadow_file"
    if (( updated == 0 )); then
      print -r -- "$shadow_entry" >> "$tmp_file"
    fi
  else
    print -r -- "$shadow_entry" > "$tmp_file"
  fi

  chmod 600 "$tmp_file"
  mv -f "$tmp_file" "$shadow_file"

  local termux_passwd="${PREFIX:-/data/data/com.termux/files/usr}/bin/passwd"
  if [[ -x "$termux_passwd" ]]; then
    printf '%s\n%s\n' "$new_pass" "$new_pass" | command "$termux_passwd" > /dev/null 2>&1 || true
  fi

  local _sudo_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/muxrc"
  rm -f "$_sudo_cache_dir/sudo_ts" 2> /dev/null

  local _sudo_cfg_dir="${XDG_CONFIG_HOME:-$HOME/.config}/muxrc"
  rm -f "$_sudo_cfg_dir/sudo_hash" "$HOME/.sudo_hash" 2> /dev/null || true

  print "passwd: password updated successfully"
  return 0
}
