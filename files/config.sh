#!/bin/bash



get_fwtype() {
    [ -n "$FWTYPE" ] && return

    local UNAME="$(uname)"

    case "$UNAME" in
        Linux)
            if [[ $SYSTEM == openwrt ]]; then
                if exists iptables; then
                    iptables_version=$(iptables --version 2>&1)

                    if [[ "$iptables_version" == *"legacy"* ]]; then
                        FWTYPE="iptables"
                        return 0
                    elif [[ "$iptables_version" == *"nf_tables"* ]]; then
                        FWTYPE="nftables"
                        return 0
                    else
                        echo -e "\e[1;33m⚠️ Не удалось определить тип файрвола.\e[0m"
                        echo -e "По умолчанию будет использован: \e[1;36mnftables\e[0m"
                        echo -e "\e[2m(Можно изменить в $ZAPRET_DIR/config)\e[0m"
                        echo -e "⏳ Продолжаю через 5 секунд..."
                        FWTYPE="nftables"
                        sleep 5
                        return 0 
                    fi
                else
                    echo -e "\e[1;33m⚠️ iptables не найден. Используется по умолчанию: \e[1;36mnftables\e[0m"
                    echo -e "\e[2m(Можно изменить в $ZAPRET_DIR/config)\e[0m"
                    echo -e "⏳ Продолжаю через 5 секунд..."
                    FWTYPE="nftables"
                    sleep 5
                    return 0
                fi
            fi

            if exists iptables; then
                iptables_version=$(iptables -V 2>&1)

                if [[ "$iptables_version" == *"legacy"* ]]; then
                    FWTYPE="iptables"
                elif [[ "$iptables_version" == *"nf_tables"* ]]; then
                    FWTYPE="nftables"
                else
                    echo -e "\e[1;33m⚠️ Не удалось определить тип файрвола.\e[0m"
                    echo -e "По умолчанию используется: \e[1;36miptables\e[0m"
                    echo -e "\e[2m(Можно изменить в $ZAPRET_DIR/config)\e[0m"
                    echo -e "⏳ Продолжаю через 5 секунд..."
                    FWTYPE="iptables"
                    sleep 5
                fi
            else
                echo -e "\e[1;31m❌ iptables не найден!\e[0m"
                echo -e "По умолчанию используется: \e[1;36miptables\e[0m"
                echo -e "\e[2m(Можно изменить в $ZAPRET_DIR/config)\e[0m"
                echo -e "⏳ Продолжаю через 5 секунд..."
                FWTYPE="iptables"
                sleep 5
            fi
            ;;
        FreeBSD)
            if exists ipfw ; then
                FWTYPE="ipfw"
            else
                echo -e "\e[1;33m⚠️ ipfw не найден!\e[0m"
                echo -e "По умолчанию используется: \e[1;36miptables\e[0m"
                echo -e "\e[2m(Можно изменить в $ZAPRET_DIR/config)\e[0m"
                echo -e "⏳ Продолжаю через 5 секунд..."
                FWTYPE="iptables"
                sleep 5
            fi
            ;;
        *)
            echo -e "\e[1;31m❌ Неизвестная система: $UNAME\e[0m"
            echo -e "По умолчанию используется: \e[1;36miptables\e[0m"
            echo -e "\e[2m(Можно изменить в $ZAPRET_DIR/config)\e[0m"
            echo -e "⏳ Продолжаю через 5 секунд..."
            FWTYPE="iptables"
            sleep 5
            ;;
    esac
}

cur_conf() {
    cr_cnf="неизвестно"
    if [[ -f $ZAPRET_DIR/config ]]; then
        TEMP_CUR_STR=$(mktemp -d)
        cp -r $ZAPRET_DIR/config $TEMP_CUR_STR/config
        sed -i "s/^FWTYPE=.*/FWTYPE=iptables/" $TEMP_CUR_STR/config
        for file in $ZAPRET_DIR/zapret.cfgs/configurations/*; do
            if [[ -f "$file" && "$(sha256sum "$file" | awk '{print $1}')" == "$(sha256sum $TEMP_CUR_STR/config | awk '{print $1}')" ]]; then
                cr_cnf="$(basename "$file")"
                break
            fi
        done
    fi
}

cur_list() {
    cr_lst="неизвестно"
    if [[ -f $ZAPRET_DIR/config ]]; then
        for file in $ZAPRET_DIR/zapret.cfgs/lists/*; do
            if [[ -f "$file" && "$(sha256sum "$file" | awk '{print $1}')" == "$(sha256sum $ZAPRET_DIR/ipset/zapret-hosts-user.txt | awk '{print $1}')" ]]; then
                cr_lst="$(basename "$file")"
                break
            fi
        done
    fi
}
game_mode_check() {
    if [ ! -f "$ZAPRET_DIR/ipset/ipset-game.txt" ]; then
        touch $ZAPRET_DIR/ipset/ipset-game.txt || error_exit "не удалось создать ipset для игрвого режима"
    fi
    
    if grep -q "^0\.0\.0\.0/0$" $ZAPRET_DIR/ipset/ipset-game.txt; then
        game_mode_status="включен"
    else
        game_mode_status="выключен"
    fi
}

toggle_game_mode() {
    game_mode_check
    
    if [[ $game_mode_status == "включен" ]]; then
        rm -f $ZAPRET_DIR/ipset/ipset-game.txt
        touch $ZAPRET_DIR/ipset/ipset-game.txt || error_exit "не удалось создать ipset для игрвого режима"
        echo "203.0.113.77" >> $ZAPRET_DIR/ipset/ipset-game.txt
    else
        rm -f $ZAPRET_DIR/ipset/ipset-game.txt
        touch $ZAPRET_DIR/ipset/ipset-game.txt || error_exit "не удалось создать ipset для игрвого режима"
        echo "0.0.0.0/0" >> $ZAPRET_DIR/ipset/ipset-game.txt
    fi
    manage_service restart
    sleep 2
}

configure_zapret_conf() {
    if [[ ! -d $ZAPRET_DIR/zapret.cfgs ]]; then
        echo -e "\e[35mКлонирую конфигурации...\e[0m"
        manage_service stop
        git clone https://github.com/Snowy-Fluffy/zapret.cfgs $ZAPRET_DIR/zapret.cfgs
        echo -e "\e[32mКлонирование успешно завершено.\e[0m"
        manage_service start
        sleep 2
    fi
    if [[ -d $ZAPRET_DIR/zapret.cfgs ]]; then
        echo "Проверяю наличие на обновление конфигураций..."
        manage_service stop 
        cd $INSTALLER_DIR && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
        manage_service start
        sleep 2
    fi

    clear

    echo "Выберите стратегию (можно поменять в любой момент, запустив Меню управления запретом еще раз):"
    PS3="Введите номер стратегии (по умолчанию 'general'): "

    select CONF in $(for f in $ZAPRET_DIR/zapret.cfgs/configurations/*; do echo "$(basename "$f" | tr ' ' '.')"; done) "Отмена"; do
        if [[ "$CONF" == "Отмена" ]]; then
            main_menu
        elif [[ -n "$CONF" ]]; then
            CONFIG_PATH="$ZAPRET_DIR/zapret.cfgs/configurations/${CONF//./ }"
            rm -f $ZAPRET_DIR/config
            cp "$CONFIG_PATH" $ZAPRET_DIR/config || error_exit "не удалось скопировать стратегию"
            echo "Стратегия '$CONF' установлена."

            sleep 2
            break
        else
            echo "Неверный выбор, попробуйте снова."
        fi
    done

    get_fwtype
    sed -i "s/^FWTYPE=.*/FWTYPE=$FWTYPE/" $ZAPRET_DIR/config
    manage_service restart
    main_menu
}

configure_zapret_list() {
    if [[ ! -d $ZAPRET_DIR/zapret.cfgs ]]; then
        echo -e "\e[35mКлонирую конфигурации...\e[0m"
        manage_service stop
        git clone https://github.com/Snowy-Fluffy/zapret.cfgs $ZAPRET_DIR/zapret.cfgs
        manage_service start
        echo -e "\e[32mКлонирование успешно завершено.\e[0m"
        sleep 2
    fi
    if [[ -d $ZAPRET_DIR/zapret.cfgs ]]; then
        echo "Проверяю наличие на обновление конфигураций..."
        manage_service stop
        cd $INSTALLER_DIR && git fetch origin && git checkout -B main origin/main && git reset --hard origin/main
        manage_service start
        sleep 2
    fi

    clear

    echo -e "\e[36mВыберите хостлист (можно поменять в любой момент, запустив Меню управления запретом еще раз):\e[0m"
    PS3="Введите номер листа (по умолчанию 'list-basic.txt'): "

    select LIST in $(for f in $ZAPRET_DIR/zapret.cfgs/lists/list*; do echo "$(basename "$f")"; done) "Отмена"; do
        if [[ "$LIST" == "Отмена" ]]; then
            main_menu
        elif [[ -n "$LIST" ]]; then
            LIST_PATH="$ZAPRET_DIR/zapret.cfgs/lists/$LIST"
            rm -f $ZAPRET_DIR/ipset/zapret-hosts-user.txt
            cp "$LIST_PATH" $ZAPRET_DIR/ipset/zapret-hosts-user.txt || error_exit "не удалось скопировать хостлист"
            echo -e "\e[32mХостлист '$LIST' установлен.\e[0m"

            sleep 2
            break
        else
            echo -e "\e[31mНеверный выбор, попробуйте снова.\e[0m"
        fi
    done
    manage_service restart
    main_menu
}

configure_custom_conf_path() {
    echo -e "\e[36mУкажите путь к стратегии. (Enter и пустой ввод для отмены)\e[0m"
    read -rp "Путь к стратегии (Пример: /home/user/folder/123): " CONFIG_PATH

    if [[ -z "$CONFIG_PATH" ]]; then
        main_menu
    fi

    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo -e "\e[31mФайл не найден: $CONFIG_PATH\e[0m"
        sleep 2
        main_menu
    fi

    manage_service stop
    rm -f $ZAPRET_DIR/config
    cp -r -- "$CONFIG_PATH" $ZAPRET_DIR/config || error_exit "не удалось скопировать стратегию из указанного пути"
    get_fwtype
    sed -i "s/^FWTYPE=.*/FWTYPE=$FWTYPE/" $ZAPRET_DIR/config
    echo -e "\e[32mСтратегия установлена из: $CONFIG_PATH\e[0m"
    manage_service start
    sleep 2
    main_menu
}

configure_custom_list_path() {
    echo -e "\e[36mУкажите путь к хостлисту. (Enter и пустой ввод для отмены)\e[0m"
    read -rp "Путь к хостлисту: " LIST_PATH

    if [[ -z "$LIST_PATH" ]]; then
        main_menu
    fi

    if [[ ! -f "$LIST_PATH" ]]; then
        echo -e "\e[31mФайл не найден: $LIST_PATH\e[0m"
        sleep 2
        main_menu
    fi

    manage_service stop
    rm -f $ZAPRET_DIR/ipset/zapret-hosts-user.txt
    cp -r -- "$LIST_PATH" $ZAPRET_DIR/ipset/zapret-hosts-user.txt || error_exit "не удалось скопировать хостлист из указанного пути"
    echo -e "\e[32mХостлист установлен из: $LIST_PATH\e[0m"
    manage_service start
    sleep 2
    main_menu
}

add_to_zapret() {
    read -p "Введите IP-адреса или домены для добавления в лист (разделяйте пробелами, запятыми или |)(Enter и пустой ввод для отмены): " input
    
    if [[ -z "$input" ]]; then
        main_menu
    fi

    IFS=',| ' read -ra ADDRESSES <<< "$input"

    for address in "${ADDRESSES[@]}"; do
        address=$(echo "$address" | xargs)
        if [[ -n "$address" && ! $(grep -Fxq "$address" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt") ]]; then
            echo "$address" >> "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
            echo "Добавлено: $address"
        else
            echo "Уже существует: $address"
        fi
    done
    
    manage_service restart
    echo "Готово"
    sleep 2
    main_menu
}
add_to_zapret_exc() {
    read -p "Введите IP-адреса или домены для добавления в лист исключений (разделяйте пробелами, запятыми или |)(Enter и пустой ввод для отмены): " input
    
    if [[ -z "$input" ]]; then
        main_menu
    fi

    IFS=',| ' read -ra ADDRESSES <<< "$input"

    for address in "${ADDRESSES[@]}"; do
        address=$(echo "$address" | xargs)
        if [[ -n "$address" && ! $(grep -Fxq "$address" "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt") ]]; then
            echo "$address" >> "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt"
            echo "Добавлено: $address"
        else
            echo "Уже существует: $address"
        fi
    done
    
    manage_service restart
    echo "Готово"
    sleep 2
    main_menu
}
edit_cust_list() {
    if [ -e "$ZAPRET_DIR/zapret.cfgs/lists/list-custom.txt" ]; then
        open_editor $ZAPRET_DIR/zapret.cfgs/lists/list-custom.txt
        echo "Хостлист был отредактирован"
        sleep 3
        main_menu
    else
        touch $ZAPRET_DIR/zapret.cfgs/lists/list-custom.txt
        open_editor $ZAPRET_DIR/zapret.cfgs/lists/list-custom.txt
        echo "Хостлист был отредактирован"
        sleep 3
        main_menu
    fi
}
edit_cust_conf() {
    if [ -e "$ZAPRET_DIR/zapret.cfgs/configurations/conf-custom" ]; then
        open_editor $ZAPRET_DIR/zapret.cfgs/configurations/conf-custom
        echo "Стратегия была отредактирован"
        sleep 3
        main_menu
    else
        cp -r $ZAPRET_DIR/config.default $ZAPRET_DIR/zapret.cfgs/configurations/conf-custom 
        open_editor $ZAPRET_DIR/zapret.cfgs/configurations/conf-custom
        echo "Стратегия была отредактирован"
        sleep 3
        main_menu
    fi
}
    
    

delete_from_zapret() {
    read -p "Введите IP-адреса или домены для удаления из листа (разделяйте пробелами, запятыми или |)(Enter и пустой ввод для отмены): " input

    if [[ -z "$input" ]]; then
        main_menu
    fi

    IFS=',| ' read -ra ADDRESSES <<< "$input"

    for address in "${ADDRESSES[@]}"; do
        address=$(echo "$address" | xargs)
        if [[ -n "$address" ]]; then
            if grep -Fxq "$address" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"; then
                sed -i "\|^$address\$|d" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"
                echo "Удалено: $address"
            else
                echo "Не найдено: $address"
            fi
        fi
    done

    manage_service restart
    echo "Готово"
    sleep 2
    main_menu
}


search_in_zapret() {
    read -p "Введите домен или IP-адрес для поиска в хостлисте (Enter и пустой ввод для отмены): " keyword

    if [[ -z "$keyword" ]]; then
        main_menu
        return
    fi

    echo
    echo "🔍 Результаты поиска по запросу: $keyword"
    echo "----------------------------------------"

    if grep -i --color=never -F "$keyword" "$ZAPRET_DIR/ipset/zapret-hosts-user.txt"; then
        echo "----------------------------------------"
        read -rp "Нажмите Enter для продолжения..."
    else
        echo "❌ Совпадений не найдено."
        echo "----------------------------------------"
        read -rp "Нажмите Enter для возврата в меню..."
    fi

    main_menu
}
delete_from_zapret_exc() {
    read -p "Введите IP-адреса или домены для удаления из листа исключений (разделяйте пробелами, запятыми или |)(Enter и пустой ввод для отмены): " input

    if [[ -z "$input" ]]; then
        main_menu
    fi

    IFS=',| ' read -ra ADDRESSES <<< "$input"

    for address in "${ADDRESSES[@]}"; do
        address=$(echo "$address" | xargs)
        if [[ -n "$address" ]]; then
            if grep -Fxq "$address" "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt"; then
                sed -i "\|^$address\$|d" "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt"
                echo "Удалено: $address"
            else
                echo "Не найдено: $address"
            fi
        fi
    done

    manage_service restart
    echo "Готово"
    sleep 2
    main_menu
}


search_in_zapret_exc() {
    read -p "Введите домен или IP-адрес для поиска в листе исключений (Enter и пустой ввод для отмены): " keyword

    if [[ -z "$keyword" ]]; then
        main_menu
        return
    fi

    echo
    echo "🔍 Результаты поиска по запросу: $keyword"
    echo "----------------------------------------"

    if grep -i --color=never -F "$keyword" "$ZAPRET_DIR/ipset/zapret-hosts-user-exclude.txt"; then
        echo "----------------------------------------"
        read -rp "Нажмите Enter для продолжения..."
    else
        echo "❌ Совпадений не найдено."
        echo "----------------------------------------"
        read -rp "Нажмите Enter для возврата в меню..."
    fi

    main_menu
}

test_domain() {
    local domain="$1"
    domain=$(echo "$domain" | sed 's/#.*//' | xargs)
    [[ -z "$domain" ]] && return

    # Временный файл для хранения результатов
    local r_file="$(mktemp)"
    # FAIL - результат по-умолчанию для ping http tls1.2 tls1.3 (построчно)
    echo -en "FAIL\nFAIL\nFAIL\nFAIL" > "$r_file"

    # Таймауты
    local t_ping=2
    local t_http=5

    if [[ "$domain" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        test_ip "$domain"
    else
        # Асинхронно запустим ping, http и https.
        # sed запишет результат строго в указанную строку
        {
            result=$(ping -c 2 -W $t_ping "$domain" 2>/dev/null | grep -E "rtt min/avg/max/mdev" | awk -F'/' '{print $5}')
            if [[ -n "$result" ]]; then
                sed -i "1c\\${result}ms" "$r_file"
            fi
        } &
        {
            result=$(curl -m $t_http -s -o /dev/null -w "%{http_code}" "http://$domain" 2>/dev/null || echo "FAIL")
            if [[ "$result" =~ ^[0-9]+$ ]]; then
                sed -i "2c\\HTTP:$result" "$r_file"
            fi
        } &
        # https будет синхронным - в обоих случаях подключение идет по одному и тому же порту (443)
        # и будет некорректно запускать оба подключения одновременно.
        {
            result=$(curl -m $t_http -s -o /dev/null -w "%{http_code}" --tlsv1.2 "https://$domain" 2>/dev/null || echo "FAIL")
            if [[ "$result" =~ ^[0-9]+$ ]]; then
                sed -i "3c\\TLS1.2:$result" "$r_file"
            fi
            result=$(curl -m $t_http -s -o /dev/null -w "%{http_code}" --tlsv1.3 "https://$domain" 2>/dev/null || echo "FAIL")
            if [[ "$result" =~ ^[0-9]+$ ]]; then
                sed -i "4c\\TLS1.3:$result" "$r_file"
            fi
        } &
    fi

    # Ждем окончания всех запросов, объединяем строки с результатами в одну, удаляем временный файл
    wait
    echo $(paste -sd ' ' "$r_file")
    rm -f "$r_file"
}

test_ip() {
    local ip="$1"
    local results=()
    ping_result=$(ping -c 2 -W 2 "$ip" 2>/dev/null | grep -E "rtt min/avg/max/mdev" | awk -F'/' '{print $5}')
    if [[ -n "$ping_result" ]]; then
        results=("${ping_result}ms" "N/A" "N/A" "N/A")
    else
        results=("FAIL" "N/A" "N/A" "N/A")
    fi
    echo "${results[@]}"
}

print_table_header() {
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    printf "│ %-30s │ %-8s │ %-10s │ %-10s │ %-10s │\n" "Домен/IP" "Ping" "HTTP" "TLS1.2" "TLS1.3"
    echo "├─────────────────────────────────────────────────────────────────────────────┤"
}

print_table_row() {
    local domain="$1"
    local ping="$2"
    local http="$3"
    local tls12="$4"
    local tls13="$5"
    local display_domain="$domain"
    if [[ ${#domain} -gt 30 ]]; then
        display_domain="${domain:0:27}..."
    fi
    printf "│ %-30s  %-8s  %-10s  %-10s  %-10s \n" "$display_domain" "$ping" "$http" "$tls12" "$tls13"
}

test_all_domains() {
    local config_name="$1"
    local list_path="$2"
    local total=0
    local available=0
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ Стратегия: $config_name"
    echo "├─────────────────────────────────────────────────────────────────────────────┤"
    print_table_header
    local results_lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -z "$line" ]] && continue
        total=$((total + 1))
        results=($(test_domain "$line"))
        local is_available=0
        if [[ "${results[0]}" != "FAIL" ]]; then
            if [[ "$line" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                is_available=1
            elif [[ "${results[2]}" =~ ^TLS1\.2:[23] ]] || [[ "${results[3]}" =~ ^TLS1\.3:[23] ]]; then
                is_available=1
            fi
        fi
        if [[ $is_available -eq 1 ]]; then
            available=$((available + 1))
        fi
        results_lines+=("$line|${results[0]}|${results[1]}|${results[2]}|${results[3]}|$is_available")
    done < "$list_path"
    for line_info in "${results_lines[@]}"; do
        IFS='|' read -r domain ping http tls12 tls13 is_available <<< "$line_info"
        print_table_row "$domain" "$ping" "$http" "$tls12" "$tls13"
    done
    echo "├─────────────────────────────────────────────────────────────────────────────┤"
    printf "│ Доступно: %d/%d доменов/IP                                           │\n" "$available" "$total"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "$available"
}

apply_config() {
    local config="$1"
    echo -e "\e[33mПрименяем стратегию: $config\e[0m"
    CONFIG_PATH="$ZAPRET_DIR/zapret.cfgs/configurations/$config"
    if [[ ! -f "$CONFIG_PATH" ]]; then
        echo -e "\e[31mФайл конфигурации не найден: $CONFIG_PATH\e[0m"
    fi
    rm -f $ZAPRET_DIR/config
    cp "$CONFIG_PATH" $ZAPRET_DIR/config || error_exit "не удалось скопировать стратегию"
    get_fwtype
    sed -i "s/^FWTYPE=.*/FWTYPE=$FWTYPE/" $ZAPRET_DIR/config
    manage_service restart
}

check_conf() {
    echo -e "\e[36mВыберите хостлист для тестирования (можно поменять в любой момент, запустив Меню управления запретом еще раз):\e[0m"
    PS3="Введите номер листа (по умолчанию для тестирования 'list-simple.txt'): "
    select LIST in $(for f in $ZAPRET_DIR/zapret.cfgs/lists/list*; do echo "$(basename "$f")"; done) "Отмена"; do
        if [[ "$LIST" == "Отмена" ]]; then
            main_menu
        elif [[ -n "$LIST" ]]; then
            LIST_PATH="$ZAPRET_DIR/zapret.cfgs/lists/$LIST"
            rm -f $ZAPRET_DIR/ipset/zapret-hosts-user.txt
            cp "$LIST_PATH" $ZAPRET_DIR/ipset/zapret-hosts-user.txt || error_exit "не удалось скопировать хостлист"
            echo -e "\e[32mХостлист '$LIST' установлен.\e[0m"
            sleep 2
            break
        else
            echo -e "\e[31mНеверный выбор, попробуйте снова.\e[0m"
        fi
    done
    manage_service restart
    check_list
    echo ""
    
    echo -e "\e[36mВыберите стратегии для проверки:\e[0m"
    echo -e "\e[33mМожно выбрать несколько стратегий через пробел или тире (например: '1 3 5' или '1-5' или '1-3 5 7-9')\e[0m"
    echo ""
    
    all_configs=($(for f in $ZAPRET_DIR/zapret.cfgs/configurations/*; do basename "$f" | tr ' ' '.'; done))
    
    if [[ ${#all_configs[@]} -eq 0 ]]; then
        error_exit "\e[31mНет доступных стратегий для проверки\e[0m"
    fi
    
    PS3="Введите номера стратегий (через пробел или диапазоны): "
    select _ in "${all_configs[@]}" "Выбрать все стратегии"; do
        user_input="$REPLY"
        if [[ -z "$user_input" ]] || [[ "$user_input" == $((${#all_configs[@]} + 1)) ]]; then
            configs=("${all_configs[@]}")
            echo -e "\e[33mБудут проверены ВСЕ стратегии.\e[0m"
            break
        fi
        
        selected_indices=()
        valid_input=true
        configs=()
        read -ra parts <<< "$user_input"
        
        for part in "${parts[@]}"; do
            if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
                start="${BASH_REMATCH[1]}"
                end="${BASH_REMATCH[2]}"
                
                if [[ $start -le 0 ]] || [[ $end -le 0 ]]; then
                    echo -e "\e[31mОшибка: номера должны быть положительными числами (неверный диапазон: $part)\e[0m"
                    valid_input=false
                    continue
                fi
                
                if [[ $start -gt $end ]]; then
                    temp=$start
                    start=$end
                    end=$temp
                fi
                for ((i=start; i<=end; i++)); do
                    if [[ $i -le ${#all_configs[@]} ]] && [[ $i -ge 1 ]]; then
                        selected_indices+=("$i")
                    fi
                done
            elif [[ "$part" =~ ^[0-9]+$ ]]; then
                if [[ $part -le 0 ]]; then
                    echo -e "\e[31mОшибка: номер должен быть положительным числом (неверный номер: $part)\e[0m"
                    valid_input=false
                    continue
                fi
                
                if [[ $part -le ${#all_configs[@]} ]]; then
                    selected_indices+=("$part")
                else
                    echo -e "\e[31mОшибка: номер $part превышает количество доступных стратегий (${#all_configs[@]})\e[0m"
                    valid_input=false
                fi
            else
                echo -e "\e[31mОшибка: неверный формат '$part'. Используйте числа или диапазоны (например: '1-5')\e[0m"
                valid_input=false
            fi
        done
        
        if [[ $valid_input == true ]] && [[ ${#selected_indices[@]} -gt 0 ]]; then
            unique_indices=($(printf "%s\n" "${selected_indices[@]}" | sort -n | uniq))
            
            configs=()
            for index in "${unique_indices[@]}"; do
                array_index=$((index-1))
                configs+=("${all_configs[$array_index]}")
            done
            
            echo ""
            echo -e "\e[32mВыбрано стратегий: ${#configs[@]}\e[0m"
            echo -e "\e[33mБудут проверены:\e[0m"
            for i in "${!configs[@]}"; do
                echo "$((i+1)). ${configs[$i]}"
            done
            break
        elif [[ ${#selected_indices[@]} -eq 0 ]] && [[ $valid_input == true ]]; then
            echo -e "\e[31mНе выбрано ни одной стратегии. Попробуйте снова.\e[0m"
            echo -e "\e[36mВыберите стратегии для проверки:\e[0m"
            echo -e "\e[33mМожно выбрать несколько стратегий через пробел или диапазоны (например: '1 3 5' или '1-5' или '1-3 5 7-9')\e[0m"
            echo -e "\e[33mОставьте пустым для проверки всех стратегий\e[0m"
            PS3="Введите номера стратегий (через пробел или диапазоны): "
        fi
    done
    
    if [[ ${#configs[@]} -eq 0 ]]; then
        error_exit "\e[31mНе выбрано ни одной стратегии для проверки\e[0m"
    fi
    
    echo -e "\e[33mБудет проверено стратегий: ${#configs[@]}\e[0m"
    echo ""
    echo -e "\e[36mНачинаем проверку всех стратегий...\e[0m"
    echo -e "\e[36mЭто может занять много времени. Чтобы выйти, вы можете воспользоваться комбинацией клавиш CTRL+C. Продолжаю через 5 секунд...\e[0m"
    sleep 5
    stats_file="/tmp/zapret_final_stats_$$.txt"
    > "$stats_file"
    local best_config=""
    local best_available=0
    local total_domains=0
    total_domains=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [[ -n "$line" ]] && total_domains=$((total_domains + 1))
    done < "$LIST_PATH"
    for config in "${configs[@]}"; do
        echo "──────────────────────────────────────────────────────────────────────────────"
        echo ""
        config_original="${config//./ }"
        if ! apply_config "$config_original"; then
            echo -e "\e[31mНе удалось применить стратегию: $config\e[0m"
            echo ""
            continue
        fi
        available=$(test_all_domains "$config" "$LIST_PATH" | tee /dev/tty | tail -1)
        if [[ "$available" =~ ^[0-9]+$ ]]; then
            echo "$config $available" >> "$stats_file"
            if [[ $available -gt $best_available ]]; then
                best_available=$available
                best_config="$config"
            fi
        else
            echo -e "\e[31mОшибка при тестировании стратегии: $config\e[0m"
        fi
    done
    echo ""
    echo -e "\e[42m\e[30m╔══════════════════════════════════════════════════════════════════════════╗\e[0m"
    echo -e "\e[42m\e[30m║                           ИТОГОВЫЙ РЕЗУЛЬТАТ                             ║\e[0m"
    echo -e "\e[42m\e[30m╠══════════════════════════════════════════════════════════════════════════╣\e[0m"
    echo -e "\e[42m\e[30m║                                                                          ║\e[0m"
    printf "\e[42m\e[30m║  Лучшая стратегия:    %-50s ║\n\e[0m" "$best_config"
    printf "\e[42m\e[30m║  Доступно доменов/IP: %-52s ║\n\e[0m" "$best_available из $total_domains ($(echo "scale=1; $best_available * 100 / $total_domains" | bc)%)"
    echo -e "\e[42m\e[30m║                                                                          ║\e[0m"
    echo -e "\e[42m\e[30m╚══════════════════════════════════════════════════════════════════════════╝\e[0m"
    echo ""
    echo -e "\e[33mПрименяем лучшую стратегию: $best_config\e[0m"
    best_config_original="${best_config//./ }"
    apply_config "$best_config_original"
    sleep 3
    if [[ -f "$stats_file" ]] && [[ $(wc -l < "$stats_file") -gt 0 ]]; then
        echo ""
        echo -e "\e[36mСтатистика по всем стратегиям:\e[0m"
        echo "┌──────────────────────────────────────────────────────┐"
        printf "│ %-30s │ %-10s │ %-6s │\n" "Стратегия" "Доступно" "%"
        echo "├──────────────────────────────────────────────────────┤"
        while read -r line; do
            read -r config count <<< "$line"
            if [[ "$count" =~ ^[0-9]+$ ]] && [[ $total_domains -gt 0 ]]; then
                percentage=$(echo "scale=1; $count * 100 / $total_domains" | bc)
                printf "│ %-30s │ %-10s │ %-5s%% │\n" "$config" "$count/$total_domains" "$percentage"
            fi
        done < "$stats_file"
        echo "└──────────────────────────────────────────────────────┘"
    fi
    rm -f "$stats_file"
    read -p "Нажмите Enter для продолжения..."
    sleep 1
}
check_list() {
    LINE_COUNT=$(wc -l < "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" 2>/dev/null || echo "0")
    if [ "$LINE_COUNT" = "0" ] && [ -s "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" ]; then
        LINE_COUNT=$(awk 'END{print NR}' "$ZAPRET_DIR/ipset/zapret-hosts-user.txt" 2>/dev/null || echo "0")
    fi
    if ! [[ "$LINE_COUNT" =~ ^[0-9]+$ ]]; then
        echo "Ошибка: Не удалось подсчитать строки в файле"
        exit 1
    fi
    echo "В выбраном листе $LINE_COUNT доменов/айпи."
    if [ "$LINE_COUNT" -gt 100 ]; then
        echo "Проверка может занять *ОЧЕНЬ* много времени!"
        echo ""
        read -p "Нажмите Enter для продолжения или Ctrl+C для отмены... "
    fi
}
