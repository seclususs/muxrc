#########
# Loggers
#########

log_info() {
    echo -e "${C_BLUE}[*]${C_RESET} $*"
}

log_success() {
    echo -e "${C_GREEN}[+]${C_RESET} $*"
}

log_warn() {
    echo -e "${C_YELLOW}[-]${C_RESET} $*"
}

log_error() {
    echo -e "${C_RED}[!]${C_RESET} $*" >&2
}
