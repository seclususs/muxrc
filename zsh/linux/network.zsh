############################
# Network diagnostic helpers
############################

ping() {
  local -a args=("$@")
  if [[ ! " ${args[*]} " =~ [[:space:]]-c[[:space:]] ]]; then
    args=(-c 4 "${args[@]}")
  fi

  if command ping "${args[@]}"; then
    return 0
  fi

  local code=$?
  if [[ -x /system/bin/ping ]] && /system/bin/ping "${args[@]}"; then
    return 0
  fi

  return $code
}

net-info() {
  command -v termux-wifi-connectioninfo > /dev/null 2>&1 || {
    echo "net-info: needs termux-api"
    return 1
  }
  command -v jq > /dev/null 2>&1 || {
    echo "net-info: needs jq"
    return 1
  }
  local ip=$(termux-wifi-connectioninfo | jq -r '.ip // empty')
  [[ -z "$ip" || "$ip" == null || "$ip" == "0.0.0.0" ]] && {
    echo "net-info: no wifi ip"
    return 1
  }
  local cmd="ssh ${USER:-$(whoami)}@${ip} -p 8022"
  echo "$cmd"
  command -v termux-toast > /dev/null 2>&1 && termux-toast "$cmd" || true
}
