#!/data/data/com.termux/files/usr/bin/bash

##################
# Termux installer
##################
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
source "$SCRIPT_DIR/lib/init.sh"

trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT

log_info "requesting android storage permission..."
termux-setup-storage
sleep 2

log_info "enabling extra repositories..."
pkg update -y
pkg install -y root-repo x11-repo
pkg upgrade -y

log_info "installing packages..."
pkg install -y zsh git wget curl ncurses-utils bc coreutils findutils grep sed gawk jq termux-exec termux-api termux-services nano fzf openssh unzip tar p7zip unrar exiftool steghide openssl-tool nmap tor yt-dlp ffmpeg

DOTFILES_DIR="$HOME/muxrc"
ZSH_DIR="$HOME/.zsh"
ZSH_PLUGINS_DIR="$ZSH_DIR/plugins"

mkdir -p "$ZSH_PLUGINS_DIR"
mkdir -p "$HOME/.termux"
mkdir -p "$DOTFILES_DIR/nano"

log_info "muting default termux motd..."
touch "$HOME/.hushlogin"

log_info "setting up sudo wrapper..."
if [[ -f "$HOME/.sudo_hash" ]]; then
    log_prompt "sudo password already configured. overwrite? [y/N]: "
    read -r reset_sudo
else
    reset_sudo="y"
fi

if [[ "${reset_sudo:-}" =~ ^[Yy]$ ]]; then
    log_prompt "create your sudo password: "
    read -r -s SUDO_PASS
    echo ""
    log_prompt "confirm sudo password: "
    read -r -s SUDO_PASS_CONFIRM
    echo ""
    
    if [[ "$SUDO_PASS" == "$SUDO_PASS_CONFIRM" ]]; then
        echo -n "$SUDO_PASS" | sha256sum | awk '{print $1}' > "$HOME/.sudo_hash"
        chmod 600 "$HOME/.sudo_hash"
        log_success "sudo hash generated successfully."
    else
        log_error "passwords do not match. run installer again to fix."
    fi
else
    log_warn "keeping existing sudo password."
fi

log_info "fetching zsh plugins..."
declare -A PLUGINS=(
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions.git"
    ["zsh-completions"]="https://github.com/zsh-users/zsh-completions.git"
    ["zsh-history-substring-search"]="https://github.com/zsh-users/zsh-history-substring-search.git"
    ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab.git"
)

for PLUGIN in "${!PLUGINS[@]}"; do
    if [ ! -d "$ZSH_PLUGINS_DIR/$PLUGIN" ]; then
        start_spinner "cloning $PLUGIN"
        if git clone -q --depth 1 "${PLUGINS[$PLUGIN]}" "$ZSH_PLUGINS_DIR/$PLUGIN"; then
            stop_spinner "success" "cloned $PLUGIN"
        else
            stop_spinner "error" "failed to clone $PLUGIN"
        fi
    else
        start_spinner "updating $PLUGIN"
        if git -C "$ZSH_PLUGINS_DIR/$PLUGIN" pull -q --rebase; then
            stop_spinner "success" "updated $PLUGIN"
        else
            stop_spinner "error" "failed to update $PLUGIN"
        fi
    fi
done

log_info "creating storage symlinks..."
declare -A STORAGE_DIRS=(
    ["Workspace"]="/storage/emulated/0/Workspace"
)

for NAME in "${!STORAGE_DIRS[@]}"; do
    TARGET="${STORAGE_DIRS[$NAME]}"
    if [ ! -d "$TARGET" ]; then
        mkdir -p "$TARGET"
        log_success "created $TARGET"
    else
        log_warn "$TARGET already exists, skipping creation."
    fi
    ln -sfn "$TARGET" "$HOME/$NAME"
done

log_info "symlinking configurations..."
ln -sf "$DOTFILES_DIR/zsh/.zshrc" "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/colors/.dircolors" "$HOME/.dircolors"
ln -sf "$DOTFILES_DIR/termux/colors.properties" "$HOME/.termux/colors.properties"
ln -sf "$DOTFILES_DIR/termux/termux.properties" "$HOME/.termux/termux.properties"
ln -sf "$DOTFILES_DIR/nano/.nanorc" "$HOME/.nanorc"

mkdir -p "$HOME/.termux/boot"
ln -sf "$DOTFILES_DIR/boot/start-sshd" "$HOME/.termux/boot/start-sshd"
chmod +x "$DOTFILES_DIR/boot/start-sshd"

mkdir -p "$HOME/.shortcuts"
ln -sf "$DOTFILES_DIR/shortcuts/backup.sh" "$HOME/.shortcuts/backup.sh"
chmod +x "$DOTFILES_DIR/shortcuts/backup.sh"

if [ ! -f "$HOME/.termux/font.ttf" ]; then
    log_info "installing jetbrains mono nerd font..."
    wget -q --show-progress -O "$HOME/.termux/font.ttf" "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.4.0/patched-fonts/JetBrainsMono/Ligatures/Regular/JetBrainsMonoNerdFont-Regular.ttf"
else
    log_warn "jetbrains mono nerd font already installed, skipping."
fi

termux-reload-settings

if [[ "$SHELL" != */zsh ]]; then
    log_info "changing default shell to zsh..."
    chsh -s zsh
fi

log_info "setting up gemini auto-correct..."
if [[ -f "$HOME/.gemini_ai_env" ]]; then
    log_prompt "gemini config already exists. overwrite? [y/N]: "
    read -r reset_gemini
else
    reset_gemini="y"
fi

if [[ "${reset_gemini:-}" =~ ^[Yy]$ ]]; then
    log_prompt "set up gemini auto-correct now? [y/N]: "
    read -r ENABLE_AI
    if [[ "${ENABLE_AI:-}" =~ ^[Yy]$ ]]; then
        log_prompt "gemini api key: "
        read -r -s GEMINI_KEY
        echo
        {
            echo "GEMINI_API_KEY=\"$GEMINI_KEY\""
            echo "GEMINI_MODEL=\"gemini-3.5-flash-lite\""
            echo "AI_AUTOCORRECT_ENABLED=1"
        } > "$HOME/.gemini_ai_env"
        chmod 600 "$HOME/.gemini_ai_env"
        log_success "gemini configuration saved."
    fi
else
    log_warn "keeping existing gemini configuration."
fi

grep -qxF '.gemini_ai_env' "$DOTFILES_DIR/.gitignore" || echo '.gemini_ai_env' >> "$DOTFILES_DIR/.gitignore"

log_success "installation complete! please restart your termux session."
trap - EXIT
