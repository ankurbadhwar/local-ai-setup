#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AI_DIR="${AI_DIR:-$HOME/AI}"
LLAMA_SERVER="${LLAMA_SERVER:-$HOME/src/llama.cpp/build/bin/llama-server}"

BACKUP_DIR="$HOME/.local/share/local-ai-setup/backups/$(date +%Y%m%d-%H%M%S)"

log() {
    printf '[local-ai-setup] %s\n' "$*"
}

backup_and_install() {
    local source="$1"
    local destination="$2"

    mkdir -p "$(dirname "$destination")"

    if [[ -e "$destination" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$destination" "$BACKUP_DIR/"
        log "Backed up: $destination"
    fi

    cp "$source" "$destination"
    log "Installed: $destination"
}

# Pre-flight checks
required_files=(
    "$REPO_DIR/llama/config/qwen3-coder-30b-q4.conf"
    "$REPO_DIR/llama/scripts/start-llama-server.sh"
    "$REPO_DIR/llama/scripts/toggle-llama.sh"
    "$REPO_DIR/llama/systemd/llama-server.service"
    "$REPO_DIR/kilo/kilo.jsonc.example"
    "$REPO_DIR/opencode/opencode.jsonc.example"
)

for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: Required file missing: $file" >&2
        exit 1
    fi
done

if [[ ! -x "$LLAMA_SERVER" ]]; then
    echo "WARNING: llama-server was not found at:"
    echo "  $LLAMA_SERVER"
    echo
    echo "The configuration will still be installed."
    echo "Set LLAMA_SERVER if your binary is elsewhere."
    echo
fi

# Create directories
mkdir -p \
    "$AI_DIR/config" \
    "$AI_DIR/scripts" \
    "$HOME/.config/systemd/user" \
    "$HOME/.config/i3/scripts" \
    "$HOME/.config/kilo" \
    "$HOME/.config/opencode"

# llama.cpp
backup_and_install \
    "$REPO_DIR/llama/config/qwen3-coder-30b-q4.conf" \
    "$AI_DIR/config/qwen3-coder-30b-q4.conf"

backup_and_install \
    "$REPO_DIR/llama/scripts/start-llama-server.sh" \
    "$AI_DIR/scripts/start-llama-server.sh"

chmod +x "$AI_DIR/scripts/start-llama-server.sh"

# i3 toggle
backup_and_install \
    "$REPO_DIR/llama/scripts/toggle-llama.sh" \
    "$HOME/.config/i3/scripts/toggle-llama"

chmod +x "$HOME/.config/i3/scripts/toggle-llama"

# systemd service
backup_and_install \
    "$REPO_DIR/llama/systemd/llama-server.service" \
    "$HOME/.config/systemd/user/llama-server.service"

systemctl --user daemon-reload

# Kilo
backup_and_install \
    "$REPO_DIR/kilo/kilo.jsonc.example" \
    "$HOME/.config/kilo/kilo.jsonc"

# OpenCode
backup_and_install \
    "$REPO_DIR/opencode/opencode.jsonc.example" \
    "$HOME/.config/opencode/opencode.jsonc"

echo
log "Installation complete."

if [[ -d "$BACKUP_DIR" ]]; then
    log "Existing files backed up to:"
    echo "  $BACKUP_DIR"
fi

echo
echo "llama-server:"
echo "  systemctl --user start llama-server"
echo "  systemctl --user stop llama-server"
echo "  systemctl --user status llama-server"
echo
echo "i3 toggle:"
echo "  ~/.config/i3/scripts/toggle-llama"
echo
echo "Configuration:"
echo "  $AI_DIR/config/qwen3-coder-30b-q4.conf"
