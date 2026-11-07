###########################
# Clipboard history helpers
###########################

CLIP_HISTORY_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/muxrc/clip_history.log"
typeset -g _CLIP_LAST=""

clip-save() {
  mkdir -p "${CLIP_HISTORY_FILE:h}"
  local cur=$(termux-clipboard-get 2> /dev/null)
  [[ -z "$cur" ]] && return
  [[ "$cur" == "$_CLIP_LAST" ]] && return
  _CLIP_LAST="$cur"
  echo "$cur" >> "$CLIP_HISTORY_FILE"
}

clip-watch() {
  while true; do
    clip-save
    sleep 2
  done
}

clip-pick() {
  [[ -f "$CLIP_HISTORY_FILE" ]] || return 1
  local pick=$(tac "$CLIP_HISTORY_FILE" | fzf --prompt="clip> ")
  if [[ -n "$pick" ]]; then
    print -rn -- "$pick" | termux-clipboard-set
    command -v termux-toast > /dev/null 2>&1 && termux-toast "copied" || true
  fi
}
