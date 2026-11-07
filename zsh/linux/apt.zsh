#########################
# Package manager wrapper
#########################

apt() {
  case "$1" in
    install | reinstall | search | show | update | upgrade | remove | autoremove | clean | autoclean | files)
      command pkg "$@"
      ;;
    list)
      case "${2:-}" in
        --installed | -i)
          command pkg list-installed "${@:3}"
          ;;
        --all)
          command pkg list-all "${@:3}"
          ;;
        *)
          command apt "$@"
          ;;
      esac
      ;;
    *)
      command apt "$@"
      ;;
  esac
}

apt-get() { apt "$@"; }

apt-cache() {
  case "$1" in
    search | show)
      command pkg "$@"
      ;;
    *)
      command apt-cache "$@"
      ;;
  esac
}

