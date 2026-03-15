#!/bin/bash
# entrypoint.sh — 三阶段配置初始化 + 启动 Gateway
#
# Phase 0: 确保目录结构存在（volume 挂载空目录场景）
# Phase 1: openclaw config set 写入固定默认值（仅首次，openclaw.json 不存在时）
# Phase 2: 读取环境变量，覆盖/补充配置（每次启动都执行）
#          包括 Model、Gateway Token、Slack、Notion、GitHub 等
#
set -euo pipefail

OPENCLAW_HOME="${HOME}/.openclaw"
CONFIG_FILE="${OPENCLAW_HOME}/openclaw.json"
AGENT_DIR="${OPENCLAW_HOME}/agents/main/agent"

# ============================================================
# 辅助函数
# ============================================================
log() { echo "[entrypoint] $*"; }

# openclaw config set 的安全包装：显示错误但不中断
config_set() {
  if ! openclaw config set "$@" 2>&1; then
    log "⚠️  config set $1 失败（非致命，继续）"
  fi
}

# ============================================================
# Phase 0: 确保目录结构存在
# ============================================================
ensure_dirs() {
  log "[phase-0] 确保目录结构..."

  # volume 挂载可能只创建空目录，确保所有必要子目录存在
  mkdir -p "${OPENCLAW_HOME}"
  mkdir -p "${OPENCLAW_HOME}/agents"
  mkdir -p "${OPENCLAW_HOME}/workspace"
  mkdir -p "${OPENCLAW_HOME}/identity"
  mkdir -p "${OPENCLAW_HOME}/logs"
  mkdir -p "${OPENCLAW_HOME}/devices"
  mkdir -p "${OPENCLAW_HOME}/cron"
  mkdir -p "${OPENCLAW_HOME}/canvas"
  mkdir -p "${AGENT_DIR}"
  mkdir -p "${HOME}/.config/notion"

  log "[phase-0] 目录结构就绪"
}

# ============================================================
# Phase 1: 固定默认值初始化（仅当 openclaw.json 不存在时执行）
# ============================================================
init_defaults() {
  if [[ -f "$CONFIG_FILE" ]]; then
    log "[phase-1] openclaw.json 已存在，跳过默认初始化"
    return
  fi

  log "[phase-1] 首次启动，写入默认配置..."

  # --- Gateway 配置 ---
  # 绑定 lan 时必须：允许 Host header 作为 CORS origin
  config_set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true

  # --- Gateway Token（从环境变量写入配置持久化）---
  if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    config_set gateway.auth.token "${OPENCLAW_GATEWAY_TOKEN}"
    log "[phase-1] gateway.auth.token: 已写入"
  fi

  # --- Agent 默认配置 ---
  config_set agents.defaults.compaction.mode safeguard

  # --- 命令配置 ---
  config_set commands.native auto
  config_set commands.nativeSkills auto
  config_set commands.restart true
  config_set commands.ownerDisplay raw

  # --- 验证 openclaw.json 是否成功创建 ---
  if [[ -f "$CONFIG_FILE" ]]; then
    log "[phase-1] ✅ openclaw.json 创建成功"
  else
    log "[phase-1] ❌ openclaw.json 未能创建！尝试手动创建最小配置..."
    cat > "$CONFIG_FILE" <<'MINCONFIG'
{
  "meta": {},
  "agents": {
    "defaults": {
      "compaction": { "mode": "safeguard" }
    }
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "gateway": {
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  }
}
MINCONFIG
    log "[phase-1] 手动创建最小 openclaw.json 完成"
  fi

  log "[phase-1] 默认配置写入完成"
}

# ============================================================
# Phase 2: 从环境变量覆盖配置（每次启动都执行）
# ============================================================
apply_env() {
  log "[phase-2] 从环境变量应用配置..."

  # --- Gateway Token（每次确保写入，防止 Phase 1 跳过后 token 丢失）---
  if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    config_set gateway.auth.token "${OPENCLAW_GATEWAY_TOKEN}"
  fi

  # --- Model ---
  local model="${OPENAI_MODEL:-gpt-4o-mini}"
  local fallback="${OPENAI_MODEL_FALLBACK:-gpt-4.1-mini}"
  config_set agents.defaults.model.primary "openai/${model}"
  config_set agents.defaults.model.fallbacks "[\"openai/${fallback}\"]"
  log "[phase-2] model: openai/${model}, fallback: openai/${fallback}"

  # --- 并发 ---
  local max_c="${OPENCLAW_MAX_CONCURRENT:-2}"
  config_set agents.defaults.maxConcurrent "$max_c"
  config_set agents.defaults.subagents.maxConcurrent "$max_c"
  log "[phase-2] maxConcurrent: ${max_c}"

  # --- OpenAI Provider Auth ---
  # 确保 auth-profiles.json 存在，让 OpenClaw 能找到 OpenAI API Key
  # 环境变量 OPENAI_API_KEY 可被 Gateway 直接读取，但 Agent 子进程
  # 可能需要 auth-profiles.json 中的显式配置
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    local auth_file="${AGENT_DIR}/auth-profiles.json"
    if [[ ! -f "$auth_file" ]]; then
      log "[phase-2] 创建 auth-profiles.json（OpenAI provider）..."
    else
      log "[phase-2] 更新 auth-profiles.json（OpenAI provider）..."
    fi
    # 始终写入最新的 API Key（.env 可能更新过）
    local base_url="${OPENAI_BASE_URL:-https://api.openai.com/v1}"
    cat > "$auth_file" <<EOF
{
  "providers": {
    "openai": {
      "apiKey": "${OPENAI_API_KEY}",
      "baseUrl": "${base_url}"
    }
  }
}
EOF
    log "[phase-2] OpenAI auth: configured (${base_url})"
  else
    log "[phase-2] ⚠️  OPENAI_API_KEY 未设置！Agent 将无法调用 LLM"
  fi

  # --- Slack ---
  if [[ -n "${SLACK_BOT_TOKEN:-}" && -n "${SLACK_APP_TOKEN:-}" ]]; then
    config_set channels.slack.mode socket
    config_set channels.slack.enabled true
    config_set channels.slack.nativeStreaming true
    config_set channels.slack.streaming partial

    # 频道白名单
    if [[ -n "${SLACK_ALLOWED_CHANNELS:-}" ]]; then
      local ch_json
      ch_json=$(echo "${SLACK_ALLOWED_CHANNELS}" | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')
      config_set channels.slack.allowedChannels "${ch_json}"
      config_set channels.slack.groupPolicy allowlist
      log "[phase-2] Slack: enabled (socket, allowlist: ${SLACK_ALLOWED_CHANNELS})"
    else
      config_set channels.slack.groupPolicy open
      log "[phase-2] Slack: enabled (socket, open to all channels)"
    fi
  else
    config_set channels.slack.enabled false
    log "[phase-2] Slack: disabled（缺少 SLACK_BOT_TOKEN 或 SLACK_APP_TOKEN）"
  fi

  # --- Notion ---
  if [[ -n "${NOTION_API_KEY:-}" ]]; then
    # 写入 openclaw config
    config_set skills.entries.notion.apiKey "${NOTION_API_KEY}"
    config_set skills.entries.notion.enabled true

    # 写入文件（Notion skill 读取 ~/.config/notion/api_key）
    echo "${NOTION_API_KEY}" > "${HOME}/.config/notion/api_key"

    # NOTION_WORKSPACE_ID 和 NOTION_PRD_DATABASE_ID 通过环境变量
    # 自动注入容器，Agent 在运行时可直接读取，无需写入 openclaw config
    log "[phase-2] Notion: configured (workspace=${NOTION_WORKSPACE_ID:-unset}, db=${NOTION_PRD_DATABASE_ID:-unset})"
  else
    log "[phase-2] Notion: skipped（缺少 NOTION_API_KEY）"
  fi

  # --- GitHub ---
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "${GITHUB_TOKEN}" | gh auth login --with-token 2>/dev/null || {
      log "[phase-2] ⚠️  gh auth login 失败（非致命）"
    }
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
      gh repo set-default "${GITHUB_REPOSITORY}" 2>/dev/null || true
      log "[phase-2] GitHub: authenticated, default repo=${GITHUB_REPOSITORY}"
    else
      log "[phase-2] GitHub: authenticated（无默认 repo）"
    fi
  else
    log "[phase-2] GitHub: skipped（缺少 GITHUB_TOKEN）"
  fi

  log "[phase-2] 环境变量应用完成"
}

# ============================================================
# 诊断输出
# ============================================================
diagnostics() {
  log "--- 初始化诊断 ---"
  if [[ -f "$CONFIG_FILE" ]]; then
    log "✅ openclaw.json 存在 ($(wc -c < "$CONFIG_FILE" | tr -d ' ') bytes)"
  else
    log "❌ openclaw.json 不存在!"
  fi

  if [[ -f "${AGENT_DIR}/auth-profiles.json" ]]; then
    log "✅ auth-profiles.json 存在"
  else
    log "⚠️  auth-profiles.json 不存在（OpenAI 将仅依赖环境变量）"
  fi

  if [[ -f "${HOME}/.config/notion/api_key" ]]; then
    # 验证 Notion API key 是否有效
    local notion_key
    notion_key=$(cat "${HOME}/.config/notion/api_key")
    local notion_resp
    notion_resp=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer ${notion_key}" \
      -H "Notion-Version: 2022-06-28" \
      https://api.notion.com/v1/users/me 2>/dev/null || echo "000")
    if [[ "$notion_resp" == "200" ]]; then
      log "✅ Notion API key 有效 (HTTP 200)"
    elif [[ "$notion_resp" == "000" ]]; then
      log "⚠️  Notion API 无法连接（网络问题）"
    else
      log "❌ Notion API key 无效 (HTTP ${notion_resp})"
    fi
  else
    log "⚠️  Notion API key 文件不存在"
  fi

  if command -v gh &>/dev/null && gh auth status &>/dev/null; then
    log "✅ GitHub CLI 已认证"
  else
    log "⚠️  GitHub CLI 未认证"
  fi

  log "--- 诊断结束 ---"
}

# ============================================================
# 执行三阶段初始化
# ============================================================
ensure_dirs
init_defaults
apply_env
diagnostics

# ============================================================
# 后台自动审批设备配对
# ============================================================
auto_approve() {
  # 关闭 errexit/pipefail，防止后台子 shell 因命令失败而退出
  set +euo pipefail

  # 等待 Gateway 完全启动（healthz 返回 200）
  log "[auto-approve] 等待 Gateway 启动..."
  local waited=0
  while ! curl -fsS http://127.0.0.1:18789/healthz &>/dev/null; do
    sleep 2
    waited=$((waited + 2))
    if [[ $waited -ge 120 ]]; then
      log "[auto-approve] ⚠️  Gateway 120s 未就绪，放弃自动审批"
      return
    fi
  done
  log "[auto-approve] Gateway 已就绪，开始轮询设备审批"

  while true; do
    local devices
    devices=$(openclaw devices list 2>/dev/null || true)
    echo "$devices" \
      | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
      | while read -r rid; do
          openclaw devices approve "$rid" 2>/dev/null && \
            log "[auto-approve] approved device $rid"
        done
    sleep 3
  done
}

auto_approve &

# ============================================================
# 前台启动 Gateway（PID 1，接收信号）
# ============================================================
log "启动 Gateway: port=18789, bind=lan"
exec openclaw gateway run --port 18789 --bind lan --allow-unconfigured "$@"
