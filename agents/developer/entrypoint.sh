#!/bin/bash
# entrypoint.sh — 两阶段配置初始化 + 启动 Gateway
#
# Phase 1: openclaw config set 写入固定默认值（仅首次，openclaw.json 不存在时）
# Phase 2: 读取 .env 环境变量，覆盖/补充配置（每次启动都执行）
#
set -euo pipefail

CONFIG_FILE="${HOME}/.openclaw/openclaw.json"

# ============================================================
# Phase 1: 固定默认值初始化（仅当 openclaw.json 不存在时执行）
# ============================================================
init_defaults() {
  if [[ -f "$CONFIG_FILE" ]]; then
    echo "[phase-1] openclaw.json 已存在，跳过默认初始化"
    return
  fi

  echo "[phase-1] 首次启动，写入默认配置..."

  # Gateway: 允许非 loopback Control UI
  openclaw config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true 2>/dev/null

  # Agent 默认并发
  openclaw config set agents.defaults.compaction.mode safeguard 2>/dev/null
  openclaw config set agents.defaults.maxConcurrent 4 2>/dev/null
  openclaw config set agents.defaults.subagents.maxConcurrent 8 2>/dev/null

  # Commands
  openclaw config set commands.native auto 2>/dev/null
  openclaw config set commands.nativeSkills auto 2>/dev/null
  openclaw config set commands.restart true 2>/dev/null
  openclaw config set commands.ownerDisplay raw 2>/dev/null

  echo "[phase-1] 默认配置写入完成"
}

# ============================================================
# Phase 2: 从环境变量覆盖配置（每次启动都执行）
# ============================================================
apply_env() {
  echo "[phase-2] 从环境变量应用配置..."

  # --- Model: 读取 OPENAI_MODEL / OPENAI_MODEL_FALLBACK ---
  local model="${OPENAI_MODEL:-gpt-4o}"
  local fallback="${OPENAI_MODEL_FALLBACK:-gpt-4.1-mini}"
  openclaw config set agents.defaults.model.primary "openai/${model}" 2>/dev/null
  openclaw config set agents.defaults.model.fallbacks "[\"openai/${fallback}\"]" 2>/dev/null
  echo "[phase-2] model: openai/${model}, fallback: openai/${fallback}"

  # --- Slack: 仅当 BOT_TOKEN + APP_TOKEN 都存在时启用 ---
  if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_APP_TOKEN:-}" ]]; then
    openclaw config set channels.slack.mode socket 2>/dev/null
    openclaw config set channels.slack.enabled true 2>/dev/null
    openclaw config set channels.slack.groupPolicy open 2>/dev/null
    openclaw config set channels.slack.nativeStreaming true 2>/dev/null
    openclaw config set channels.slack.streaming partial 2>/dev/null
    echo "[phase-2] Slack: enabled (socket mode)"
  else
    openclaw config set channels.slack.enabled false 2>/dev/null
    echo "[phase-2] Slack: disabled（缺少 SLACK_BOT_TOKEN 或 SLACK_APP_TOKEN）"
  fi

  echo "[phase-2] 环境变量应用完成"
}

# ============================================================
# 执行两阶段初始化
# ============================================================
init_defaults
apply_env

# ============================================================
# 后台自动审批设备配对
# ============================================================
auto_approve() {
  sleep 5
  while true; do
    openclaw devices list 2>/dev/null \
      | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
      | while read -r rid; do
          openclaw devices approve "$rid" 2>/dev/null && \
            echo "[auto-approve] approved device $rid"
        done
    sleep 3
  done
}

auto_approve &

# ============================================================
# 前台启动 Gateway（PID 1，接收信号）
# ============================================================
exec openclaw gateway run --port 18789 --bind lan --allow-unconfigured "$@"
