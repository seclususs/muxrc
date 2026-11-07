#########################
# Package manager wrapper
#########################

apt() {
  if [[ "$1" =~ ^(install|search|update|upgrade|remove|autoremove|clean)$ ]]; then
    command pkg "$@"
  else
    command apt "$@"
  fi
}

apt-get() { apt "$@"; }
