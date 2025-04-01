#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Баннер
print_banner() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Gensyn Node Installation & Manager     ║${NC}"
    echo -e "${BLUE}║        Created by @nodetrip                ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════╝${NC}"
    echo ""
}

# Проверка зависимостей
check_dependencies() {
    local deps=(python3 python3-venv python3-pip curl screen git yarn nodejs npm build-essential)
    if ! command -v cloudflared &>/dev/null; then
        echo -e "${YELLOW}Добавляем cloudflared в список для установки...${NC}"
        deps+=(cloudflared)
    fi
    local missing_deps=()

    for dep in "${deps[@]}"; do
        if ! command -v $dep &>/dev/null && ! dpkg -l | grep -q "^ii.*$dep"; then
            missing_deps+=($dep)
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}Установка отсутствующих зависимостей: ${missing_deps[*]}${NC}"
        sudo apt update
        sudo apt install -y "${missing_deps[@]}"
    fi

    # Проверка версии Python
    python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    if (( $(echo "$python_version < 3.10" | bc -l) )); then
        echo -e "${RED}Требуется Python версии 3.10 или выше. Текущая версия: $python_version${NC}"
        exit 1
    fi
}

# Установка и настройка cloudflared
setup_cloudflared() {
    print_banner
    echo -e "${YELLOW}Установка и настройка cloudflared...${NC}"
    
    # Останавливаем существующие процессы cloudflared
    pkill cloudflared 2>/dev/null
    screen -X -S cloudflared quit 2>/dev/null
    
    # Установка cloudflared
    if ! command -v cloudflared &>/dev/null; then
        echo -e "${YELLOW}Устанавливаем cloudflared...${NC}"
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        sudo dpkg -i cloudflared.deb
        rm cloudflared.deb
    fi

    # Запускаем cloudflared и сохраняем URL
    echo -e "${YELLOW}Создаем туннель cloudflared...${NC}"
    cloudflared_output=$(mktemp)
    screen -dmS cloudflared bash -c "cloudflared tunnel --url http://localhost:3000 2>&1 | tee $cloudflared_output"
    
    # Ждем появления URL в логах
    echo -e "${YELLOW}Ожидаем создания туннеля...${NC}"
    tunnel_url=""
    for i in {1..30}; do
        if [ -f "$cloudflared_output" ]; then
            tunnel_url=$(grep -o "https://.*\.trycloudflare\.com" "$cloudflared_output" || true)
            if [ ! -z "$tunnel_url" ]; then
                break
            fi
        fi
        echo -n "."
        sleep 2
    done
    
    if [ ! -z "$tunnel_url" ]; then
        echo -e "\n${GREEN}Туннель успешно создан!${NC}"
        echo -e "${YELLOW}URL для авторизации:${NC}"
        echo -e "${GREEN}$tunnel_url${NC}"
        # Сохраняем URL для использования в других функциях
        echo "$tunnel_url" > $HOME/.cloudflared_url
    else
        echo -e "\n${RED}Не удалось получить URL туннеля. Пожалуйста, попробуйте перезапустить установку.${NC}"
        return 1
    fi
}

# Установка Docker
install_docker() {
    print_banner
    echo -e "${YELLOW}Установка Docker...${NC}"
    
    # Удаление старых версий
    for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
        sudo apt-get remove $pkg;
    done

    # Установка необходимых пакетов
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Добавление репозитория
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Установка Docker
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Добавление пользователя в группу docker
    sudo usermod -aG docker $USER
    
    echo -e "${GREEN}Docker успешно установлен!${NC}"
}

# Проверка и запуск Docker демона
check_docker_daemon() {
    echo -e "${YELLOW}Проверка статуса Docker демона...${NC}"
    if ! systemctl is-active --quiet docker; then
        echo -e "${YELLOW}Docker демон не запущен. Запускаем...${NC}"
        sudo systemctl start docker
        sudo systemctl enable docker
        sleep 5
    fi
}

# Просмотр логов
view_logs() {
    print_banner
    if screen -list | grep -q "gensyn"; then
        echo -e "${GREEN}Подключаемся к screen сессии gensyn...${NC}"
        echo -e "${YELLOW}При первом запуске ответьте на вопросы:${NC}"
        echo -e "1. ${GREEN}Would you like to connect to the Testnet? [Y/n]${NC} - выберите ${GREEN}Y${NC}"
        echo -e "2. ${GREEN}Would you like to push models you train in the RL swarm to the Hugging Face Hub? [y/N]${NC} - выберите ${GREEN}N${NC}"
        echo -e "\n${YELLOW}Для отключения нажмите Ctrl+A затем D${NC}"
        sleep 2
        screen -r gensyn
    else
        echo -e "${RED}Screen сессия gensyn не найдена!${NC}"
    fi
}

# Удаление ноды
remove_node() {
    print_banner
    echo -e "${RED}Вы уверены, что хотите удалить ноду? (y/n)${NC}"
    read -r confirm
    if [[ $confirm == "y" || $confirm == "Y" ]]; then
        screen -X -S gensyn quit 2>/dev/null
        screen -X -S cloudflared quit 2>/dev/null
        pkill cloudflared 2>/dev/null
        cd $HOME
        rm -rf rl-swarm
        rm -f $HOME/.cloudflared_url
        echo -e "${GREEN}Нода успешно удалена${NC}"
    fi
}

# Полная установка
full_install() {
    print_banner
    echo -e "${GREEN}Начинаем полную установку ноды Gensyn...${NC}"
    
    # 1. Очистка предыдущей установки
    echo -e "${YELLOW}Очистка предыдущей установки...${NC}"
    screen -X -S gensyn quit 2>/dev/null
    screen -X -S cloudflared quit 2>/dev/null
    pkill cloudflared 2>/dev/null
    cd $HOME
    rm -rf rl-swarm
    rm -f $HOME/.cloudflared_url
    
    # 2. Проверка и установка зависимостей
    check_dependencies
    
    # 3. Установка xdg-utils
    echo -e "${YELLOW}Установка xdg-utils...${NC}"
    sudo apt-get update
    sudo apt-get install -y xdg-utils
    
    # 4. Установка Docker
    echo -e "${YELLOW}Установка Docker...${NC}"
    install_docker
    
    # 5. Проверка и запуск Docker демона
    check_docker_daemon
    
    # 6. Установка ноды
    echo -e "${YELLOW}Установка ноды...${NC}"
    cd $HOME
    git clone https://github.com/SKaaalper/rl-swarm.git
    cd rl-swarm
    python3 -m venv .venv
    source .venv/bin/activate
    
    # Установка зависимостей Python и Node.js
    echo -e "${YELLOW}Установка зависимостей...${NC}"
    pip install --upgrade pip
    pip install -r requirements.txt
    yarn install
    
    # 8. Модифицируем run_rl_swarm.sh
    echo -e "${YELLOW}Модификация run_rl_swarm.sh...${NC}"
    # Комментируем авто-открытие браузера
    # sed -i 's/open/xdg-open/g' run_rl_swarm.sh # Эта замена может быть не нужна, если xdg-utils установлен
    sed -i '/xdg-open http:\/\/localhost:3000/s/^/#/' run_rl_swarm.sh
    # Убираем сложную вставку cloudflared logic
    chmod +x run_rl_swarm.sh
    
    # 9. НЕ запускаем ноду автоматически. Выводим инструкции для ручного запуска.
    echo -e "${GREEN}Подготовка завершена! Нода НЕ запущена автоматически.${NC}"
    echo -e "${YELLOW}Для запуска ноды выполните вручную СЛЕДУЮЩИЕ КОМАНДЫ ПО ПОРЯДКУ:${NC}"
    echo -e "1. ${GREEN}cd $HOME/rl-swarm${NC}"
    echo -e "2. ${GREEN}source .venv/bin/activate${NC}"
    echo -e "3. ${GREEN}./run_rl_swarm.sh${NC}"
    echo -e "${YELLOW}   -> После запуска команды выше, ответьте ${GREEN}Y${NC} на вопрос о Testnet."
    echo -e "   -> Скрипт начнет установку зависимостей и запустит сервер авторизации."
    echo -e "${YELLOW}4. В ОТДЕЛЬНОМ ОКНЕ ТЕРМИНАЛА выполните:${NC}"
    echo -e "   ${GREEN}cloudflared tunnel --url http://localhost:3000${NC}"
    echo -e "   -> Скопируйте ${GREEN}https://....trycloudflare.com${NC} URL из вывода этой команды."
    echo -e "${YELLOW}5. Откройте скопированный URL в браузере на вашем ПК и авторизуйтесь."
    echo -e "${YELLOW}6. Вернитесь в ПЕРВОЕ ОКНО ТЕРМИНАЛА (где запущен ./run_rl_swarm.sh):${NC}"
    echo -e "   -> Скрипт должен автоматически продолжить работу после авторизации (найдет userData.json)."
    echo -e "   -> Ответьте ${GREEN}N${NC} на вопрос о Hugging Face Hub."
    echo -e "   -> Нода начнет работать. Окно терминала можно будет оставить открытым или запустить в screen."
}

# Главное меню
main_menu() {
    while true; do
        print_banner
        echo -e "${GREEN}1.${NC} Полная установка ноды (рекомендуется)"
        echo -e "${GREEN}2.${NC} Просмотр логов"
        echo -e "${GREEN}3.${NC} Проверить статус cloudflared"
        echo -e "${GREEN}4.${NC} Перезапустить cloudflared"
        echo -e "${GREEN}5.${NC} Удалить ноду"
        echo -e "${GREEN}6.${NC} Выход"
        echo ""
        echo -e "${YELLOW}Выберите действие (1-6):${NC}"
        read -r choice

        case $choice in
            1) full_install ;;
            2) view_logs ;;
            3) 
                if [ -f "$HOME/.cloudflared_url" ]; then
                    echo -e "${GREEN}URL для авторизации:${NC}"
                    cat $HOME/.cloudflared_url
                else
                    echo -e "${RED}URL не найден. Запустите полную установку.${NC}"
                fi
                ;;
            4) 
                stop_cloudflared 2>/dev/null
                setup_cloudflared
                ;;
            5) remove_node ;;
            6) exit 0 ;;
            *) echo -e "${RED}Неверный выбор!${NC}" ;;
        esac
        
        if [[ $choice != "2" ]]; then
            echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
            read -r
        fi
    done
}

# Запуск скрипта
main_menu

restart_services() {
    print_banner
    echo -e "${YELLOW}Перезапуск сервисов...${NC}"
    
    # Останавливаем существующие сессии
    screen -X -S gensyn quit 2>/dev/null
    screen -X -S cloudflared quit 2>/dev/null
    
    # Перезапускаем ноду
    cd $HOME/rl-swarm
    source .venv/bin/activate
    ./run_rl_swarm.sh
    
    echo -e "${YELLOW}Ждем запуска ноды...${NC}"
    sleep 30
    
    # Перезапускаем cloudflared
    screen -dmS cloudflared bash -c 'cloudflared tunnel --url http://localhost:3000'
    
    echo -e "${YELLOW}Получаем новый URL...${NC}"
    sleep 5
    echo -e "${GREEN}Новый URL для авторизации:${NC}"
    screen -S cloudflared -X hardcopy .cloudflared.log
    grep -o "https://.*trycloudflare.com" .cloudflared.log
    rm .cloudflared.log
}

sudo ufw allow 3000/tcp
sudo ufw status

sudo apt update && sudo apt install -y python3 python3-venv python3-pip curl screen git yarn && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add - && echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list && sudo apt update && sudo apt install -y yarn

sudo apt-get install -y xdg-utils

sed -i 's/^python /python3 /' $HOME/rl-swarm/run_rl_swarm.sh
