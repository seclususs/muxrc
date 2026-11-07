#####################
# File opener wrapper
#####################

xdg-open() {
  if command -v termux-open > /dev/null 2>&1; then
    command termux-open "$@"
  else
    echo "xdg-open: command not found. Please run: pkg install termux-tools"
    return 127
  fi
}
