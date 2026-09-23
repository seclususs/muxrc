###################
# Logging Functions
###################

log_info() { print -P -n "%F{blue}[*]%f "; print -r -- "$*" }
log_success() { print -P -n "%F{green}[+]%f "; print -r -- "$*" }
log_warn() { print -P -n "%F{yellow}[-]%f "; print -r -- "$*" }
log_error() { print -u2 -P -n "%F{red}[!]%f "; print -u2 -r -- "$*" }

########################
# Duplicate File Cleaner
########################
clean-dupes() {
    if [[ $# -eq 0 ]]; then
        log_error "usage: clean-dupes <target_directory>"
        return 1
    fi
    
    local target_dir="$1"
    
    if [[ ! -d "$target_dir" ]]; then
        log_error "directory '$target_dir' not found"
        return 1
    fi
    
    if [[ ! -r "$target_dir" ]]; then
        log_error "directory '$target_dir' is not readable"
        return 1
    fi
    
    bash "$HOME/muxrc/tools/sh/clean-dupes.sh" "$target_dir"
}

#######################
# EXIF Metadata Cleaner
#######################
clean-meta() {
    if [[ $# -eq 0 ]]; then
        log_error "usage: clean-meta <target_directory>"
        return 1
    fi
    
    local target_dir="$1"
    
    if [[ ! -d "$target_dir" ]]; then
        log_error "directory '$target_dir' not found"
        return 1
    fi
    
    log_info "cleaning metadata..."
    local err_file
    err_file=$(mktemp)
    
    bash "$HOME/muxrc/tools/sh/exif-cleaner.sh" "$target_dir" 2> "$err_file"
    
    if [[ -s "$err_file" ]]; then
        log_warn "warning summary:"
        cat "$err_file"
    fi
    rm -f "$err_file"
    
    log_success "done. output saved to ~/muxrc/tools/output/stripped/"
}

#####################
# Steganography Vault
#####################
stego-vault() {
    bash "$HOME/muxrc/tools/sh/steganography.sh"
}

##############
# File Renamer
##############
rename-by-date() {
    if [[ $# -lt 2 ]]; then
        log_error "usage: rename-by-date <directory> <prefix>"
        return 1
    fi
    
    local target_dir="$1"
    local prefix="$2"
    
    if [[ ! -d "$target_dir" ]]; then
        log_error "directory '$target_dir' not found"
        return 1
    fi
    
    bash "$HOME/muxrc/tools/sh/file-renamer.sh" "$target_dir" "$prefix"
}

##############
# EXIF Spoofer
##############
spoof-meta() {
    if [[ $# -lt 2 ]]; then
        log_error "usage: spoof-meta <preset_name> <image_file>"
        return 1
    fi
    
    local preset_name="$1"
    local image_file="$2"
    local preset_file="$HOME/muxrc/tools/presets/${preset_name}.json"
    
    if [[ ! -f "$preset_file" ]]; then
        log_error "preset '$preset_name' not found"
        return 1
    fi
    
    if [[ ! -f "$image_file" ]]; then
        log_error "image file '$image_file' not found"
        return 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq not installed. run: pkg install jq"
        return 1
    fi
    
    bash "$HOME/muxrc/tools/sh/exif-spoofer.sh" "$preset_file" "$image_file"
}

########################
# Binary Media Encrypter
########################
media-crypt() {
    if [[ $# -eq 0 ]]; then
        log_error "usage: media-crypt <target_file>"
        return 1
    fi
    
    local target_file="$1"
    
    if [[ ! -f "$target_file" ]]; then
        log_error "file '$target_file' not found"
        return 1
    fi
    
    local pass1 pass2
    read -rs "pass1?enter encryption password: "
    print -u2 ""
    read -rs "pass2?confirm password: "
    print -u2 ""
    
    if [[ -z "$pass1" ]]; then
        log_error "password cannot be empty"
        return 1
    fi
    
    if [[ "$pass1" != "$pass2" ]]; then
        log_error "passwords do not match"
        return 1
    fi
    
    MUXRC_CRYPT_PASS="$pass1" bash "$HOME/muxrc/tools/sh/encrypter.sh" "$target_file"
}

##########################
# Permanent Media Shredder
##########################
shred-file() {
    if [[ $# -eq 0 ]]; then
        log_error "usage: shred-file <file_path>"
        return 1
    fi
    
    local target_file="$1"
    
    if [[ ! -f "$target_file" ]]; then
        log_error "file '$target_file' not found"
        return 1
    fi
    
    if ! command -v shred >/dev/null 2>&1; then
        log_error "coreutils not installed. run: pkg install coreutils"
        return 1
    fi
    
    bash "$HOME/muxrc/tools/sh/shredder.sh" "$target_file"
}

###########################
# Local Network ARP Sweeper
###########################
net-sweep() {
    if ! command -v nmap >/dev/null 2>&1; then
        log_error "nmap not installed. run: pkg install nmap"
        return 1
    fi
    
    local cidr
    cidr=$(ip route show 2>/dev/null | grep -v 'default' | grep -vE 'dev (lo|tun|tap|wg)' | awk '{print $1}' | head -n 1)
    
    if [[ -z "$cidr" ]] && command -v sudo >/dev/null 2>&1; then
        log_info "auto-detecting subnet requires root..."
        cidr=$(sudo ip route show 2>/dev/null | grep -v 'default' | grep -vE 'dev (lo|tun|tap|wg)' | awk '{print $1}' | head -n 1)
    fi
    
    if [[ -z "$cidr" ]]; then
        log_error "could not auto-detect valid local subnet"
        return 1
    fi
    
    log_info "executing arp sweep on $cidr..."
    if command -v sudo >/dev/null 2>&1; then
        sudo bash "$HOME/muxrc/tools/sh/arp-sweeper.sh" "$cidr"
    else
        bash "$HOME/muxrc/tools/sh/arp-sweeper.sh" "$cidr"
    fi
}

###################
# Tor Privacy Setup
###################
tor-start() {
    local pid_file="$HOME/.muxrc/run/tor.pid"
    
    if ! command -v tor >/dev/null 2>&1; then
        log_error "tor not installed. run: pkg install tor"
        return 1
    fi
    
    if [[ -f "$pid_file" ]]; then
        local tpid
        tpid=$(cat "$pid_file" 2>/dev/null)
        if kill -0 "$tpid" 2>/dev/null; then
            log_error "tor already running pid: $tpid. use tor-stop first"
            return 1
        else
            log_warn "found stale pid file. cleaning up..."
            bash "$HOME/muxrc/tools/sh/tor-setup.sh" stop
        fi
    fi
    
    bash "$HOME/muxrc/tools/sh/tor-setup.sh" start
}

tor-stop() {
    bash "$HOME/muxrc/tools/sh/tor-setup.sh" stop
}

######################
# TikTok Live Recorder
######################
ttdl-live() {
    if [[ $# -eq 0 ]]; then
        log_error "usage: ttdl-live <username>"
        return 1
    fi
    
    local username="$1"
    username="${username#@}"
    local url="https://www.tiktok.com/@${username}/live"
    
    if ! command -v yt-dlp >/dev/null 2>&1; then
        log_error "yt-dlp not installed. run: pkg install yt-dlp"
        return 1
    fi
    
    bash "$HOME/muxrc/tools/sh/tiktok-dl.sh" "$url"
}
