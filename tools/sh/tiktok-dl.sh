#!/data/data/com.termux/files/usr/bin/bash

######################
# TikTok Media Utility
######################
set -euo pipefail
export LC_ALL=C

source "$(dirname "$(realpath "$0")")/../../lib/init.sh"

if [[ $# -lt 1 ]]; then
    log_error "usage: $(basename "$0") <live|post> [urls...]"
    exit 1
fi

mode="$1"
shift

if [[ "$mode" == "live" ]]; then
    url="${1:-}"
    if [[ -z "$url" ]]; then
        log_error "usage: $(basename "$0") live <tiktok_url>"
        exit 1
    fi
    
    username=$(echo "$url" | grep -oP '(?<=tiktok.com/@)[^/?]+' | head -n 1 || true)
    if [[ -z "$username" ]]; then
        username="unknown_user"
    fi
    base_dir="/storage/emulated/0/Download/ttdl/$username"
    mkdir -p "$base_dir"
    
    ua="Mozilla/5.0 (Linux; Android 13; SM-G998B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Mobile Safari/537.36"
    
    log_info "target: $url"
    log_info "saving to: $base_dir"
    log_info "recording... (ctrl+c to stop)"
    
    trap 'echo ""; log_success "recording stopped by user."; exit 0' SIGINT
    
    yt-dlp \
    --user-agent "$ua" \
    --no-warnings \
    --external-downloader-args ffmpeg:"-loglevel error -hide_banner" \
    -P "$base_dir" \
    "$url"
    
    log_success "recording stopped."
    exit 0
fi

if [[ "$mode" == "post" ]]; then
    trap '[[ -n "${SPINNER_PID:-}" ]] && kill -0 "$SPINNER_PID" 2>/dev/null && kill -9 "$SPINNER_PID" 2>/dev/null || true; echo -ne "\r\033[K"' EXIT
    
    for cmd in curl jq sed grep awk touch ffmpeg exiftool; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "$cmd is not installed. please install it."
            exit 1
        fi
    done
    
    if [[ $# -eq 0 ]]; then
        log_error "usage: $(basename "$0") post <url1> [url2 ...]"
        exit 1
    fi
    
    process_url() {
        local raw_url="$1"
        local url
        url=$(echo "$raw_url" | grep -oP 'https?://[^ ]+' || true)
        if [[ -z "$url" ]]; then
            log_error "invalid url format: $raw_url"
            return
        fi
        log_info "processing: $url"
        
        log_info "resolving url..."
        local final_url
        final_url=$(curl -s -L -o /dev/null -w %{url_effective} "$url" || true)
        
        local username
        username=$(echo "$final_url" | grep -oP '(?<=tiktok.com/@)[^/?]+' | head -n 1 || true)
        if [[ -z "$username" ]]; then
            username="unknown_user"
        fi
        
        local video_id
        video_id=$(echo "$final_url" | grep -oP '(?<=/video/|/photo/)\d+' | head -n 1 || true)
        
        if [[ -z "$video_id" ]]; then
            log_error "could not extract video id from $final_url"
            return
        fi
        
        log_success "found user: $username, id: $video_id"
        
        log_info "fetching tiktok..."
        local tk_page
        tk_page=$(curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/127.0.0.0 Safari/537.36" "$final_url" || true)
        
        local create_time
        create_time=$(echo "$tk_page" | grep -o 'id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>[^<]*' | sed 's/id="__UNIVERSAL_DATA_FOR_REHYDRATION__"[^>]*>//' | jq -r ".[\"__DEFAULT_SCOPE__\"][\"webapp.video-detail\"][\"itemInfo\"][\"itemStruct\"][\"createTime\"]" 2>/dev/null || true)
        
        if [[ -z "$create_time" ]] || [[ "$create_time" == "null" ]]; then
            create_time=$(echo "$tk_page" | grep -o 'id="sigi-state"[^>]*>[^<]*' | sed 's/id="sigi-state"[^>]*>//' | jq -r ".ItemModule[\"$video_id\"].createTime" 2>/dev/null || true)
        fi
        
        if [[ -z "$create_time" ]] || [[ "$create_time" == "null" ]]; then
            create_time=$(echo "$tk_page" | grep -o '"createTime":"\?[0-9]*"\?' | sed 's/[^0-9]//g' | head -n 1 || true)
        fi
        
        if [[ -z "$create_time" ]] || [[ "$create_time" == "0" ]]; then
            if [[ "$video_id" =~ ^[0-9]+$ ]]; then
                create_time=$(echo "$video_id" | awk '{printf "%d\n", $1 / 4294967296}')
                log_info "extracted createtime: $create_time"
            else
                create_time=""
                log_warn "could not find createtime"
            fi
        fi
        
        local iso_time=""
        local exif_time=""
        if [[ -n "$create_time" ]]; then
            if date --version >/dev/null 2>&1; then
                iso_time=$(date -u -d "@$create_time" +"%Y-%m-%dT%H:%M:%SZ")
                exif_time=$(date -d "@$create_time" +"%Y:%m:%d %H:%M:%S")
            else
                iso_time=$(date -u -r "$create_time" +"%Y-%m-%dT%H:%M:%SZ")
                exif_time=$(date -r "$create_time" +"%Y:%m:%d %H:%M:%S")
            fi
        fi
        
        log_info "requesting..."
        local cookie_file
        cookie_file=$(mktemp)
        
        local md_page
        md_page=$(curl -s -c "$cookie_file" -A "Mozilla/5.0" "https://musicaldown.com/en" || true)
        
        local action
        action=$(echo "$md_page" | grep -o '<form[^>]*action="[^"]*"' | sed 's/.*action="\([^"]*\)".*/\1/' | head -n 1 || true)
        local action_url="$action"
        if [[ "$action" == /* ]]; then
            action_url="https://musicaldown.com$action"
        fi
        
        local curl_args=("-s" "-L" "-b" "$cookie_file" "-e" "https://musicaldown.com/en" "-A" "Mozilla/5.0")
        while read -r input_tag; do
            local name type val
            name=$(echo "$input_tag" | grep -o 'name="[^"]*"' | sed 's/name="\([^"]*\)"/\1/' || true)
            type=$(echo "$input_tag" | grep -o 'type="[^"]*"' | sed 's/type="\([^"]*\)"/\1/' || true)
            val=$(echo "$input_tag" | grep -o 'value="[^"]*"' | sed 's/value="\([^"]*\)"/\1/' | sed 's/&amp;/\&/g' || true)
            
            [[ -z "$name" ]] && continue
            
            if [[ "$type" == "text" ]] || [[ "$type" == "url" ]]; then
                val="$final_url"
            fi
            
            curl_args+=("--data-urlencode" "$name=$val")
        done < <(echo "$md_page" | grep -o '<input[^>]*>' || true)
        
        local result
        result=$(curl "${curl_args[@]}" "$action_url" || true)
        rm -f "$cookie_file"
        
        local post_type="video"
        local dl_links=()
        
        if echo "$result" | grep -qi 'CONVERT VIDEO NOW'; then
            post_type="photo"
            while read -r href; do
                [[ -n "$href" ]] && dl_links+=("$href")
                done < <(echo "$result" | awk -v RS='<a ' '
            /Download/ && !/MP3/ && !/MP4/ {
                if (match($0, /href="[^"]*"/)) {
                    str = substr($0, RSTART + 6, RLENGTH - 7)
                    if (str ~ /fastdl\.muscdn\.app|tiktokcdn|p16/) {
                        print str
                    }
                }
            }')
            
            if [[ ${#dl_links[@]} -eq 0 ]]; then
                log_error "no photo download links found."
                return
            fi
        else
            local mp4_link
            mp4_link=$(echo "$result" | awk -v RS='<a ' '
            /Download MP4/ && /HD/ {
                if (match($0, /href="[^"]*"/)) {
                    print substr($0, RSTART + 6, RLENGTH - 7)
                }
            }' | head -n 1)
            
            if [[ -n "$mp4_link" ]]; then
                dl_links+=("$mp4_link")
            else
                log_error "hd download link not found."
                return
            fi
        fi
        
        local base_dir="/storage/emulated/0/Download/ttdl/$username"
        mkdir -p "$base_dir"
        
        if [[ "$post_type" == "video" ]]; then
            local target_file="$base_dir/${video_id}.mp4"
            
            if [[ -f "$target_file" ]]; then
                log_warn "video ${video_id} already exists, skipping."
            else
                local temp_raw="$base_dir/.temp_${video_id}.mp4"
                local dl_success=false
                while [[ "$dl_success" == false ]]; do
                    start_spinner "downloading video"
                    if curl -s -L -o "$temp_raw" "${dl_links[0]}"; then
                        stop_spinner "success" "downloaded video"
                        dl_success=true
                        if [[ -n "$create_time" ]]; then
                            log_info "applying metadata..."
                            if ffmpeg -y -i "$temp_raw" -c copy -metadata creation_time="$iso_time" -v error "$target_file"; then
                                rm -f "$temp_raw"
                                exiftool -overwrite_original -AllDates="$exif_time" "$target_file" >/dev/null 2>&1 || true
                                touch -d "@$create_time" "$target_file" || true
                                log_success "saved: $target_file"
                            else
                                log_error "failed to apply metadata, saving raw file"
                                mv "$temp_raw" "$target_file"
                                exiftool -overwrite_original -AllDates="$exif_time" "$target_file" >/dev/null 2>&1 || true
                                touch -d "@$create_time" "$target_file" || true
                            fi
                        else
                            mv "$temp_raw" "$target_file"
                            log_success "saved: $target_file"
                        fi
                    else
                        stop_spinner "error" "failed to download video"
                        rm -f "$temp_raw"
                        log_prompt "retry download video for ${video_id}? [Y/n]: "
                        local retry
                        read -r retry
                        if [[ "${retry:-y}" =~ ^[Nn]$ ]]; then
                            log_warn "skipping video ${video_id}"
                            break
                        fi
                    fi
                done
            fi
            
            elif [[ "$post_type" == "photo" ]]; then
            local idx=1
            for link in "${dl_links[@]}"; do
                local target_file="$base_dir/${video_id}_s${idx}.jpg"
                
                if [[ -f "$target_file" ]]; then
                    log_warn "photo ${idx} for ${video_id} already exists, skipping."
                    idx=$((idx + 1))
                    continue
                fi
                
                local temp_raw="$base_dir/.temp_${video_id}_s${idx}.jpg"
                local dl_success=false
                while [[ "$dl_success" == false ]]; do
                    start_spinner "downloading photo $idx"
                    if curl -s -L -o "$temp_raw" "$link"; then
                        stop_spinner "success" "downloaded photo $idx"
                        dl_success=true
                        mv "$temp_raw" "$target_file"
                        if [[ -n "$create_time" ]]; then
                            local slide_time=$((create_time + idx - 1))
                            local slide_exif=""
                            if date --version >/dev/null 2>&1; then
                                slide_exif=$(date -d "@$slide_time" +"%Y:%m:%d %H:%M:%S")
                            else
                                slide_exif=$(date -r "$slide_time" +"%Y:%m:%d %H:%M:%S")
                            fi
                            exiftool -overwrite_original -AllDates="$slide_exif" "$target_file" >/dev/null 2>&1 || true
                            touch -d "@$slide_time" "$target_file" || true
                        fi
                        log_success "saved: $target_file"
                    else
                        stop_spinner "error" "failed to download photo $idx"
                        rm -f "$temp_raw"
                        log_prompt "retry download photo $idx for ${video_id}? [Y/n]: "
                        local retry
                        read -r retry
                        if [[ "${retry:-y}" =~ ^[Nn]$ ]]; then
                            log_warn "skipping photo $idx"
                            break
                        fi
                    fi
                done
                idx=$((idx + 1))
            done
        fi
        log_info "done processing $video_id"
    }
    
    for arg in "$@"; do
        if [[ -f "$arg" ]]; then
            while IFS= read -u 3 -r line || [[ -n "$line" ]]; do
                [[ -n "$line" ]] && process_url "$line"
            done 3< "$arg"
        else
            process_url "$arg"
        fi
    done
    exit 0
fi

log_error "invalid mode: $mode"
exit 1
