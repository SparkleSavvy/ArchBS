#!/bin/bash

set -e

PUMPKIN_DIR="/opt/pumpkin-mc/server"
PUMPKIN_BIN="$PUMPKIN_DIR/pumpkin"
DOWNLOAD_URL="https://github.com/Pumpkin-MC/Pumpkin/releases/download/nightly/pumpkin-X64-Linux"

echo "Установка Pumpkin сервера..."

# Проверяем root права
if [[ $EUID -eq 0 ]]; then
   echo "Этот скрипт не должен запускаться от root."
   exit 1
fi

# Установка sudo, если нужно
if ! command -v sudo &> /dev/null; then
    echo "sudo не установлен. Установите его:"
    echo "sudo pacman -S sudo"
    exit 1
fi

# Создаём директории
sudo mkdir -p "$PUMPKIN_DIR"

# Скачиваем бинарник
echo "Скачивание бинарника..."
sudo curl -L --output "$PUMPKIN_BIN" "$DOWNLOAD_URL"
sudo chmod +x "$PUMPKIN_BIN"

# Создаём исполняемый скрипт для глобальной команды
SCRIPT_PATH="/usr/local/bin/pumpkin"
sudo tee "$SCRIPT_PATH" > /dev/null << 'EOF'
#!/bin/bash

PUMPKIN_DIR="/opt/pumpkin-mc/server"
PUMPKIN_BIN="$PUMPKIN_DIR/pumpkin"
SCREEN_NAME="pumpkin-server"

case "$1" in
    run)
        if screen -list | grep -q "$SCREEN_NAME"; then
            echo "Сервер уже запущен."
        else
            cd "$PUMPKIN_DIR"
            screen -dmS "$SCREEN_NAME" "$PUMPKIN_BIN"
            echo "Сервер запущен в фоне (screen: $SCREEN_NAME)."
        fi
        ;;
    stop)
        if screen -list | grep -q "$SCREEN_NAME"; then
            screen -S "$SCREEN_NAME" -X quit
            echo "Сервер остановлен."
        else
            echo "Сервер не запущен."
        fi
        ;;
    status)
        if screen -list | grep -q "$SCREEN_NAME"; then
            echo "Сервер запущен (screen: $SCREEN_NAME)."
        else
            echo "Сервер остановлен."
        fi
        ;;
    *)
        echo "Использование: $0 {run|stop|status}"
        exit 1
        ;;
esac
EOF

sudo chmod +x "$SCRIPT_PATH"

echo "Установка завершена!"
echo "Команды: pumpkin run, pumpkin stop, pumpkin status"
