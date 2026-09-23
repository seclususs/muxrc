#####################
# Core Initialization
#####################
set -euo pipefail

CORE_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"

source "$CORE_DIR/colors.sh"
source "$CORE_DIR/logger.sh"
source "$CORE_DIR/formatter.sh"
