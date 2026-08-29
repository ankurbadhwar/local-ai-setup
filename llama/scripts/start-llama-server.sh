#!/bin/bash
set -euo pipefail

AI_DIR="${AI_DIR:-$HOME/AI}"
CONFIG="$AI_DIR/config/qwen3-coder-30b-q4.conf"
LLAMA_SERVER="${LLAMA_SERVER:-$HOME/src/llama.cpp/build/bin/llama-server}"

if [[ ! -f "$CONFIG" ]]; then
    echo "Configuration not found: $CONFIG" >&2
    exit 1
fi

if [[ ! -x "$LLAMA_SERVER" ]]; then
    echo "llama-server not found: $LLAMA_SERVER" >&2
    echo "Set LLAMA_SERVER=/path/to/llama-server or install llama.cpp." >&2
    exit 1
fi

source "$CONFIG"

exec "$LLAMA_SERVER" \
    -hf "$MODEL" \
    -c "$CONTEXT" \
    -np "$PARALLEL" \
    -ngl "$GPU_LAYERS" \
    -fa "$FLASH_ATTN" \
    -ctk "$KV_TYPE_K" \
    -ctv "$KV_TYPE_V" \
    -nkvo \
    --fit "$FIT" \
    --host "$HOST" \
    --port "$PORT" \
    --no-webui
