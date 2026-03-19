#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

REPO="Pumpkin-MC/Pumpkin"
PUMPKIN_DIR="$HOME/pumpkinmc_server"
BIN_DIR="/usr/local/bin"

echo "====================================================="
echo " PumpkinMC Installer for Arch Linux (Final Fix)"
echo "====================================================="

echo "=> Installing required dependencies (curl, jq, tmux, wget, unzip, tar)..."
sudo pacman -Syu --needed curl jq tmux wget unzip tar --noconfirm

echo "=> Fetching the latest release metadata from GitHub..."
API_RESPONSE=$(curl -s "https://api.github.com/repos/$REPO/releases")

# Безопасный парсинг JSON, который не падает, если список пуст
DOWNLOAD_URL=$(echo "$API_RESPONSE" | jq -r '
    [ .[]? | select(.assets != null) ] | .[0]?.assets[]? | 
    select(.name | test("linux.*x86_64|x86_64.*linux|linux.*amd64|amd64.*linux|linux"; "i")) | 
    select(.name | test("arm|aarch64") | not) | 
    .browser_download_url
' | head -n 1)

# Fallback: берем любой первый файл из последнего релиза
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | jq -r '.[0]?.assets[0]?.browser_download_url // empty')
fi

# Fallback 2: если API GitHub вообще пустой, скачиваем напрямую Nightly build из GitHub Actions
if [ -z "$DOWNLOAD_URL" ] ||[ "$DOWNLOAD_URL" == "null" ]; then
    echo "=> GitHub releases are empty. Using alternative Nightly build link..."
    DOWNLOAD_URL="https://nightly.link/Pumpkin-MC/Pumpkin/workflows/build/master/pumpkin-linux.zip"
fi

echo "=> Found release asset: $DOWNLOAD_URL"

mkdir -p "$PUMPKIN_DIR"
cd "$PUMPKIN_DIR"

# Определяем имя файла
FILE_NAME=$(basename "$DOWNLOAD_URL" | cut -d? -f1)
if[ -z "$FILE_NAME" ] || [ "$FILE_NAME" == "null" ]; then
    FILE_NAME="pumpkin-release.zip"
fi

echo "=> Downloading $FILE_NAME..."
wget -q --show-progress -O "$FILE_NAME" "$DOWNLOAD_URL"

echo "=> Extracting/Setting up the executable..."
if [[ "$FILE_NAME" == *.zip ]]; then
    unzip -o "$FILE_NAME"
    rm "$FILE_NAME"
elif [[ "$FILE_NAME" == *.tar.gz ]]; then
    tar -xzf "$FILE_NAME"
    rm "$FILE_NAME"
fi

# Делаем исполняемыми все распакованные файлы в папке
find . -maxdepth 1 -type f -exec chmod +x {} + 2>/dev/null || true

# Ищем исполняемый файл (желательно со словом pumpkin в названии)
EXECUTABLE=$(find . -maxdepth 1 -type f -executable -name "*pumpkin*" | head -n 1)

# Если не нашли по имени, берем любой
if[ -z "$EXECUTABLE" ]; then
    EXECUTABLE=$(find . -maxdepth 1 -type f -executable | head -n 1)
fi

# ПРОБЕЛЫ ТЕПЕРЬ СТОЯТ ПРАВИЛЬНО
if [ -z "$EXECUTABLE" ] || [ ! -f "$EXECUTABLE" ]; then
    EXECUTABLE="./pumpkin"
    chmod +x "$EXECUTABLE" 2>/dev/null || true
fi

# Переименовываем бинарник для красоты и стабильности
if[ -f "$EXECUTABLE" ] && [ "$EXECUTABLE" != "./pumpkin-server" ]; then
    mv "$EXECUTABLE" ./pumpkin-server
fi
EXECUTABLE="./pumpkin-server"

echo "=> Server executable is ready at $PUMPKIN_DIR/pumpkin-server"

echo "=> Creating the 'pumpkinmc' command wrapper..."

WRAPPER_SCRIPT="/tmp/pumpkinmc"
cat << 'EOF' > "$WRAPPER_SCRIPT"
#!/bin/bash

PUMPKIN_DIR="PUMPKIN_DIR_PLACEHOLDER"
SESSION_NAME="pumpkin_session"

case "$1" in
    run|start)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "PumpkinMC is already running in tmux session: $SESSION_NAME"
        else
            echo "Starting PumpkinMC in tmux session..."
            cd "$PUMPKIN_DIR" || exit
            tmux new-session -d -s "$SESSION_NAME" "./pumpkin-server"
            echo "PumpkinMC started successfully."
            echo "Use 'pumpkinmc console' to view the server logs and interact with it."
        fi
        ;;
    stop)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "Stopping PumpkinMC gracefully..."
            tmux send-keys -t "$SESSION_NAME" "stop" C-m
            echo "Stop command sent. Waiting for server to save and exit..."
            
            for i in {1..15}; do
                if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            
            if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                echo "Server is taking too long to stop. Forcing shutdown..."
                tmux send-keys -t "$SESSION_NAME" C-c
                sleep 2
                tmux kill-session -t "$SESSION_NAME" 2>/dev/null
            fi
            echo "PumpkinMC stopped."
        else
            echo "PumpkinMC is not currently running."
        fi
        ;;
    console|attach)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "Attaching to console. Press 'Ctrl+B' and then 'D' to detach (do NOT press Ctrl+C to close)."
            sleep 2
            tmux attach-session -t "$SESSION_NAME"
        else
            echo "PumpkinMC is not running."
        fi
        ;;
    status)
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "PumpkinMC is RUNNING."
        else
            echo "PumpkinMC is STOPPED."
        fi
        ;;
    *)
        echo "Usage: pumpkinmc {run|stop|console|status}"
        exit 1
        ;;
esac
EOF

chmod +x "$WRAPPER_SCRIPT"

sed -i "s|PUMPKIN_DIR_PLACEHOLDER|$PUMPKIN_DIR|g" "$WRAPPER_SCRIPT"

echo "=> Moving wrapper to $BIN_DIR/pumpkinmc (requires sudo)..."
sudo mv "$WRAPPER_SCRIPT" "$BIN_DIR/pumpkinmc"

echo ""
echo "====================================================="
echo " Installation Complete!"
echo "====================================================="
echo "=> Starting the server for the first time..."
pumpkinmc run
