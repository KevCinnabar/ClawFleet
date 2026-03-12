#!/bin/sh
set -e

CONFIG_DIR="$OPENCLAW_HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"

# Initialize config if not present (first run with empty volume)
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[entrypoint] First run: initializing OpenClaw config..."
  openclaw doctor --fix 2>/dev/null || true
  openclaw config set gateway.mode local
  openclaw config set gateway.bind lan
  openclaw config set gateway.port 3000
  openclaw config set gateway.auth.mode token
  openclaw config set gateway.controlUi.allowedOrigins '["http://localhost:3000","http://127.0.0.1:3000","http://localhost:3001","http://127.0.0.1:3001"]'
  echo "[entrypoint] Config initialized."
fi

# Start gateway with token from env
exec openclaw gateway run --port 3000 --bind lan --token "$OPENCLAW_GATEWAY_TOKEN"

