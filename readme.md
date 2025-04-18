# GenSyn Node - Управление нодой Gensyn

Скрипт для автоматизации установки, запуска и управления нодой Gensyn на Linux/macOS.

## Особенности

- ✅ Полная автоматизация установки и запуска ноды Gensyn
- ✅ Автоматическое сохранение и переиспользование `swarm.pem` для сохранения заработанных очков
- ✅ Запуск ноды в фоновом режиме через `screen`
- ✅ Быстрый перезапуск без потери данных
- ✅ Удобное меню с цветным интерфейсом
- ✅ Встроенная система мониторинга памяти с автоматическим перезапуском
- ✅ Подробные логи и вывод для диагностики

## Быстрый старт

```bash
rm -f gen.sh && wget -nc --no-cache https://raw.githubusercontent.com/node-trip/GenSyn-Node/refs/heads/main/gen.sh && chmod +x gen.sh && ./gen.sh
```

## Детальная инструкция

### Установка

1. Выполните команду быстрого старта из раздела выше
2. Выберите пункт 1 в меню для установки ноды
3. Если у вас уже был файл `swarm.pem`, нода автоматически сохранит ваш прогресс

### Первый запуск (для новых пользователей)

При первой установке, если у вас еще нет файлов `swarm.pem`, `userData.json` и `userApiKey.json`, потребуется выполнить дополнительные шаги:

1. После установки и запуска ноды (пункт 1 меню), подключитесь к логам через пункт 3 меню
2. В логах вы увидите сообщение: **"Please visit this website and log in using your email"** со ссылкой
3. Перейдите по этой ссылке и выполните вход с использованием вашей электронной почты
4. После подтверждения почты необходимые файлы будут автоматически созданы
5. Нода начнет свою работу после успешной авторизации

Это действие нужно выполнить только один раз. При последующих запусках или перезапусках файлы будут использоваться автоматически.

### Меню управления

Скрипт имеет интуитивно понятное меню с несколькими пунктами:

#### 1) Установить и запустить ноду

Этот пункт выполняет:
- Установку необходимых зависимостей (Python, Node.js и др.)
- Клонирование репозитория Gensyn
- Модификацию скрипта для работы без интерактивных запросов
- Установку Node.js зависимостей
- Создание виртуального окружения Python
- Запуск ноды в фоновом режиме через `screen`

Если найден существующий файл `swarm.pem`, он будет переиспользован.

#### 2) Перезапустить ноду

Быстрый перезапуск ноды с сохранением всех настроек и `swarm.pem`. Используйте этот пункт, если нода перестала работать.

#### 3) Посмотреть логи

Подключение к сессии `screen` для просмотра логов работающей ноды.

Для отключения от сессии без остановки ноды нажмите `Ctrl+A`, затем `D`.

#### 4) Удалить ноду

Полная очистка всех данных ноды. **Внимание:** Это удалит ваш файл `swarm.pem` и все заработанные очки!

#### 5) Мониторинг использования памяти

Подменю управления мониторингом памяти, включающее:

1. **Включить мониторинг** - Запускает фоновый процесс, который каждые 30 минут проверяет использование памяти.
2. **Выключить мониторинг** - Останавливает процесс мониторинга.
3. **Просмотреть историю мониторинга** - Показывает логи мониторинга, включая автоматические перезапуски.

Если использование памяти меньше 10%, мониторинг автоматически перезапустит ноду, так как это означает, что нода, вероятно, остановилась.

## Особенности системы мониторинга

Мониторинг памяти работает в фоновом режиме и сохраняется даже после выхода из скрипта. При повторном входе в скрипт вы можете включить или выключить мониторинг через соответствующий пункт меню.

- Все действия мониторинга записываются в файл: `$HOME/.gensyn_monitor/monitor.log`
- При выходе из скрипта с активным мониторингом вы получите уведомление
- Автоматический перезапуск ноды происходит только при использовании памяти < 10%

## Решение проблем

### Ошибка "Permission denied"

Если вы видите ошибку `Permission denied` при запуске скрипта `run_rl_swarm.sh`, используйте перезапуск ноды через пункт 2, который автоматически установит необходимые права.

### Ошибка "ModuleNotFoundError"

Если в логах вы видите ошибки связанные с отсутствием Python модулей, попробуйте удалить ноду (пункт 4) и установить ее заново (пункт 1).

### Нода запускается, но не работает

1. Проверьте логи с помощью пункта 3
2. Включите мониторинг памяти (пункт 5 -> 1)
3. Если использование памяти очень низкое (< 10%), перезапустите ноду

## Дополнительная информация

- Нода запускается в сессии `screen` с именем `gensyn`
- Все файлы ноды расположены в каталоге `$HOME/rl-swarm`
- При успешной установке `swarm.pem` будет создан автоматически
- При перезапуске ноды файлы `swarm.pem`, `userData.json` и `userApiKey.json` сохраняются

## Сохранение прогресса при переустановке

Если вы хотите сохранить свой прогресс и идентификатор ноды при переустановке или переносе на другой сервер:

1. Скопируйте следующие файлы из директории `$HOME/rl-swarm`:
   - `swarm.pem` - ваш идентификатор ноды
   - `userData.json` - данные пользователя
   - `userApiKey.json` - API ключ

2. Поместите эти файлы в корневую директорию (`$HOME`) перед запуском скрипта. Скрипт автоматически обнаружит и использует их, сохраняя ваш прогресс и идентификатор ноды.

> **Важно**: Без файла `swarm.pem` вы потеряете все заработанные очки и ваша нода будет считаться новой!

## Благодарности

Скрипт разработан сообществом для удобного управления нодой Gensyn. Если вам понравился скрипт, присоединяйтесь к нашему сообществу.

## Сообщество

Присоединяйтесь к нашему Telegram-каналу [@nodetrip](https://t.me/nodetrip) для получения обновлений, поддержки и обсуждения нод Gensyn.
