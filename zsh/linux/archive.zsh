#############################
# Universal archive extractor
#############################

ex() {
  if [[ $# -eq 0 ]]; then
    echo "usage: ex <archive_file>"
    return 1
  fi

  if [[ -f $1 ]]; then
    local target="${1:l}"
    case "$target" in
      *.tar.bz2) tar xjf "$1" ;;
      *.tar.gz) tar xzf "$1" ;;
      *.bz2) bunzip2 "$1" ;;
      *.rar) unrar x "$1" ;;
      *.gz) gunzip "$1" ;;
      *.tar) tar xf "$1" ;;
      *.tbz2) tar xjf "$1" ;;
      *.tgz) tar xzf "$1" ;;
      *.zip) unzip "$1" ;;
      *.z) uncompress "$1" ;;
      *.7z) 7z x "$1" ;;
      *.tar.xz | *.txz) tar xJf "$1" ;;
      *.xz) unxz "$1" ;;
      *)
        echo "ex: '$1' has unknown archive format."
        return 1
        ;;
    esac
  else
    echo "ex: '$1' is not a valid file."
    return 1
  fi
}
