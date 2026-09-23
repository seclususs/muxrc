#!/data/data/com.termux/files/usr/bin/bash

######################
# TikTok Live Recorder
######################
set -euo pipefail

url="${1:-}"
if [[ -z "$url" ]]; then
    echo "Usage: $(basename "$0") <tiktok_url>"
    exit 1
fi

ua="Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36"

echo "[*] Target: $url"
echo "[*] Recording in progress... press Ctrl+C to stop"

yt-dlp \
--user-agent "$ua" \
--no-warnings \
--external-downloader-args ffmpeg:"-loglevel error -hide_banner" \
"$url"

echo "[+] Recording stopped."
