#!/usr/bin/env bash

#####################
# Core Initialization
#####################
set -euo pipefail

LIB_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]:-$0}")")"
source "$LIB_DIR/colors.sh"
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/formatter.sh"
