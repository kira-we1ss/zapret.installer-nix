#!/bin/sh

set -e  

install_dependencies() {
    kernel="$(uname -s)"

    if [ "$kernel" = "Linux" ]; then
        [ -f /etc/os-release ] && . /etc/os-release || { echo "Не удалось определить ОС"; exit 1; }

        SUDO="${SUDO:-}"

        find_package_manager() {
            case "$1" in
                arch|artix|cachyos|endeavouros|manjaro|garuda) echo "$SUDO pacman -Syu --noconfirm && $SUDO pacman -S --noconfirm --needed git" ;;
                debian|ubuntu|mint) echo "$SUDO apt update -y && $SUDO apt install -y git" ;;
                fedora|almalinux|rocky|rhel|centos|oracle|redos) echo "if command -v dnf >/dev/null 2>&1; then $SUDO dnf update -y && $SUDO dnf install -y git; else $SUDO yum makecache -y && $SUDO yum install -y git; fi" ;;
                void)      echo "$SUDO xbps-install -S && $SUDO xbps-install -y git" ;;
                gentoo)    echo "$SUDO emerge --sync --quiet && $SUDO emerge --ask=n dev-vcs/git app-shells/bash" ;;
                opensuse)  echo "$SUDO zypper refresh && $SUDO zypper install git" ;;
                openwrt)   echo "$SUDO opkg update && $SUDO opkg install git git-http bash" ;;
                altlinux)  echo "$SUDO apt-get update -y && $SUDO apt-get install -y git bash" ;;
                alpine)    echo "$SUDO apk update && $SUDO apk add git bash" ;;
                nixos)     echo "" ;;  # git is available via nix-shell; skip
                *)         echo "" ;;
            esac
        }

        install_cmd="$(find_package_manager "$ID")"
        if [ -z "$install_cmd" ] && [ -n "$ID_LIKE" ]; then
            for like in $ID_LIKE; do
                install_cmd="$(find_package_manager "$like")" && [ -n "$install_cmd" ] && break
            done
        fi

        if [ -n "$install_cmd" ]; then
            eval "$install_cmd"
        elif [ "${ID:-}" != "nixos" ]; then
            echo "Неизвестная ОС: ${ID:-Неизвестно}"
            echo "Установите git и bash самостоятельно."
            sleep 2
        fi
    elif [ "$kernel" = "Darwin" ]; then
        echo "macOS не поддерживается на данный момент."
        exit 1
    else
        echo "Неизвестная ОС: $kernel"
        echo "Установите git и bash самостоятельно."
        sleep 2
    fi
}

if [ "$(awk '$2 == "/" {print $4}' /proc/mounts)" = "ro" ]; then
    echo "Файловая система только для чтения, не могу продолжать."
    exit 1
fi

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

# Detect NixOS and choose the installer directory accordingly.
OS_ID=""
[ -f /etc/os-release ] && OS_ID=$(. /etc/os-release && echo "${ID:-}")

if [ "$OS_ID" = "nixos" ]; then
    INSTALLER_DIR="/var/lib/zapret.installer"
else
    INSTALLER_DIR="/opt/zapret.installer"
fi

if ! command -v git > /dev/null 2>&1; then
    if [ "$OS_ID" = "nixos" ]; then
        echo "git не найден. На NixOS выполните:"
        echo "  nix-shell -p git --run 'sh -c \"\$(curl -fsSL <url>)\"'"
        echo "или добавьте git в environment.systemPackages и повторите."
        exit 1
    fi
    install_dependencies
fi

# Resolve the directory that contains this installer.sh.
# POSIX sh does not have BASH_SOURCE, so we use $0.
SELF_DIR=$(cd "$(dirname "$0")" && pwd)

if [ -f "$SELF_DIR/zapret-control.sh" ]; then
    # Running from inside the repo — use it in place; no copy needed.
    INSTALLER_DIR="$SELF_DIR"
else
    # Running via curl | sh — clone or update from the remote.
    if [ ! -d "$INSTALLER_DIR" ]; then
        $SUDO git clone https://github.com/kira-we1ss/zapret.installer-nix.git "$INSTALLER_DIR"
    else
        if ! (cd "$INSTALLER_DIR" && $SUDO git pull); then
            echo "Ошибка при обновлении. Удаляю репозиторий и клонирую заново..."
            $SUDO rm -rf "$INSTALLER_DIR"
            $SUDO git clone https://github.com/kira-we1ss/zapret.installer-nix.git "$INSTALLER_DIR"
        fi
    fi
fi

chmod +x "$INSTALLER_DIR/zapret-control.sh"
exec bash "$INSTALLER_DIR/zapret-control.sh"
