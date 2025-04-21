#!/bin/bash

# Цвета
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
NC="\e[0m"

# Директории
SWARM_DIR="$HOME/rl-swarm"
HOME_DIR="$HOME"

# Директория для хранения логов мониторинга
MONITOR_LOG_DIR="$HOME/.gensyn_monitor"
MONITOR_LOG_FILE="$MONITOR_LOG_DIR/monitor.log"
MONITOR_PID_FILE="$MONITOR_LOG_DIR/monitor.pid"

# Функция для модификации run_rl_swarm.sh (Protobuf fix + Auto Testnet/HF)
modify_run_script() {
    local script_path="$1/run_rl_swarm.sh"
    if [ -f "$script_path" ]; then
        echo -e "${YELLOW}[!] Модификация ${script_path} (Protobuf fix, Auto Testnet/HF)...${NC}"
        local success=true
        local tmp_file=$(mktemp)

        # 0. Применить Protobuf fix
        # Вставляем строки перед pip_install requirements-hivemind.txt
        awk '
        /^pip_install "\$ROOT"\/requirements-hivemind\.txt/ {
            print "# Force install a compatible protobuf version before installing hivemind requirements"
            print "echo_green \">> Installing compatible protobuf version...\""
            print "pip install --disable-pip-version-check -q \"protobuf>=3.12.2,<5.28.0\""
        }
        { print }
        ' "$script_path" > "$tmp_file"

        if [ $? -eq 0 ]; then
             mv "$tmp_file" "$script_path"
             echo -e "${GREEN}[✓] Protobuf fix применен.${NC}"
        else
             echo -e "${RED}${BOLD}[✗] Ошибка применения Protobuf fix.${NC}"
             rm -f "$tmp_file"
             return 1 # Выходим, если патч не применился
        fi 

        # 1. Модификация Testnet (теперь применяем к уже пропатченному файлу)
        tmp_file=$(mktemp) # Новый временный файл
        # Сначала удаляем старый блок while...done
        sed '/^while true; do/,/^done/d' "$script_path" > "$tmp_file"
        if [ $? -ne 0 ]; then
             echo -e "${RED}${BOLD}[✗] Ошибка удаления блока Testnet.${NC}"
             rm -f "$tmp_file"
             success=false
        else
            # Теперь вставляем новые строки после строки с EOF
            local tmp_file_insert=$(mktemp)
            awk '/^EOF$/{print; printf "%s\n", "# Automatically connect to Testnet without asking"; printf "%s\n", "CONNECT_TO_TESTNET=True"; printf "%s\n", "echo_green \">> Automatically connecting to Testnet.\"" ; next}1' "$tmp_file" > "$tmp_file_insert"
            if [ $? -eq 0 ]; then
                mv "$tmp_file_insert" "$script_path"
                echo -e "${GREEN}[✓] Testnet вопрос удален и заменен.${NC}"
            else
                echo -e "${RED}${BOLD}[✗] Ошибка вставки блока Testnet.${NC}"
                rm -f "$tmp_file_insert"
                success=false
            fi
            rm -f "$tmp_file" # Удаляем первый временный файл sed
        fi

        # 2. Модификация Hugging Face (если Testnet прошел успешно)
        if [ "$success" = true ]; then
            # Комментируем строки с запросом и обработкой ответа HF
            sed -i -e '/read -p ".*Hugging Face Hub?.*"/s/^/#/' \
                   -e '/yn=${yn:-N}/s/^/#/' \
                   -e '/case \$yn in/s/^/#/' \
                   -e '/^[[:space:]]*\[Yy\]\*)/s/^/#/' \
                   -e '/^[[:space:]]*\[Nn\]\*)/s/^/#/' \
                   -e '/^[[:space:]]*\*)/s/^/#/' \
                   -e '/^[[:space:]]*esac/s/^/#/' "$script_path"

            # Добавляем строку с автоматической установкой HUGGINGFACE_ACCESS_TOKEN="None"
            tmp_file=$(mktemp) # Новый временный файл
            awk '/^#.*yn=\${yn:-N}/{print; print "    HUGGINGFACE_ACCESS_TOKEN=\"None\""; next}1' "$script_path" > "$tmp_file"

            if [ $? -eq 0 ] && mv "$tmp_file" "$script_path"; then
                echo -e "${GREEN}[✓] Hugging Face вопрос удален.${NC}"
            else
                echo -e "${RED}${BOLD}[✗] Ошибка модификации Hugging Face.${NC}"
                rm -f "$tmp_file"
                success=false
            fi
        fi

        # Итоговый результат
        if [ "$success" = true ]; then
            echo -e "${GREEN}${BOLD}[✓] Скрипт ${script_path} успешно модифицирован (Protobuf, Auto Testnet/HF).${NC}"
            return 0
        else
             echo -e "${RED}${BOLD}[✗] Общая ошибка модификации ${script_path}.${NC}"
            return 1
        fi
    else
        echo -e "${RED}${BOLD}[✗] Скрипт ${script_path} не найден для модификации.${NC}"
        return 1
    fi
}

# Функция для отложенного запуска мониторинга
delayed_monitoring_start() {
    # Проверяем, не запущен ли уже отложенный запуск
    if pgrep -f "sleep.*enable_monitoring" >/dev/null; then
        return 0
    fi
    
    echo -e "${YELLOW}[!] Планирование автоматического запуска мониторинга через 10 минут...${NC}"
    
    # Запускаем отложенную активацию мониторинга в фоновом режиме через nohup
    nohup bash -c "sleep 600 && cd $(pwd) && source $(pwd)/gen.sh && if ! [ -f '$MONITOR_PID_FILE' ] || ! kill -0 \$(cat '$MONITOR_PID_FILE') 2>/dev/null; then enable_monitoring; fi" > /dev/null 2>&1 &
    
    echo -e "${GREEN}[✓] Мониторинг будет автоматически запущен через 10 минут, если еще не активен.${NC}"
}

# Функция для установки и запуска ноды
install_and_run() {
    echo -e "${BLUE}${BOLD}=== Установка зависимостей ===${NC}"
    apt update && apt install -y sudo
    sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl wget screen git lsof nano unzip || { echo -e "${RED}${BOLD}[✗] Ошибка установки зависимостей.${NC}"; exit 1; }
    echo -e "${GREEN}${BOLD}[✓] Зависимости установлены.${NC}"

    echo -e "${BLUE}${BOLD}=== Запуск установочных скриптов ===${NC}"
    curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash || { echo -e "${RED}${BOLD}[✗] Ошибка выполнения первого скрипта node.sh.${NC}"; exit 1; }
    curl -sSL https://raw.githubusercontent.com/zunxbt/installation/main/node.sh | bash || { echo -e "${RED}${BOLD}[✗] Ошибка выполнения второго скрипта node.sh.${NC}"; exit 1; }
    echo -e "${GREEN}${BOLD}[✓] Установочные скрипты выполнены.${NC}"

    echo -e "${BLUE}${BOLD}=== Подготовка репозитория ===${NC}"

    local use_existing_swarm="n"
    local existing_userData="n"
    local existing_userApi="n"

    # Проверка swarm.pem в $HOME
    if [ -f "$HOME_DIR/swarm.pem" ]; then
        echo -e "${BOLD}${YELLOW}Найден файл ${GREEN}$HOME_DIR/swarm.pem${YELLOW}.${NC}"
        read -p $'\e[1mИспользовать его для этой ноды? (y/N): \e[0m' confirm_swarm
        if [[ "$confirm_swarm" =~ ^[Yy]$ ]]; then
            use_existing_swarm="y"
            echo -e "${GREEN}[✓] Будет использован существующий swarm.pem.${NC}"
            # Проверяем связанные файлы только если используем swarm.pem
            if [ -f "$HOME_DIR/userData.json" ]; then
                echo -e "${YELLOW}[!] Найден файл ${GREEN}$HOME_DIR/userData.json${YELLOW}. Он будет перемещен.${NC}"
                existing_userData="y"
            fi
             if [ -f "$HOME_DIR/userApiKey.json" ]; then
                echo -e "${YELLOW}[!] Найден файл ${GREEN}$HOME_DIR/userApiKey.json${YELLOW}. Он будет перемещен.${NC}"
                existing_userApi="y"
            fi
        else
             echo -e "${YELLOW}[!] Существующий $HOME_DIR/swarm.pem будет проигнорирован.${NC}"
        fi
    else
        echo -e "${YELLOW}[!] Файл $HOME_DIR/swarm.pem не найден. Будет сгенерирован новый при первом запуске.${NC}"
    fi

    # Удаление старой директории rl-swarm и клонирование
    echo -e "${BLUE}${BOLD}=== Клонирование репозитория ===${NC}"
    cd "$HOME" || { echo -e "${RED}${BOLD}[✗] Не удалось перейти в директорию $HOME.${NC}"; exit 1; }

    if [ -d "$SWARM_DIR" ]; then
        echo -e "${YELLOW}[!] Обнаружена существующая директория $SWARM_DIR. Удаление...${NC}"
        rm -rf "$SWARM_DIR"
        if [ $? -ne 0 ]; then
            echo -e "${RED}${BOLD}[✗] Не удалось удалить существующую директорию $SWARM_DIR.${NC}"
            exit 1
        fi
        echo -e "${GREEN}${BOLD}[✓] Существующая директория $SWARM_DIR удалена.${NC}"
    fi

    echo -e "${BOLD}${YELLOW}[✓] Клонирование репозитория из https://github.com/gensyn-ai/rl-swarm.git...${NC}"
    git clone https://github.com/gensyn-ai/rl-swarm.git "$SWARM_DIR" # Клонируем сразу в нужную папку
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}[✗] Ошибка клонирования репозитория.${NC}"
        exit 1
    fi
    echo -e "${GREEN}${BOLD}[✓] Репозиторий успешно клонирован в $SWARM_DIR.${NC}"

    # Перемещение существующих файлов, если пользователь согласился
    if [ "$use_existing_swarm" == "y" ]; then
        echo -e "${YELLOW}[!] Перемещение $HOME_DIR/swarm.pem в $SWARM_DIR/...${NC}"
        mv "$HOME_DIR/swarm.pem" "$SWARM_DIR/swarm.pem" || { echo -e "${RED}[✗] Ошибка перемещения swarm.pem${NC}"; exit 1; }

        # Создаем директорию для userData и userApi если нужно
        mkdir -p "$SWARM_DIR/modal-login/temp-data"

        if [ "$existing_userData" == "y" ]; then
             echo -e "${YELLOW}[!] Перемещение $HOME_DIR/userData.json...${NC}"
             mv "$HOME_DIR/userData.json" "$SWARM_DIR/modal-login/temp-data/" || echo -e "${RED}[!] Не удалось переместить userData.json (возможно, он уже был удален)${NC}"
        fi
        if [ "$existing_userApi" == "y" ]; then
             echo -e "${YELLOW}[!] Перемещение $HOME_DIR/userApiKey.json...${NC}"
             mv "$HOME_DIR/userApiKey.json" "$SWARM_DIR/modal-login/temp-data/" || echo -e "${RED}[!] Не удалось переместить userApiKey.json (возможно, он уже был удален)${NC}"
        fi
         echo -e "${GREEN}${BOLD}[✓] Существующие файлы конфигурации перемещены.${NC}"
    fi

    # Модифицируем скрипт run_rl_swarm.sh
    modify_run_script "$SWARM_DIR" || exit 1

    # Добавляем отладку set -x / set +x вокруг блока Testnet
    echo -e "${YELLOW}[!] Добавление временной отладки (set -x) в run_rl_swarm.sh...${NC}"
    local tmp_debug=$(mktemp)
    awk '
    /^if \\[ \"\$CONNECT_TO_TESTNET\" = \"True\" \\]; then/ {
        print "set -x # Temporary debug"
    }
    { print }
    /^pip_install\(\) {/ {
         print "set +x # End temporary debug"
    }
    ' "$script_path" > "$tmp_debug"

    if [ $? -eq 0 ]; then
        mv "$tmp_debug" "$script_path"
        echo -e "${GREEN}[✓] Временная отладка добавлена.${NC}"
    else
        echo -e "${RED}${BOLD}[✗] Ошибка добавления временной отладки.${NC}"
        rm -f "$tmp_debug"
        # Не выходим, просто продолжаем без отладки
    fi

    # Добавляем права на выполнение
    echo -e "${YELLOW}[!] Добавление прав на выполнение для run_rl_swarm.sh...${NC}"
    chmod +x "$SWARM_DIR/run_rl_swarm.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}[✗] Не удалось добавить права на выполнение для run_rl_swarm.sh.${NC}"
        exit 1
    fi
    echo -e "${GREEN}${BOLD}[✓] Права на выполнение добавлены.${NC}"

    # Переходим в директорию ноды
    cd "$SWARM_DIR" || { echo -e "${BOLD}${RED}[✗] Не удалось перейти в директорию $SWARM_DIR. Выход.${NC}"; exit 1; }

    # Настройка и запуск в screen
    echo -e "${BLUE}${BOLD}=== Запуск ноды в screen ===${NC}"
    local run_script_cmd="
    if [ -n \\\"\$VIRTUAL_ENV\\\" ]; then
        echo -e '${BOLD}${YELLOW}[✓] Деактивация существующего виртуального окружения...${NC}'
        [ -n \"\$VIRTUAL_ENV\" ] && deactivate
    fi
    echo -e '${BOLD}${YELLOW}[✓] Настройка виртуального окружения Python...${NC}'
    python3 -m venv .venv && source .venv/bin/activate || { echo -e '${RED}${BOLD}[✗] Ошибка настройки виртуального окружения.${NC}'; exit 1; }
    echo -e '${BOLD}${YELLOW}[✓] Запуск rl-swarm...${NC}'
    ./run_rl_swarm.sh # Убрали echo 'N' |
    echo -e '${GREEN}${BOLD}Скрипт rl-swarm завершил работу. Нажмите Enter для выхода из screen.${NC}'
    read # Ждем нажатия Enter перед выходом из скрипта внутри screen
    "

    # Создание и запуск команды в screen
    echo -e "${GREEN}${BOLD}[✓] Создание screen сессии 'gensyn' и запуск ноды...${NC}"
    screen -dmS gensyn bash -c "cd $SWARM_DIR && $run_script_cmd; exec bash"

    echo -e "${GREEN}${BOLD}[✓] Нода запущена в screen сессии 'gensyn'.${NC}"
    echo -e "${YELLOW}Чтобы подключиться к сессии, используйте команду: ${NC}${BOLD}screen -r gensyn${NC}"
    echo -e "${YELLOW}Чтобы отключиться от сессии (оставив ноду работать), нажмите ${NC}${BOLD}Ctrl+A, затем D${NC}"
    
    # Запускаем мониторинг с задержкой
    delayed_monitoring_start
}

# Функция для перезапуска ноды
restart_node() {
    echo -e "${BLUE}${BOLD}=== Перезапуск ноды ===${NC}"

    # Проверка, существует ли сессия screen
    if screen -list | grep -q "gensyn"; then
        echo -e "${YELLOW}[!] Завершение работы текущей ноды в screen 'gensyn'...${NC}"
        # Отправляем Ctrl+C в screen
        screen -S gensyn -p 0 -X stuff $'\003'
        sleep 2 # Даем время на обработку Ctrl+C
        # Завершаем сессию окончательно
        screen -S gensyn -X quit 2>/dev/null
    else
        echo -e "${YELLOW}[!] Screen сессия 'gensyn' не найдена.${NC}"
    fi

    echo -e "${YELLOW}[!] Завершение оставшихся процессов...${NC}"
    pkill -f hivemind_exp.gsm8k.train_single_gpu
    pkill -f hivemind/hivemind_cli/p2pd
    pkill -f run_rl_swarm.sh
    sleep 2

    # Проверяем наличие директории ноды
    if [ ! -d "$SWARM_DIR" ]; then
        echo -e "${RED}${BOLD}[✗] Директория ${SWARM_DIR} не найдена. Возможно, нода не была установлена?${NC}"
        return 1
    fi

    # Добавляем отладку set -x / set +x вокруг блока Testnet (при перезапуске)
    echo -e "${YELLOW}[!] Добавление временной отладки (set -x) в run_rl_swarm.sh при перезапуске...${NC}"
    local tmp_debug_restart=$(mktemp)
     awk '
    /^if \\[ \"\$CONNECT_TO_TESTNET\" = \"True\" \\]; then/ {
        print "set -x # Temporary debug"
    }
    { print }
    # Добавляем комментарий-якорь, если его нет, для set +x
    # /^[[:space:]]*fi[[:space:]]*$/ && !/End of CONNECT_TO_TESTNET block/ { $0 = $0 " # End of CONNECT_TO_TESTNET block" }
    # /^fi # End of CONNECT_TO_TESTNET block/ {
    /^pip_install\(\) {/ { # Вставляем перед определением функции pip_install
         print "set +x # End temporary debug"
    }
    ' "$script_path" > "$tmp_debug_restart"
    
    if [ $? -eq 0 ]; then
        mv "$tmp_debug_restart" "$script_path"
        echo -e "${GREEN}[✓] Временная отладка добавлена.${NC}"
    else
        echo -e "${RED}${BOLD}[✗] Ошибка добавления временной отладки при перезапуске.${NC}"
        rm -f "$tmp_debug_restart"
    fi

    # Добавляем права на выполнение (ВАЖНО после modify_run_script)
    echo -e "${YELLOW}[!] Добавление прав на выполнение для run_rl_swarm.sh при перезапуске...${NC}"
    chmod +x "$SWARM_DIR/run_rl_swarm.sh"
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}[✗] Не удалось добавить права на выполнение для run_rl_swarm.sh при перезапуске.${NC}"
        return 1
    fi
    echo -e "${GREEN}${BOLD}[✓] Права на выполнение добавлены.${NC}"

     # Команда для запуска внутри screen
     local restart_script_cmd="
     cd $SWARM_DIR || { echo -e '${RED}${BOLD}[✗] Не удалось перейти в директорию ${SWARM_DIR}. Выход.'; exit 1; }
     echo -e '${BOLD}${YELLOW}[✓] Активация виртуального окружения...${NC}'
     source .venv/bin/activate || { echo -e '${RED}${BOLD}[✗] Ошибка активации виртуального окружения.${NC}'; exit 1; }
     echo -e '${BOLD}${YELLOW}[✓] Запуск rl-swarm...${NC}'
     ./run_rl_swarm.sh # Запускаем существующий скрипт
     echo -e '${GREEN}${BOLD}Скрипт rl-swarm завершил работу. Нажмите Enter для выхода из screen.${NC}'
     read # Ждем нажатия Enter перед выходом из скрипта внутри screen
     "

    # Запуск новой ноды в screen
    echo -e "${GREEN}${BOLD}[✓] Запуск новой ноды в screen сессии 'gensyn'...${NC}"
    screen -dmS gensyn bash -c "$restart_script_cmd; exec bash"

    echo -e "${GREEN}${BOLD}[✓] Нода перезапущена в screen сессии 'gensyn'.${NC}"
    echo -e "${YELLOW}Чтобы подключиться к сессии, используйте команду: ${NC}${BOLD}screen -r gensyn${NC}"
    
    # Запускаем мониторинг с задержкой
    delayed_monitoring_start
}

# Функция для просмотра логов (подключения к screen)
view_logs() {
    echo -e "${BLUE}${BOLD}=== Просмотр логов (подключение к screen 'gensyn') ===${NC}"
    if screen -list | grep -q "gensyn"; then
        echo -e "${YELLOW}Подключение к screen 'gensyn'... Нажмите Ctrl+A, затем D для отключения.${NC}"
        screen -r gensyn
    else
        echo -e "${RED}${BOLD}[✗] Screen сессия 'gensyn' не найдена. Нечего просматривать.${NC}"
    fi
}

# Функция для удаления ноды
delete_node() {
    echo -e "${BLUE}${BOLD}=== Удаление ноды ===${NC}"
    read -p $'\e[1m\e[31mВы уверены, что хотите удалить ноду и все связанные данные? (y/N): \e[0m' confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[!] Завершение screen сессии 'gensyn'...${NC}"
        screen -S gensyn -X quit 2>/dev/null

        echo -e "${YELLOW}[!] Завершение оставшихся процессов...${NC}"
        pkill -f hivemind_exp.gsm8k.train_single_gpu
        pkill -f hivemind/hivemind_cli/p2pd
        pkill -f run_rl_swarm.sh
        sleep 2

        echo -e "${YELLOW}[!] Удаление директории ${SWARM_DIR}...${NC}"
        rm -rf "$SWARM_DIR"

        echo -e "${GREEN}${BOLD}[✓] Нода успешно удалена.${NC}"
    else
        echo -e "${YELLOW}Удаление отменено.${NC}"
    fi
}

# Функция для включения мониторинга
enable_monitoring() {
    # Проверяем, запущен ли уже мониторинг
    if [ -f "$MONITOR_PID_FILE" ] && kill -0 "$(cat "$MONITOR_PID_FILE")" 2>/dev/null; then
        echo -e "${YELLOW}Мониторинг уже запущен (PID: $(cat "$MONITOR_PID_FILE")).${NC}"
        return 0
    fi
    
    # Создаем директорию для логов, если она не существует
    mkdir -p "$MONITOR_LOG_DIR"
    
    # Создаем скрипт монитора, который будет запущен через nohup
    local monitor_script="$MONITOR_LOG_DIR/monitor_script.sh"
    cat > "$monitor_script" << 'EOF'
#!/bin/bash
MONITOR_LOG_FILE="$1"
SWARM_DIR="$2"

# Функция проверки использования памяти
check_memory_usage() {
    # Получаем статистику памяти из команды free
    local mem_stats=$(free | grep Mem)
    local total_mem=$(echo $mem_stats | awk '{print $2}')
    local used_mem=$(echo $mem_stats | awk '{print $3}')
    local mem_usage_percent=$(( (used_mem * 100) / total_mem ))
    
    # Записываем данные в лог
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] Использование памяти: $mem_usage_percent%" >> "$MONITOR_LOG_FILE"
    
    # Проверяем, если использование памяти меньше 20%, перезапускаем ноду
    if [ $mem_usage_percent -lt 20 ]; then
        echo "[$timestamp] ВНИМАНИЕ: Низкое использование памяти ($mem_usage_percent%). Перезапуск ноды..." >> "$MONITOR_LOG_FILE"
        # Вызываем функцию перезапуска
        "$SWARM_DIR/../restart_gensyn_node.sh"
        echo "[$timestamp] Перезапуск выполнен." >> "$MONITOR_LOG_FILE"
    fi
}

# Функция для проверки наличия ошибок в логах screen
check_screen_logs() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    
    # Проверяем, существует ли сессия screen
    if ! screen -list | grep -q "gensyn"; then
        echo "[$timestamp] Screen сессия 'gensyn' не найдена. Пропускаем проверку логов." >> "$MONITOR_LOG_FILE"
        return 0
    fi
    
    # Сохраняем содержимое экрана screen в временный файл
    local tmp_log_file=$(mktemp)
    # Используем hardcopy для получения содержимого экрана screen
    screen -S gensyn -X hardcopy "$tmp_log_file"
    
    # Проверяем наличие ошибок
    if grep -q -E "timed out|KeyError: 'question'|Killed|AttributeError: 'NoneType' object has no attribute 'split'" "$tmp_log_file"; then
        local error_type="unknown"
        if grep -q "timed out" "$tmp_log_file"; then
            error_type="timed out"
        elif grep -q "KeyError: 'question'" "$tmp_log_file"; then
            error_type="KeyError: 'question'"
        elif grep -q "Killed" "$tmp_log_file"; then
            error_type="Killed"
        elif grep -q "AttributeError: 'NoneType' object has no attribute 'split'" "$tmp_log_file"; then
            error_type="AttributeError: NoneType split"
        fi
        
        echo "[$timestamp] ВНИМАНИЕ: Обнаружена ошибка '$error_type' в логах. Перезапуск ноды..." >> "$MONITOR_LOG_FILE"
        # Удаляем временный файл
        rm -f "$tmp_log_file"
        # Вызываем функцию перезапуска
        "$SWARM_DIR/../restart_gensyn_node.sh"
        echo "[$timestamp] Перезапуск выполнен из-за ошибки '$error_type'." >> "$MONITOR_LOG_FILE"
    else
        echo "[$timestamp] Ошибок в логах не обнаружено." >> "$MONITOR_LOG_FILE"
        # Удаляем временный файл
        rm -f "$tmp_log_file"
    fi
}

# Основной цикл проверки
while true; do
    check_memory_usage
    check_screen_logs
    sleep 1800 # 30 минут
done
EOF

    # Создаем скрипт для перезапуска ноды
    local restart_script="$HOME/restart_gensyn_node.sh"
    cat > "$restart_script" << EOF
#!/bin/bash

# Функция для перезапуска ноды
restart_node() {
    # Проверка, существует ли сессия screen
    if screen -list | grep -q "gensyn"; then
        # Отправляем Ctrl+C в screen
        screen -S gensyn -p 0 -X stuff $'\003'
        sleep 2 # Даем время на обработку Ctrl+C
        # Завершаем сессию окончательно
        screen -S gensyn -X quit 2>/dev/null
    fi

    # Завершение оставшихся процессов
    pkill -f hivemind_exp.gsm8k.train_single_gpu
    pkill -f hivemind/hivemind_cli/p2pd
    pkill -f run_rl_swarm.sh
    sleep 2

    # Проверяем наличие директории ноды
    if [ ! -d "$SWARM_DIR" ]; then
        exit 1
    fi

    # Добавляем права на выполнение
    chmod +x "$SWARM_DIR/run_rl_swarm.sh"

    # Команда для запуска внутри screen
    local restart_script_cmd="
    cd $SWARM_DIR || exit 1
    echo -e 'Активация виртуального окружения...'
    source .venv/bin/activate || exit 1
    echo -e 'Запуск rl-swarm...'
    ./run_rl_swarm.sh
    "

    # Запуск новой ноды в screen
    screen -dmS gensyn bash -c "\$restart_script_cmd; exec bash"
}

# Запуск функции перезапуска
restart_node
EOF

    # Делаем скрипты исполняемыми
    chmod +x "$monitor_script"
    chmod +x "$restart_script"

    # Запускаем мониторинг через nohup, чтобы он работал даже после закрытия терминала
    echo -e "${YELLOW}[!] Запуск мониторинга, независимого от терминала...${NC}"
    nohup "$monitor_script" "$MONITOR_LOG_FILE" "$SWARM_DIR" > "$MONITOR_LOG_DIR/nohup.out" 2>&1 &
    
    # Сохраняем PID фонового процесса
    echo $! > "$MONITOR_PID_FILE"
    echo -e "${GREEN}${BOLD}[✓] Мониторинг запущен (PID: $(cat "$MONITOR_PID_FILE")) и будет работать даже после закрытия терминала.${NC}"
    echo -e "${YELLOW}Каждые 30 минут будет проверяться использование памяти и наличие ошибок.${NC}"
    echo -e "${YELLOW}Нода будет автоматически перезапущена, если:${NC}"
    echo -e "${YELLOW} - Использование памяти меньше 20%${NC}"
    echo -e "${YELLOW} - В логах обнаружены ошибки:${NC}"
    echo -e "${YELLOW}   * 'timed out'${NC}"
    echo -e "${YELLOW}   * 'KeyError: question'${NC}"
    echo -e "${YELLOW}   * 'Killed'${NC}"
    echo -e "${YELLOW}   * 'AttributeError: NoneType object has no attribute split'${NC}"
    echo -e "${YELLOW}Логи сохраняются в файл: ${MONITOR_LOG_FILE}${NC}"
}

# Функция для выключения мониторинга
disable_monitoring() {
    if [ -f "$MONITOR_PID_FILE" ]; then
        local pid=$(cat "$MONITOR_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}[!] Остановка мониторинга (PID: $pid)...${NC}"
            kill "$pid"
            rm -f "$MONITOR_PID_FILE"
            echo -e "${GREEN}${BOLD}[✓] Мониторинг остановлен.${NC}"
        else
            echo -e "${YELLOW}[!] Процесс мониторинга ($pid) не найден. Очистка данных...${NC}"
            rm -f "$MONITOR_PID_FILE"
            echo -e "${GREEN}[✓] Данные мониторинга очищены.${NC}"
        fi
    else
        echo -e "${YELLOW}[!] Мониторинг не запущен.${NC}"
    fi
}

# Функция для просмотра истории мониторинга
view_monitoring_history() {
    if [ ! -f "$MONITOR_LOG_FILE" ]; then
        echo -e "${YELLOW}[!] Файл истории мониторинга не найден.${NC}"
        return 1
    fi
    
    echo -e "${BLUE}${BOLD}=== История мониторинга ===${NC}"
    echo -e "${YELLOW}Содержимое файла ${MONITOR_LOG_FILE}:${NC}"
    echo ""
    
    # Используем tail для отображения последних 100 строк лога
    tail -n 100 "$MONITOR_LOG_FILE"
    
    echo ""
    echo -e "${YELLOW}Показаны последние 100 записей.${NC}"
}

# Функция для отображения подменю мониторинга
show_monitoring_menu() {
    while true; do
        echo -e "\n${BLUE}${BOLD}======= Подменю мониторинга ========${NC}"
        echo -e "${GREEN}1)${NC} Включить мониторинг"
        echo -e "${RED}2)${NC} Выключить мониторинг"
        echo -e "${BLUE}3)${NC} Просмотреть историю мониторинга"
        echo -e "--------------------------------------------------"
        echo -e "${BOLD}0)${NC} Вернуться в главное меню"
        echo -e "=================================================="
        
        # Показываем статус мониторинга
        if [ -f "$MONITOR_PID_FILE" ] && kill -0 "$(cat "$MONITOR_PID_FILE")" 2>/dev/null; then
            echo -e "${GREEN}Статус мониторинга: ВКЛЮЧЕН (PID: $(cat "$MONITOR_PID_FILE"))${NC}"
        else
            echo -e "${RED}Статус мониторинга: ВЫКЛЮЧЕН${NC}"
        fi
        
        read -p $'\e[1mВведите номер пункта подменю: \e[0m' choice
        echo "" # Новая строка для лучшей читаемости
        
        case $choice in
            1)
                enable_monitoring
                ;;
            2)
                disable_monitoring
                ;;
            3)
                view_monitoring_history
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}${BOLD}[✗] Неверный выбор. Пожалуйста, попробуйте снова.${NC}"
                ;;
        esac
        
        # Пауза перед повторным показом подменю
        echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
        read -r
    done
}

# Функция для отображения меню
show_menu() {
    echo -e "\n${BLUE}${BOLD}========= Меню управления нодой Gensyn ==========${NC}"
    echo -e "${GREEN}1)${NC} Установить и запустить ноду"
    echo -e "${YELLOW}2)${NC} Перезапустить ноду"
    echo -e "${BLUE}3)${NC} Посмотреть логи (подключиться к screen)"
    echo -e "${RED}4)${NC} Удалить ноду"
    echo -e "${GREEN}5)${NC} Мониторинг ноды"
    echo -e "--------------------------------------------------"
    echo -e "${BOLD}0)${NC} Выход"
    echo -e "=================================================="
}

# Основной цикл скрипта
while true; do
    show_menu
    read -p $'\e[1mВведите номер пункта меню: \e[0m' choice
    echo "" # Новая строка для лучшей читаемости

    case $choice in
        1)
            install_and_run
            ;;
        2)
            restart_node
            ;;
        3)
            view_logs
            ;;
        4)
            delete_node
            ;;
        5)
            show_monitoring_menu
            ;;
        0)
            # Проверяем, запущен ли мониторинг при выходе
            if [ -f "$MONITOR_PID_FILE" ] && kill -0 "$(cat "$MONITOR_PID_FILE")" 2>/dev/null; then
                echo -e "${YELLOW}[!] Мониторинг остается активным и будет работать в фоновом режиме.${NC}"
                echo -e "${YELLOW}    Для его отключения используйте пункт меню '5 -> 2'.${NC}"
            fi
            echo -e "${GREEN}Выход из скрипта.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}${BOLD}[✗] Неверный выбор. Пожалуйста, попробуйте снова.${NC}"
            ;;
    esac

    # Пауза перед повторным показом меню, если не был выбран выход
    if [ "$choice" != "0" ]; then
      echo -e "\n${YELLOW}Нажмите Enter для возврата в меню...${NC}"
      read -r
    fi
done
