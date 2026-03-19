#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# The direct URL you provided
DOWNLOAD_URL="https://github.com/Pumpkin-MC/Pumpkin/releases/download/nightly/pumpkin-X64-Linux"
PUMPKIN_DIR="$HOME/pumpkinmc_server"
BIN_DIR="/usr/local/bin"

echo "====================================================="
echo " PumpkinMC Installer for Arch Linux (Direct Version)"
echo "====================================================="

echo "=> Installing required dependencies (tmux, wget)..."
sudo pacman -Syu --needed tmux wget --noconfirm

echo "=> Setting up server directory at $PUMPKIN_DIR..."
mkdir -p "$PUMPKIN_DIR"
cd "$PUMPKIN_DIR"

echo "=> Downloading the PumpkinMC binary..."
# Download directly and name it 'pumpkin-server'
wget -q --show-progress -O pumpkin-server "$DOWNLOAD_URL"

echo "=> Making the binary executable..."
chmod +x pumpkin-server

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

# Inject the actual directory path into the wrapper script
sed -i "s|PUMPKIN_DIR_PLACEHOLDER|$PUMPKIN_DIR|g" "$WRAPPER_SCRIPT"

echo "=> Moving wrapper to $BIN_DIR/pumpkinmc (requires sudo)..."
sudo mv "$WRAPPER_SCRIPT" "$BIN_DIR/pumpkinmc"

echo ""
echo "====================================================="
echo " Installation Complete!"
echo "====================================================="
echo " Directory: $PUMPKIN_DIR"
echo " Command:   pumpkinmc"
echo "====================================================="
echo "=> Starting the server for the first time..."
pumpkinmc run
