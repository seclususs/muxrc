#!/data/data/com.termux/files/usr/bin/bash

########################
# Duplicate File Cleaner
########################
set -euo pipefail

fdupes -rd "$1"
