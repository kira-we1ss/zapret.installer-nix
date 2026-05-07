#!/bin/bash

# ---------------------------------------------------------------------------
# Path variables — set by detect_nixos(), used everywhere else.
# Defaults are the traditional /opt layout for non-NixOS systems.
# ---------------------------------------------------------------------------
NIXOS=false
ZAPRET_DIR=/opt/zapret
# INSTALLER_DIR is set by zapret-control.sh before sourcing this file.
# Only fall back to the default if it wasn't already set.
INSTALLER_DIR="${INSTALLER_DIR:-/opt/zapret.installer}"
ZAPRET_VER_FILE=/opt/zapret-ver

detect_nixos() {
    if [ -f /etc/os-release ]; then
        local _id
        _id=$(. /etc/os-release && echo "${ID:-}")
        if [ "$_id" = "nixos" ]; then
            NIXOS=true
            ZAPRET_DIR=/var/lib/zapret
            INSTALLER_DIR="${INSTALLER_DIR:-/var/lib/zapret.installer}"
            ZAPRET_VER_FILE=/var/lib/zapret/version
        fi
    fi
}

error_exit() {
    $TPUT_E
    echo -e "\e[31mОшибка:\e[0m $1" >&2
    exit 1
}

check_fs() {
    if [ "$(awk '$2 == "/" {print $4}' /proc/mounts)" = "ro" ]; then
        error_exit "файловая система только для чтения, не могу продолжить."
    fi
}

exists() {
    which "$1" >/dev/null 2>/dev/null
}

existf() {
    type "$1" >/dev/null 2>/dev/null
}

whichq() {
    which $1 2>/dev/null
}

check_openwrt() {
    if grep -q '^ID="openwrt"$' /etc/os-release; then
        SYSTEM=openwrt
    fi
}

check_tput() {
    if command -v tput &>/dev/null; then
        TPUT_B="tput smcup"
        TPUT_E="tput rmcup"
    else
        TPUT_B=""
        TPUT_E=""
    fi
}

is_network_error() {
    local log="$1"
    echo "$log" | grep -qiE "timed out|recv failure|unexpected disconnect|early EOF|RPC failed|curl.*recv"
}

try_again() {
    local error_message="$1"
    shift

    local -a command=("$@")
    local attempt=0
    local max_attempts=3
    local success=0

    while (( attempt < max_attempts )); do
        ((attempt++))

        (( attempt > 1 )) && echo -e "\e[33mПопытка $attempt из $max_attempts...\e[0m"

        output=$("${command[@]}" 2>&1) && success=1 && break

        if ! is_network_error "$output"; then
            echo "$output" >&2
            error_exit "не удалось склонировать репозиторий."
        fi
        sleep 2
    done

    (( success == 0 )) && error_exit "$error_message"
}

open_editor() {
    local file_path="$1"
    if [ ! -f "$file_path" ]; then
        error_exit "Не найден файл '$file_path'"
    fi

    local editors_list=("$EDITOR" "$VISUAL" "nano" "vim" "nvim" "helix")
    for editor in ${editors_list[@]}; do
        if command -v "$editor"; then
            "$editor" "$file_path"
            return
        fi
    done

    echo "Не найдено ни одного текстового редактора из списка:"
    echo "${editors_list[@]}"
    echo "Установите один из вышеперечисленных редакторов"
    echo ""
    echo "Возврат в главное меню через 5 секунд..."
    sleep 5
}

fast_exit(){
    $TPUT_E
    echo "Выход по запросу пользователя"
    exit 1
}
