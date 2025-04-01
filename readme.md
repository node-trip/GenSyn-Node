# Установщик и Менеджер Ноды Gensyn от @nodetrip

Этот скрипт упрощает установку, настройку и управление нодой Gensyn Testnet.

## Возможности

*   **Интерактивное Меню:** Удобное меню для выполнения всех основных действий.
*   **Автоматическая Установка Зависимостей:** Скрипт проверяет и устанавливает все необходимые пакеты, включая Python 3.10+, Docker, yarn, cloudflared и другие.
*   **Установка Ноды:** Клонирует актуальный репозиторий (`SKaaalper/rl-swarm`), создает виртуальное окружение и устанавливает Python/Node.js зависимости.
*   **Автоматическая Настройка:** Модифицирует скрипт запуска ноды (`run_rl_swarm.sh`) для корректной работы на сервере (комментирует авто-открытие браузера).
*   **Управление:** Предоставляет опции для просмотра логов и полного удаления ноды.
*   **Ручной Запуск:** Предоставляет четкие инструкции для ручного запуска ноды после подготовки системы, включая запуск `cloudflared` для авторизации.

## Системные Требования

Убедитесь, что ваш сервер соответствует минимальным требованиям:

| Требование        | Детали                                      |
| :--------------- | :------------------------------------------ |
| CPU Архитектура  | `arm64` или `amd64`                         |
| Минимальная RAM  | 16 GB                                       |
| CUDA Устройства  | **Опционально:** RTX 3090, RTX 4090, A100, H100 |
| Версия Python    | >= 3.10                                     |

## Установка и Запуск

1.  **Подключитесь к вашему серверу** (рекомендуется Ubuntu 22.04).
2.  **Выполните команду:**
    ```bash
    rm -f gem.sh && wget -nc --no-cache https://raw.githubusercontent.com/node-trip/GenSyn-Node/refs/heads/main/gem.sh && chmod +x gem.sh && ./gem.sh
    ```
3.  **Выберите опцию 1** "Полная установка ноды". Скрипт установит все необходимое и подготовит систему.
4.  **Следуйте инструкциям для ручного запуска:** После завершения подготовки скрипт выведет подробные шаги, которые нужно выполнить вручную в двух окнах терминала для запуска ноды и `cloudflared`, а также для прохождения авторизации.

## Использование Меню

*   **Полная установка:** Устанавливает все зависимости и готовит ноду к ручному запуску.
*   **Просмотр логов:** Позволяет подключиться к `screen`-сессии `gensyn` (если вы ее создали при ручном запуске) для просмотра логов ноды.
*   **Удалить ноду:** Полностью удаляет директорию ноды (`rl-swarm`) и связанные `screen`-сессии.

## Перенос Ноды на Другой Сервер

Если вам нужно перенести вашу работающую ноду Gensyn на другой сервер, сохранив ее идентификатор (PeerID) и прогресс, следуйте этим шагам:

1.  **Остановите ноду:** Подключитесь к `screen`-сессии (`screen -r gensyn`, если вы ее использовали) и нажмите `Ctrl+C`, чтобы остановить процесс.
2.  **Создайте архив:** Перейдите в домашнюю директорию и создайте архив всей папки с нодой:
    ```bash
    cd $HOME
    tar -czvf rl-swarm-backup.tar.gz rl-swarm
    ```
    В этом архиве будут содержаться ваш ключ идентификации (`swarm.pem`) и данные авторизации (`userData.json`).
3.  **Скопируйте архив:** Перенесите файл `rl-swarm-backup.tar.gz` на ваш новый сервер (используя `scp`, `rsync` или любой другой удобный вам способ).
4.  **На новом сервере:**
    *   **Распакуйте архив:**
        ```bash
        cd $HOME
        tar -xzvf rl-swarm-backup.tar.gz
        ```
    *   **Установите зависимости:** Скачайте и запустите установочный скрипт `gem.sh` с помощью команды из раздела "Установка и Запуск", но выберите опцию **1 ("Полная установка") только для установки зависимостей**. **Не выполняйте** шаги ручного запуска ноды, которые предложит скрипт после установки зависимостей. Цель - только убедиться, что все пакеты (python3, docker, cloudflared и т.д.) установлены на новом сервере.
    *   **Запустите ноду вручную:** Используйте те же команды ручного запуска, что и при первоначальной установке (перейдите в папку `$HOME/rl-swarm`, активируйте окружение `source .venv/bin/activate` и запустите `./run_rl_swarm.sh`). Нода должна подхватить существующие файлы `swarm.pem` и `userData.json`. Возможно, вам **не потребуется** снова проходить авторизацию через `cloudflared`, так как файл `userData.json` уже существует. Следите за логами.

---

**🚀 Хотите больше полезных скриптов и гайдов по нодам?**

Подписывайтесь на мой Telegram-канал: **[@nodetrip](https://t.me/nodetrip)**!
