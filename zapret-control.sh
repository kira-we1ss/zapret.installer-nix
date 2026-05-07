#!/bin/bash

# Always derive INSTALLER_DIR from the location of this script itself.
# This works regardless of OS, install path, or how the script was invoked.
INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$INSTALLER_DIR/files/utils.sh"
source "$INSTALLER_DIR/files/config.sh"
source "$INSTALLER_DIR/files/init.sh"
source "$INSTALLER_DIR/files/menu.sh"
source "$INSTALLER_DIR/files/service.sh"
source "$INSTALLER_DIR/files/install.sh"

# Now that utils.sh is sourced, run the full detect_nixos() which sets all
# path variables used by the rest of the scripts.
detect_nixos

set -e  

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    if command -v sudo > /dev/null 2>&1; then
        SUDO="sudo"
    elif command -v doas > /dev/null 2>&1; then
        SUDO="doas"
    else
        echo "Скрипт не может быть выполнен не от имени суперпользователя."
        exit 1
    fi
fi

if [[ $EUID -ne 0 ]]; then
    exec $SUDO bash "$0" "$@"
fi
trap fast_exit SIGINT
check_openwrt
check_tput
$TPUT_B
check_fs
detect_init
remote_latest_version
main_menu
