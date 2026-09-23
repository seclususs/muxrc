#!/data/data/com.termux/files/usr/bin/bash

######################
# TikTok Live Recorder
######################
set -euo pipefail

source "$(dirname "$(realpath "$0")")/_core/init.sh"

url="${1:-}"
if [[ -z "$url" ]]; then
    log_error "Usage: $(basename "$0") <tiktok_url>"
    exit 1
fi

ua="Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36"

log_info "Target: $url"
log_info "Recording in progress... press Ctrl+C to stop"

yt-dlp \
--user-agent "$ua" \
--no-warnings \
--external-downloader-args ffmpeg:"-loglevel error -hide_banner" \
"$url"

log_success "Recording stopped."
