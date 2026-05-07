#!/bin/bash


remote_latest_version() {
    rver=$(timeout 10s curl -s https://api.github.com/repos/bol-van/zapret/releases/latest | \
          grep "tag_name" | \
          cut -d '"' -f 4 | \
          sed 's/^v//')
}

get_latest_version() {
    if [ -z "$rver" ]; then
        rver=$(timeout 10s curl -s -I https://github.com/bol-van/zapret/releases/latest | grep -i "location:" | cut -d' ' -f2 | tr -d '\r' | grep -o "tag/v[0-9.]\+" | cut -d'/' -f2 | sed 's/^v//')
        if [ -z "$rver" ]; then
            #error_exit "не удалось определить последнюю версию запрета. Проверьте соединение с сетью."
            echo "Неизвестно"
        else
            echo "$rver"
        fi
    else
        echo "$rver"
    fi
}

# ---------------------------------------------------------------------------
# Helper: ask the user whether to run nixos-rebuild switch automatically.
# Runs it if the user agrees; otherwise prints the command.
# ---------------------------------------------------------------------------
_nixos_rebuild_prompt() {
    echo ""
    read -p "Запустить 'nixos-rebuild switch' сейчас? [Y/n]: " _nrb_answer
    case "$_nrb_answer" in
        [Nn]*)
            echo ""
            echo -e "\e[33mВыполните вручную:\e[0m"
            echo "  sudo nixos-rebuild switch"
            echo ""
            ;;
        *)
            echo -e "\e[36mЗапускаю nixos-rebuild switch...\e[0m"
            nixos-rebuild switch || error_exit "nixos-rebuild switch завершился с ошибкой."
            ;;
    esac
}

download_zapret_release()
{

    rm -rf "$ZAPRET_DIR"
    rm -rf "${ZAPRET_DIR}-v$(get_latest_version)"
    TEMP_DIR_BIN=$(mktemp -d)
    if [ SYSTEM = openwrt ]; then
        if ! curl -L -o "$TEMP_DIR_BIN/latest.tar.gz" $(curl -s https://api.github.com/repos/bol-van/zapret/releases/latest | grep "browser_download_url.*openwrt.*tar.gz" | head -n 1 | cut -d '"' -f 4); then
            rm -rf $TEMP_DIR_BIN
            error_exit "Не удалось получить релиз запрета."
        fi        
        if ! tar -xzf $TEMP_DIR_BIN/latest.tar.gz -C /opt/ --strip-components=1; then
            rm -rf $TEMP_DIR_BIN "${ZAPRET_DIR}-v$(get_latest_version)"
            error_exit "Не удалось разархивировать архив с релизом запрета."
        fi
    else
        curl -s https://api.github.com/repos/bol-van/zapret/releases/latest | grep "browser_download_url.*tar.gz" | grep -v "openwrt" | head -n 1 | cut -d '"' -f 4 | while read zurl; do curl -L -o "$TEMP_DIR_BIN/latest.tar.gz" "$zurl" || error_exit "не могу получить релиз запрета"; done
        if ! tar -xzf $TEMP_DIR_BIN/latest.tar.gz -C "$(dirname "$ZAPRET_DIR")/"; then
            rm -rf $TEMP_DIR_BIN "${ZAPRET_DIR}-v$(get_latest_version)"
            error_exit "Не удалось разархивировать архив с релизом запрета."
        fi
    fi
    mv "/opt/zapret-v$(get_latest_version)" "$ZAPRET_DIR" 2>/dev/null || \
        mv "$(dirname "$ZAPRET_DIR")/zapret-v$(get_latest_version)" "$ZAPRET_DIR"
    get_latest_version > "$ZAPRET_VER_FILE"
    echo "Клонирую репозиторий конфигураций..."
    git clone https://github.com/Snowy-Fluffy/zapret.cfgs "$ZAPRET_DIR/zapret.cfgs" || error_exit "не удалось получить репозиторий конфигураций. Вероятно это сетевая ошибка, попробуйте снова."
    echo "Клонирование успешно завершено."



}

download_zapret_git() {
    rm -rf "$ZAPRET_DIR"
    echo "Клонирую репозиторий bol-van/zapret..."
    git clone https://github.com/bol-van/zapret "$ZAPRET_DIR" || error_exit "не удалось получить запрет. Вероятно это сетевая ошибка, попробуйте снова."
    echo "git" > "$ZAPRET_VER_FILE"
    echo "Клонирую репозиторий конфигураций..."
    git clone https://github.com/Snowy-Fluffy/zapret.cfgs "$ZAPRET_DIR/zapret.cfgs" || error_exit "не удалось получить репозиторий конфигураций. Вероятно это сетевая ошибка, попробуйте снова."
    echo "Клонирование успешно завершено."
}


install_dependencies() {
    # On NixOS all dependencies are declared in the Nix derivation.
    if [ "$NIXOS" = true ]; then
        return 0
    fi

    kernel="$(uname -s)"
    if [ "$kernel" = "Linux" ]; then
        . /etc/os-release
        declare -A command_by_ID=(
            ["arch"]="pacman -S --noconfirm --needed ipset "
            ["artix"]="pacman -S --noconfirm --needed ipset "
            ["cachyos"]="pacman -S --noconfirm --needed ipset "
            ["endeavouros"]="pacman -S --noconfirm --needed ipset "
            ["manjaro"]="pacman -S --noconfirm --needed ipset "
            ["debian"]="apt-get install -y iptables ipset "
            ["fedora"]="dnf install -y iptables ipset"
            ["ubuntu"]="apt-get install -y iptables ipset"
            ["mint"]="apt-get install -y iptables ipset"
            ["centos"]="yum install -y ipset iptables"
            ["void"]="xbps-install -y iptables ipset"
            ["gentoo"]="emerge --noreplace net-firewall/iptables net-firewall/ipset"
            ["opensuse"]="zypper install -y iptables ipset"
            ["openwrt"]="opkg install iptables ipset"
            ["altlinux"]="apt-get install -y iptables ipset"
            ["almalinux"]="dnf install -y iptables ipset"
            ["rocky"]="dnf install -y iptables ipset"
            ["alpine"]="apk add iptables ipset"
        )
        if [[ -v command_by_ID[$ID] ]]; then
            eval "${command_by_ID[$ID]}"
        else
            for like in $ID_LIKE; do
                if [[ -n "${command_by_ID[$like]}" ]]; then
                    eval "${command_by_ID[$like]}"
                    break
                fi
            done
        fi
    elif [ "$kernel" = "Darwin" ]; then
        error_exit "macOS не поддерживается на данный момент."
    else
        echo "Неизвестная ОС: ${kernel}. Установите iptables и ipset самостоятельно." bash -c 'read -p "Нажмите Enter для продолжения..."'
    fi
}

# ---------------------------------------------------------------------------
# NixOS install helper
# ---------------------------------------------------------------------------
_install_nixos() {
    echo -e "\e[36mУстановка Запрета на NixOS...\e[0m"

    # Create state directories
    mkdir -p "$ZAPRET_DIR/ipset"

    # Clone zapret.cfgs for interactive TUI use
    if [[ ! -d "$ZAPRET_DIR/zapret.cfgs" ]]; then
        echo "Клонирую репозиторий конфигураций..."
        git clone https://github.com/Snowy-Fluffy/zapret.cfgs "$ZAPRET_DIR/zapret.cfgs" \
            || error_exit "не удалось получить репозиторий конфигураций."
    fi

    # Copy NixOS files to /etc/nixos/
    local module_src="$INSTALLER_DIR/nix/module.nix"
    local package_src="$INSTALLER_DIR/nix/package.nix"
    if [[ ! -f "$module_src" ]]; then
        error_exit "Файл модуля не найден: $module_src"
    fi
    mkdir -p /etc/nixos/zapret
    cp "$module_src"  /etc/nixos/zapret/module.nix  \
        || error_exit "не удалось скопировать module.nix в /etc/nixos/zapret/"
    cp "$package_src" /etc/nixos/zapret/package.nix \
        || error_exit "не удалось скопировать package.nix в /etc/nixos/zapret/"

    # Get the latest zapret commit for pinning
    local zapret_rev
    zapret_rev=$(git ls-remote https://github.com/bol-van/zapret HEAD 2>/dev/null | cut -f1) || true

    cat > /etc/nixos/zapret/default.nix << NIXEOF
{ config, pkgs, lib, ... }:
{
  imports = [ ./module.nix ];
  config = lib.mkIf config.services.zapret.enable {
    services.zapret.package = lib.mkDefault (pkgs.callPackage ./package.nix {
      zapret-src = pkgs.fetchFromGitHub {
        owner = "bol-van";
        repo  = "zapret";
        rev   = "${zapret_rev:-REPLACE_WITH_COMMIT_SHA}";
        # Run: nix-prefetch-url --unpack https://github.com/bol-van/zapret/archive/${zapret_rev:-REPLACE_WITH_COMMIT_SHA}.tar.gz
        hash  = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
      };
    });
  };
}
NIXEOF

    echo ""
    echo -e "\e[32mМодуль скопирован в /etc/nixos/zapret/\e[0m"
    echo ""
    echo -e "\e[1;33m══════════════════════════════════════════════════════\e[0m"
    echo -e "\e[1;33m  Как подключить zapret к вашей конфигурации NixOS:\e[0m"
    echo -e "\e[1;33m══════════════════════════════════════════════════════\e[0m"
    echo ""
    echo -e "\e[1;36m── Вариант 1: Flakes (рекомендуется) ──\e[0m"
    echo ""
    echo -e "  1) В \e[1mflake.nix\e[0m → \e[1minputs\e[0m добавьте:"
    echo '       zapret.url = "github:kira-we1ss/zapret.installer-nix";'
    echo ""
    echo -e "  2) В \e[1moutputs\e[0m добавьте \e[1mzapret\e[0m в аргументы функции:"
    echo '       outputs = { self, nixpkgs, ..., zapret }: {'
    echo ""
    echo -e "  3) В список \e[1mmodules\e[0m вашего nixosSystem добавьте:"
    echo '       zapret.nixosModules.default'
    echo ""
    echo -e "  4) В \e[1mconfiguration.nix\e[0m добавьте:"
    echo '       services.zapret.enable = true;'
    echo ""
    echo -e "\e[1;36m── Вариант 2: Без flakes ──\e[0m"
    echo ""
    echo -e "  1) В \e[1mconfiguration.nix\e[0m добавьте:"
    echo '       imports = [ ./zapret/default.nix ];'
    echo '       services.zapret.enable = true;'
    echo ""
    echo -e "  2) Откройте \e[1m/etc/nixos/zapret/default.nix\e[0m и заполните поле \e[1mhash\e[0m:"
    if [ -n "$zapret_rev" ]; then
        echo "       nix-prefetch-url --unpack https://github.com/bol-van/zapret/archive/${zapret_rev}.tar.gz"
    else
        echo "       Получите rev: git ls-remote https://github.com/bol-van/zapret HEAD | cut -f1"
        echo "       Получите hash: nix-prefetch-url --unpack https://github.com/bol-van/zapret/archive/<rev>.tar.gz"
    fi
    echo ""
    echo -e "\e[1;33m══════════════════════════════════════════════════════\e[0m"
    echo ""

    # Copy default config and hostlist so the TUI works immediately after rebuild
    if [[ -f "$ZAPRET_DIR/zapret.cfgs/configurations/general" ]]; then
        cp "$ZAPRET_DIR/zapret.cfgs/configurations/general" "$ZAPRET_DIR/config" \
            || echo "Предупреждение: не удалось скопировать конфиг по умолчанию."
    fi
    if [[ -f "$ZAPRET_DIR/zapret.cfgs/lists/list-basic.txt" ]]; then
        cp "$ZAPRET_DIR/zapret.cfgs/lists/list-basic.txt" \
           "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" \
            || echo "Предупреждение: не удалось скопировать хостлист по умолчанию."
    fi
    if [[ -f "$ZAPRET_DIR/zapret.cfgs/lists/ipset-discord.txt" ]]; then
        cp "$ZAPRET_DIR/zapret.cfgs/lists/ipset-discord.txt" \
           "$ZAPRET_DIR/ipset/ipset-discord.txt" \
            || true
    fi
    touch "$ZAPRET_DIR/ipset/ipset-game.txt" || true

    _nixos_rebuild_prompt

    configure_zapret_conf
}

install_zapret_release() {
    if [ "$NIXOS" = true ]; then
        _install_nixos
        return
    fi

    install_dependencies
    if [[ $dir_exists == true ]]; then
        read -p "На вашем компьютере был найден запрет ($ZAPRET_DIR). Для продолжения его необходимо удалить. Вы действительно хотите удалить запрет ($ZAPRET_DIR) и продолжить? (y/N): " answer
        case "$answer" in
            [Yy]* )
                if [[ -f "$ZAPRET_DIR/uninstall_easy.sh" ]]; then
                    cd "$ZAPRET_DIR"
                    sed -i '238s/ask_yes_no N/ask_yes_no Y/' "$ZAPRET_DIR/common/installer.sh"
                    yes "" | ./uninstall_easy.sh
                    sed -i '238s/ask_yes_no Y/ask_yes_no N/' "$ZAPRET_DIR/common/installer.sh"
                fi
                rm -rf "$ZAPRET_DIR"
                echo "Удаляю zapret..."
                cd /
                sleep 3
                ;;
            * )
                main_menu
                ;;
        esac
    fi
    download_zapret_release
    cd "$ZAPRET_DIR"
    sed -i '238s/ask_yes_no N/ask_yes_no Y/' "$ZAPRET_DIR/common/installer.sh"
    yes "" | ./install_easy.sh
    sed -i '238s/ask_yes_no Y/ask_yes_no N/' "$ZAPRET_DIR/common/installer.sh"
    rm -f /bin/zapret
    rm -f "$ZAPRET_DIR/config"
    cp -r "$ZAPRET_DIR/zapret.cfgs/configurations/general" "$ZAPRET_DIR/config" || error_exit "не удалось автоматически скопировать конфиг"
    cp -r "$ZAPRET_DIR/zapret.cfgs/bin/"* "$ZAPRET_DIR/files/fake" || error_exit "не удалось автоматически скопировать fake bin"
    rm -f "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
    touch "$ZAPRET_DIR/ipset/ipset-game.txt" || error_exit "не удалось автоматически создать game ipset"
    cp -r "$ZAPRET_DIR/zapret.cfgs/lists/list-basic.txt" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" || error_exit "не удалось автоматически скопировать хостлист"
    cp -r "$ZAPRET_DIR/zapret.cfgs/lists/ipset-discord.txt" "$ZAPRET_DIR/ipset/ipset-discord.txt" || error_exit "не удалось автоматически скопировать ипсет"
    ln -s "$INSTALLER_DIR/zapret-control.sh" /bin/zapret || error_exit "не удалось создать символическую ссылку"
    if [[ INIT_SYSTEM = systemd ]]; then
        systemctl daemon-reload
    fi
    if [[ INIT_SYSTEM = runit ]]; then
        read -p "Для окончания установки необходимо перезапустить ваше устройство. Перезапустить его сейчас? (Y/n): " answer
        case "$answer" in
        [Yy]* )
            reboot
            ;;
        [Nn]* )
            $TPUT_E
            exit 1
            ;;
        * )
            reboot
            ;;
    esac
    else
        manage_service restart
        configure_zapret_conf
    fi
}

install_zapret_git() {
    if [ "$NIXOS" = true ]; then
        _install_nixos
        return
    fi

    install_dependencies
    if [[ $dir_exists == true ]]; then
        read -p "На вашем компьютере был найден запрет ($ZAPRET_DIR). Для продолжения его необходимо удалить. Вы действительно хотите удалить запрет ($ZAPRET_DIR) и продолжить? (y/N): " answer
        case "$answer" in
            [Yy]* )
                if [[ -f "$ZAPRET_DIR/uninstall_easy.sh" ]]; then
                    cd "$ZAPRET_DIR"
                    sed -i '238s/ask_yes_no N/ask_yes_no Y/' "$ZAPRET_DIR/common/installer.sh"
                    yes "" | ./uninstall_easy.sh
                    sed -i '238s/ask_yes_no Y/ask_yes_no N/' "$ZAPRET_DIR/common/installer.sh"
                fi
                rm -rf "$ZAPRET_DIR"
                echo "Удаляю zapret..."
                cd /
                sleep 3
                ;;
            * )
                main_menu
                ;;
        esac
    fi
    download_zapret_git
    cd "$ZAPRET_DIR"
    sed -i '238s/ask_yes_no N/ask_yes_no Y/' "$ZAPRET_DIR/common/installer.sh"
    yes "" | ./install_easy.sh
    sed -i '238s/ask_yes_no Y/ask_yes_no N/' "$ZAPRET_DIR/common/installer.sh"
    rm -f /bin/zapret
    rm -f "$ZAPRET_DIR/config"
    cp -r "$ZAPRET_DIR/zapret.cfgs/configurations/general" "$ZAPRET_DIR/config" || error_exit "не удалось автоматически скопировать конфиг"
    cp -r "$ZAPRET_DIR/zapret.cfgs/bin/"* "$ZAPRET_DIR/files/fake" || error_exit "не удалось автоматически скопировать fake bin"
    rm -f "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
    touch "$ZAPRET_DIR/ipset/ipset-game.txt" || error_exit "не удалось автоматически создать game ipset"
    cp -r "$ZAPRET_DIR/zapret.cfgs/lists/list-basic.txt" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" || error_exit "не удалось автоматически скопировать хостлист"
    cp -r "$ZAPRET_DIR/zapret.cfgs/lists/ipset-discord.txt" "$ZAPRET_DIR/ipset/ipset-discord.txt" || error_exit "не удалось автоматически скопировать ипсет"
    ln -s "$INSTALLER_DIR/zapret-control.sh" /bin/zapret || error_exit "не удалось создать символическую ссылку"
    if [[ INIT_SYSTEM = systemd ]]; then
        systemctl daemon-reload
    fi
    if [[ INIT_SYSTEM = runit ]]; then
        read -p "Для окончания установки необходимо перезапустить ваше устройство. Перезапустить его сейчас? (Y/n): " answer
        case "$answer" in
        [Yy]* )
            reboot
            ;;
        [Nn]* )
            $TPUT_E
            exit 1
            ;;
        * )
            reboot
            ;;
    esac
    else
        manage_service restart
        configure_zapret_conf
    fi
}


update_zapret() {
    if [ "$NIXOS" = true ]; then
        echo -e "\e[36mОбновление Запрета на NixOS...\e[0m"

        # Back up mutable runtime files
        LIST_EXISTS=0
        CONF_EXISTS=0
        TEMP_DIR_CONF=$(mktemp -d)
        if [[ -f "$ZAPRET_DIR/config" ]]; then
            cp "$ZAPRET_DIR/config" "$TEMP_DIR_CONF/config"
            CONF_EXISTS=1
        fi
        if [[ -f "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" ]]; then
            cp "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" "$TEMP_DIR_CONF/zapret-hosts-user.txt"
            LIST_EXISTS=1
        fi

        # Update installer repo (contains updated nix/module.nix and nix/package.nix)
        if [[ -d "$INSTALLER_DIR" ]]; then
            cd "$INSTALLER_DIR" && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
        fi

        # Update zapret.cfgs
        if [[ -d "$ZAPRET_DIR/zapret.cfgs" ]]; then
            cd "$ZAPRET_DIR/zapret.cfgs" && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
        fi

        # Copy possibly-updated module/package to /etc/nixos/zapret/
        if [[ -f "$INSTALLER_DIR/nix/module.nix" ]]; then
            mkdir -p /etc/nixos/zapret
            cp "$INSTALLER_DIR/nix/module.nix"  /etc/nixos/zapret/module.nix \
                || echo "Предупреждение: не удалось обновить /etc/nixos/zapret/module.nix"
            cp "$INSTALLER_DIR/nix/package.nix" /etc/nixos/zapret/package.nix \
                || echo "Предупреждение: не удалось обновить /etc/nixos/zapret/package.nix"
        fi

        _nixos_rebuild_prompt

        # Restore backed-up files (module wins for declared values; runtime files stay)
        if [[ $CONF_EXISTS -eq 1 ]]; then
            mv "$TEMP_DIR_CONF/config" "$ZAPRET_DIR/config"
        fi
        if [[ $LIST_EXISTS -eq 1 ]]; then
            mv "$TEMP_DIR_CONF/zapret-hosts-user.txt" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
        fi
        rm -rf "$TEMP_DIR_CONF"

        manage_service restart
        bash -c 'read -p "Нажмите Enter для продолжения..."'
        exec "$0" "$@"
        return
    fi

    LIST_EXISTS=0
    CONF_EXISTS=0
    TEMP_DIR_CONF=$(mktemp -d)
    if [[ -f "$ZAPRET_DIR/config" ]]; then
        cp -r "$ZAPRET_DIR/config" $TEMP_DIR_CONF/config
        CONF_EXISTS=1
    fi
    if [[ -f "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" ]]; then
        cp -r "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" $TEMP_DIR_CONF/zapret-hosts-user.txt
        LIST_EXISTS=1
    fi 
    #if [ $(zapret_update_check) = 0 ]; then
    #    echo "Актуальная версия уже установлена: нечего обновлять." 
    #    bash -c 'read -p "Нажмите Enter для продолжения..."' 
    
    if [ -f "$ZAPRET_VER_FILE" ]; then
        #cat $ZAPRET_VER_FILE | tr -d '[:space:]' - useful
        if [ -z $(cat "$ZAPRET_VER_FILE") ] || [ $(cat "$ZAPRET_VER_FILE") != "git" ]; then
            download_zapret_release || download_zapret_git || error_exit "не удалось обновить запрет"
            echo -e "Запрет обновлен до версии $(cat $ZAPRET_VER_FILE)"
            cd "$ZAPRET_DIR"
            sed -i '238s/ask_yes_no N/ask_yes_no Y/' "$ZAPRET_DIR/common/installer.sh"
            yes "" | ./install_easy.sh
            sed -i '238s/ask_yes_no Y/ask_yes_no N/' "$ZAPRET_DIR/common/installer.sh"
        else
            cd "$ZAPRET_DIR" && git fetch origin && git checkout -B master origin/master && git reset --hard origin/master || error_exit "не удалось обновить zapret с помощью git. Попробуйте снова, вероятно это сетевая ошибка. Если не помогло - переустановите zapret."
            echo -e "Репозиторий запрета был обновлен."
        fi
    else
        download_zapret_release || download_zapret_git || error_exit "не удалось обновить zapret"
        echo -e "Запрет обновлен до версии $(cat $ZAPRET_VER_FILE)"
        cd "$ZAPRET_DIR"
        sed -i '238s/ask_yes_no N/ask_yes_no Y/' "$ZAPRET_DIR/common/installer.sh"
        yes "" | ./install_easy.sh
        sed -i '238s/ask_yes_no Y/ask_yes_no N/' "$ZAPRET_DIR/common/installer.sh"
    fi

    if [[ -d "$ZAPRET_DIR/zapret.cfgs" ]]; then
        cd "$ZAPRET_DIR/zapret.cfgs" && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
    fi
    if [[ -d "$INSTALLER_DIR/" ]]; then
        cd "$INSTALLER_DIR" && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
        rm -f /bin/zapret
        ln -s "$INSTALLER_DIR/zapret-control.sh" /bin/zapret || error_exit "не удалось создать символическую ссылку"
    fi
    if [ $CONF_EXISTS = 1 ]; then
        rm -f "$ZAPRET_DIR/config"
        mv $TEMP_DIR_CONF/config "$ZAPRET_DIR/config"
    fi
    if [ $LIST_EXISTS = 1 ]; then 
        rm -f "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
        mv $TEMP_DIR_CONF/zapret-hosts-user.txt "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
    fi
    rm -rf $TEMP_DIR_CONF
    rm -rf $TEMP_DIR_BIN
    rm -f "$ZAPRET_DIR/config"
    cp -r "$ZAPRET_DIR/zapret.cfgs/configurations/general" "$ZAPRET_DIR/config" || error_exit "не удалось автоматически скопировать конфиг"
    cp -r "$ZAPRET_DIR/zapret.cfgs/bin/"* "$ZAPRET_DIR/files/fake/" || error_exit "не удалось автоматически скопировать fake bin"
    rm -f "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
    touch "$ZAPRET_DIR/ipset/ipset-game.txt" || error_exit "не удалось автоматически создать game ipset"
    cp -r "$ZAPRET_DIR/zapret.cfgs/lists/list-basic.txt" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" || error_exit "не удалось автоматически скопировать хостлист"
    cp -r "$ZAPRET_DIR/zapret.cfgs/lists/ipset-discord.txt" "$ZAPRET_DIR/ipset/ipset-discord.txt" || error_exit "не удалось автоматически скопировать discord ipset"
    configure_zapret_conf
    manage_service restart
    bash -c 'read -p "Нажмите Enter для продолжения..."'
    exec "$0" "$@"
}

update_script() {
    if [[ -d "$ZAPRET_DIR/zapret.cfgs" ]]; then
        cd "$ZAPRET_DIR/zapret.cfgs" && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
    fi
    if [[ -d "$INSTALLER_DIR/" ]]; then
        cd "$INSTALLER_DIR" && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
    fi
    if [ "$NIXOS" = false ]; then
        rm -f /bin/zapret
        ln -s "$INSTALLER_DIR/zapret-control.sh" /bin/zapret || error_exit "не удалось создать символическую ссылку"
    fi
    bash -c 'read -p "Нажмите Enter для продолжения..."'
    exec "$0" "$@"
}

update_installed_script() {
    if [[ -d "$ZAPRET_DIR/zapret.cfgs" ]]; then
        cd "$ZAPRET_DIR/zapret.cfgs" && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
    fi
    if [[ -d "$INSTALLER_DIR/" ]]; then
        cd "$INSTALLER_DIR" && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
        if [ "$NIXOS" = false ]; then
            rm -f /bin/zapret
            ln -s "$INSTALLER_DIR/zapret-control.sh" /bin/zapret || error_exit "не удалось создать символическую ссылку"
        fi
        manage_service restart
    fi
    bash -c 'read -p "Нажмите Enter для продолжения..."'
    exec "$0" "$@"
}

uninstall_zapret() {
    read -p "Вы действительно хотите удалить запрет? (y/N): " answer
    case "$answer" in
        [Yy]* )
            if [ "$NIXOS" = true ]; then
                echo -e "\e[36mУдаление Запрета на NixOS...\e[0m"
                rm -rf /etc/nixos/zapret
                echo ""
                echo -e "\e[33mНе забудьте убрать строку\e[0m"
                echo "  imports = [ ./zapret/default.nix ];"
                echo -e "\e[33mиз /etc/nixos/configuration.nix (или flake.nix)\e[0m"
                echo ""
                _nixos_rebuild_prompt
                rm -rf "$ZAPRET_DIR"
                rm -rf "$INSTALLER_DIR/"
                rm -f "$ZAPRET_VER_FILE"
                echo "Запрет удален"
                $TPUT_E
                exit
            fi

            if [[ -f "$ZAPRET_DIR/uninstall_easy.sh" ]]; then
                cd "$ZAPRET_DIR"
                yes "" | ./uninstall_easy.sh
            fi
            rm -rf "$ZAPRET_DIR"
            rm -rf "$INSTALLER_DIR/"
            rm -r /bin/zapret
            rm -f "$ZAPRET_VER_FILE"
            echo "Удаляю zapret..."
            sleep 3
            echo "Запрет удален"
            $TPUT_E
            exit
            ;;
        * )
            main_menu
            ;;
    esac
} 
