#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

REPO="Pumpkin-MC/Pumpkin"
PUMPKIN_DIR="$HOME/pumpkinmc_server"
BIN_DIR="/usr/local/bin"

echo "====================================================="
echo " PumpkinMC Installer for Arch Linux (Fixed)"
echo "====================================================="

echo "=> Installing required dependencies (curl, jq, tmux, wget, unzip, tar)..."
sudo pacman -Syu --needed curl jq tmux wget unzip tar --noconfirm

echo "=> Fetching the latest release metadata from GitHub..."
# ИСПОЛЬЗУЕМ /releases вместо /releases/latest, чтобы видеть pre-releases (ранние сборки)
API_RESPONSE=$(curl -s "https://api.github.com/repos/$REPO/releases")

# Берем самый первый релиз в списке (индекс [0]) и ищем Linux-билд
DOWNLOAD_URL=$(echo "$API_RESPONSE" | jq -r '
    .[0].assets[]? | 
    select(.name | test("linux.*x86_64|x86_64.*linux|linux.*amd64|amd64.*linux|linux"; "i")) | 
    select(.name | test("arm|aarch64") | not) | 
    .browser_download_url
' | head -n 1)

# Fallback: если конкретно linux-файла нет, берём первый попавшийся файл из самого нового релиза
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    DOWNLOAD_URL=$(echo "$API_RESPONSE" | jq -r '.[0].assets[0]?.browser_download_url // empty')
fi

# Проверка, нашли ли мы хоть что-то
if [ -z "$DOWNLOAD_URL" ] || [ "$DOWNLOAD_URL" == "null" ]; then
    echo "Error: No compiled release assets found for $REPO."
    echo "The project might not have pre-compiled binaries available at the moment."
    exit 1
fi

echo "=> Found release asset: $DOWNLOAD_URL"

# Create a dedicated directory for the server
mkdir -p "$PUMPKIN_DIR"
cd "$PUMPKIN_DIR"

FILE_NAME=$(basename "$DOWNLOAD_URL")
echo "=> Downloading $FILE_NAME..."
wget -q --show-progress -O "$FILE_NAME" "$DOWNLOAD_URL"

echo "=> Extracting/Setting up the executable..."
if [[ "$FILE_NAME" == *.zip ]]; then
    unzip -o "$FILE_NAME"
    rm "$FILE_NAME"
    EXECUTABLE=$(find . -maxdepth 1 -type f -executable | head -n 1)
elif [[ "$FILE_NAME" == *.tar.gz ]]; then
    tar -xzf "$FILE_NAME"
    rm "$FILE_NAME"
    EXECUTABLE=$(find . -maxdepth 1 -type f -executable | head -n 1)
else
    EXECUTABLE="./$FILE_NAME"
    chmod +x "$EXECUTABLE"
fi

# Fallback if find fails to locate the executable
if[ -z "$EXECUTABLE" ] || [ ! -f "$EXECUTABLE" ]; then
    EXECUTABLE="./pumpkin"
    chmod +x "$EXECUTABLE" 2>/dev/null || true
fi

# Rename the executable for consistency
mv "$EXECUTABLE" ./pumpkin-server
EXECUTABLE="./pumpkin-server"

echo "=> Server executable is ready at $PUMPKIN_DIR/pumpkin-server"

echo "=> Creating the 'pumpkinmc' command wrapper..."

WRAPPER_SCRIPT="/tmp/pumpkinmc"
cat << 'EOF' > "$WRAPPER_SCRIPT"
#!/bin/bash

# PUMPKIN_DIR_PLACEHOLDER will be replaced by the installer
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
            # Send standard 'stop' command to the Minecraft server console
            tmux send-keys -t "$SESSION_NAME" "stop" C-m
            echo "Stop command sent. Waiting for server to save and exit..."
            
            # Wait up to 15 seconds for graceful shutdown
            for i in {1..15}; do
                if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
                    break
                fi
                sleep 1
            done
            
            # Force kill if still running
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
        echo "  run     - Starts the server in a background tmux session"
        echo "  stop    - Stops the server gracefully"
        echo "  console - Attaches to the server console (Press Ctrl+B, then D to detach)"
        echo "  status  - Checks if the server is running"
        exit 1
        ;;
esac
EOF

chmod +x "$WRAPPER_SCRIPT"

# Inject the actual directory path into the wrapper script
sed -i "s|PUMPKIN_DIR_PLACEHOLDER|$PUMPKIN_DIR|g" "$WRAPPER_SCRIPT"

echo "=> Moving wrapper to $BIN_DIR/pumpkinmc (requires sudo)..."
sudo mv "$WRAPPER_SCRIPT" "$BIN_DIR/pumpkinmc"

echo ""
echo "====================================================="
echo " Installation Complete!"
echo "====================================================="
echo " Directory: $PUMPKIN_DIR"
echo " Global Command: pumpkinmc"
echo ""
echo "=> Starting the server for the first time..."
pumpkinmc run
