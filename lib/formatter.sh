###########
# Formatter
###########

#######################################
# Truncates string to fit Termux bounds
#######################################
format_truncate() {
    local text="$1"
    local max_len="${2:-60}"
    
    if [[ ${#text} -gt $max_len ]]; then
        echo "${text:0:$max_len}..."
    else
        echo "$text"
    fi
}
