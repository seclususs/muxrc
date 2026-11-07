########################
# Safe trash and untrash
########################

TRASH_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"

trash() {
  if [[ $# -eq 0 ]]; then
    echo "usage: trash <file> [file...]"
    return 1
  fi

  mkdir -p "$TRASH_DIR"
  local f
  for f in "$@"; do
    [[ -e "$f" || -L "$f" ]] || {
      echo "trash: no such file: $f"
      continue
    }
    local ts
    ts=$(date +%s)
    local dest="$TRASH_DIR/${f:t}.${ts}"
    local counter=1
    while [[ -e "$dest" ]]; do
      dest="$TRASH_DIR/${f:t}.${ts}.${counter}"
      ((counter++))
    done
    mv -- "$f" "$dest"
  done
}

untrash() {
  local search_dirs=()
  [[ -d "$TRASH_DIR" ]] && search_dirs+=("$TRASH_DIR")
  [[ -d "$HOME/.trash" && "$HOME/.trash" != "$TRASH_DIR" ]] && search_dirs+=("$HOME/.trash")
  local item
  item=$(for d in "${search_dirs[@]}"; do ls -1t "$d" 2> /dev/null; done | fzf --prompt="restore> ") || return
  if [[ -n "$item" ]]; then
    local orig_name="${item%.*}"
    if [[ "$item" =~ '\.[0-9]+\.[0-9]+$' ]]; then
      orig_name="${orig_name%.*}"
    fi
    local target_dest="./${orig_name}"
    if [[ -e "$target_dest" ]]; then
      local confirm=""
      read -q "confirm?target '$target_dest' already exists in current directory. overwrite? [y/N] "
      echo ""
      [[ "$confirm" =~ ^[Yy]$ ]] || return 1
    fi

    if [[ -e "$TRASH_DIR/$item" ]]; then
      mv -- "$TRASH_DIR/$item" "$target_dest"
    elif [[ -e "$HOME/.trash/$item" ]]; then
      mv -- "$HOME/.trash/$item" "$target_dest"
    fi
  fi
}
