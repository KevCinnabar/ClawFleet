# ClawFleet 测试与验证指南

> 基于 [OpenClaw Docker 文档](https://docs.openclaw.ai/install/docker) 和本项目实际配置编写。

## 为什么不用 `docker-setup.sh`？

OpenClaw 官方仓库提供了 `docker-setup.sh` 一键脚本，它会自动完成镜像构建、onboarding、token 生成和 Compose 启动等步骤。**这是官方推荐的最简启动方式。**

但 ClawFleet 是一个**独立的编排项目**，不是从 OpenClaw 仓库根目录运行的，因此无法直接使用 `docker-setup.sh`。本项目通过自定义 `entrypoint.sh` 实现了等价的初始化逻辑：

| 对比项 | `docker-setup.sh`（官方） | ClawFleet（本项目） |
|--------|--------------------------|-------------------|
| 运行位置 | OpenClaw 仓库根目录 | 独立项目目录 |
| 镜像来源 | 本地 build 或 `OPENCLAW_IMAGE` 拉取 | 直接 `FROM ghcr.io/openclaw/openclaw:latest` |
| Onboarding | 脚本自动运行 `onboard` 向导 | 通过 `--allow-unconfigured` 跳过 |
| Token 管理 | 脚本自动生成并写入 `.env` | 手动在 agent `.env` 中配置 `OPENCLAW_GATEWAY_TOKEN` |
| 容器数量 | 单个 gateway | 多个智能体（Manager + Developer），各自独立容器 |
| 配置注入 | 脚本自动处理 | 通过 volume 挂载 `data/agents/` 中的 IDENTITY.md、SOUL.md |
| 集成初始化 | 脚本自动配置 | `entrypoint.sh` Phase 2 自动配置 Notion/GitHub/Slack |

> 💡 如果你只想快速体验单个 OpenClaw 实例，建议直接使用官方的 `docker-setup.sh`。
> ClawFleet 的价值在于**多智能体编排**——每个角色一个容器，各自独立的身份和数据。

详见：[OpenClaw Docker 文档解读](./doc/openclaw-docker.md)

---

## 架构概览

```
宿主机 (macOS)
├── docker-compose.yml
├── agents/
│   ├── manager/
│   │   ├── Dockerfile            ← FROM ghcr.io/openclaw/openclaw:latest + gh CLI
│   │   ├── entrypoint.sh         ← 两阶段初始化（Phase 1 + Phase 2）
│   │   └── .env                  ← Manager 完整环境变量
│   └── developer/
│       ├── Dockerfile
│       ├── entrypoint.sh
│       └── .env                  ← Developer 完整环境变量
└── data/                         ← volume 挂载（运行时持久化）
    ├── .openclaw/manager/        → 容器内 /home/node/.openclaw
    ├── .openclaw/developer/      → 容器内 /home/node/.openclaw
    ├── agents/manager/           → 容器内 /home/node/.openclaw/agents/manager
    ├── agents/developer/         → 容器内 /home/node/.openclaw/agents/developer
    └── workspace/                → 容器内 /home/node/.openclaw/workspace（共享）

端口映射：
  Manager:   宿主机 3001 → 容器 18789
  Developer: 宿主机 3002 → 容器 18789
```

---

## 环境变量配置

每个 Agent 拥有独立的 `.env` 文件（**不再使用根目录共享 .env**）：

```
agents/manager/.env      ← Manager 完整配置
agents/developer/.env    ← Developer 完整配置
```

> ⚠️ 两个 `.env` 可以共享相同的 API Key，但 **Slack Token 必须不同**——每个 Agent 需要独立的 Slack App。

每个 `.env` 包含全部所需变量：

| 变量 | 用途 | 必需 |
|------|------|------|
| `OPENAI_API_KEY` | OpenAI API 密钥 | ✅ |
| `OPENAI_BASE_URL` | OpenAI API 端点 | ✅ |
| `OPENAI_MODEL` | 主模型（如 `gpt-4o-mini`） | ✅ |
| `OPENAI_MODEL_FALLBACK` | 备用模型（如 `gpt-4.1-mini`） | ✅ |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway 认证 Token | ✅ |
| `OPENCLAW_MAX_CONCURRENT` | 最大并发数 | 否（默认 2） |
| `NOTION_API_KEY` | Notion 集成 | 否 |
| `NOTION_WORKSPACE_ID` | Notion 工作区 ID | 否 |
| `NOTION_PRD_DATABASE_ID` | Notion 数据库 ID | 否 |
| `GITHUB_TOKEN` | GitHub PAT | 否 |
| `GITHUB_REPOSITORY` | 默认仓库 owner/repo | 否 |
| `SLACK_BOT_TOKEN` | Slack Bot Token | 否 |
| `SLACK_APP_TOKEN` | Slack App Token | 否 |
| `SLACK_SIGNING_SECRET` | Slack Signing Secret | 否 |

### Manager vs Developer 配置差异

| 配置项 | Manager | Developer | 说明 |
|--------|---------|-----------|------|
| `OPENAI_MODEL` | `gpt-4o-mini` | `gpt-4.1-mini` | Manager 侧重沟通，Developer 侧重代码 |
| `SLACK_*` | Manager App Token | Developer App Token | **每个 Agent 必须使用独立的 Slack App** |
| `NOTION_API_KEY` | 共享同一个 | 共享同一个 | 可以相同 |
| `GITHUB_TOKEN` | 共享同一个 | 共享同一个 | 可以相同 |

---

## 初始化机制（entrypoint.sh）

每个容器启动时，`entrypoint.sh` 自动执行**三阶段初始化**：

### Phase 0：目录结构保障

无论首次还是重启，都会确保以下目录存在（volume 挂载空目录时需要）：

```
~/.openclaw/
├── agents/main/agent/    ← auth-profiles.json 所在目录
├── workspace/
├── identity/
├── logs/
├── devices/
├── cron/
└── canvas/
```

### Phase 1：首次初始化（仅当 `openclaw.json` 不存在）

当 `data/.openclaw/<agent>/` 为空目录（首次启动或清除数据后）时执行：

1. 写入 `gateway.controlUi` CORS 配置
2. 写入 `gateway.auth.token`（从 `OPENCLAW_GATEWAY_TOKEN` 环境变量持久化到 JSON）
3. 写入 Agent 默认配置（compaction、commands 等）

> ⚠️ **如果 `openclaw config set` 失败**（极端情况），脚本会手动写入一份最小 `openclaw.json`，确保 Gateway 能启动。

> ⚠️ **Volume 覆盖机制**：docker-compose 的 volume 挂载会**完全覆盖**容器内 `~/.openclaw` 目录。
> 因此 Dockerfile 中 `RUN openclaw config set ...` 写入的配置会被覆盖。
> 实际配置由 `entrypoint.sh` 在容器启动时通过 `openclaw config set` 写入到挂载目录。

### Phase 2：环境变量注入（每次启动）

从 `.env` 读取环境变量，通过 `openclaw config set` 和文件写入配置：

| 配置项 | 环境变量来源 | 写入位置 |
|--------|------------|---------|
| Gateway Token | `OPENCLAW_GATEWAY_TOKEN` | `gateway.auth.token`（每次刷新） |
| Model | `OPENAI_MODEL` / `OPENAI_MODEL_FALLBACK` | `agents.defaults.model.*` |
| 并发 | `OPENCLAW_MAX_CONCURRENT` | `agents.defaults.maxConcurrent` |
| **OpenAI Auth** | `OPENAI_API_KEY` + `OPENAI_BASE_URL` | `~/.openclaw/agents/main/agent/auth-profiles.json` |
| Slack | `SLACK_BOT_TOKEN` + `SLACK_APP_TOKEN` | `channels.slack.*` |
| Notion | `NOTION_API_KEY` | `skills.entries.notion.apiKey` + `~/.config/notion/api_key` |
| GitHub | `GITHUB_TOKEN` | `gh auth login --with-token` + `gh repo set-default` |

> 💡 **auth-profiles.json**：OpenClaw Agent 子进程通过此文件查找 API Key。
> 之前遇到的 `No API key found for provider` 错误就是因为缺少此文件。
> 现在 Phase 2 会自动创建并在每次启动时更新。

### 诊断输出

初始化完成后，脚本会输出关键文件状态：

```
[entrypoint] --- 初始化诊断 ---
[entrypoint] ✅ openclaw.json 存在 (890 bytes)
[entrypoint] ✅ auth-profiles.json 存在
[entrypoint] ✅ Notion API key 文件存在
[entrypoint] ✅ GitHub CLI 已认证
[entrypoint] --- 诊断结束 ---
```

如果看到 ❌ 或 ⚠️，请检查对应的 `.env` 配置。

**完整启动日志示例（首次）：**
```
[entrypoint] [phase-0] 确保目录结构...
[entrypoint] [phase-0] 目录结构就绪
[entrypoint] [phase-1] 首次启动，写入默认配置...
[entrypoint] [phase-1] gateway.auth.token: 已写入
[entrypoint] [phase-1] ✅ openclaw.json 创建成功
[entrypoint] [phase-1] 默认配置写入完成
[entrypoint] [phase-2] 从环境变量应用配置...
[entrypoint] [phase-2] model: openai/gpt-4o-mini, fallback: openai/gpt-4.1-mini
[entrypoint] [phase-2] maxConcurrent: 2
[entrypoint] [phase-2] 创建 auth-profiles.json（OpenAI provider）...
[entrypoint] [phase-2] OpenAI auth: configured (https://api.openai.com/v1)
[entrypoint] [phase-2] Slack: enabled (socket mode)
[entrypoint] [phase-2] Notion: configured (config + file)
[entrypoint] [phase-2] GitHub: authenticated, default repo=KevCinnabar/ClawFleet
[entrypoint] [phase-2] 环境变量应用完成
[entrypoint] --- 初始化诊断 ---
[entrypoint] ✅ openclaw.json 存在 (890 bytes)
[entrypoint] ✅ auth-profiles.json 存在
[entrypoint] ✅ Notion API key 文件存在
[entrypoint] ✅ GitHub CLI 已认证
[entrypoint] --- 诊断结束 ---
[entrypoint] 启动 Gateway: port=18789, bind=lan
```

### 完全重新初始化

如需从零开始（模拟 `docker-setup.sh` 的效果）：

```bash
# 停止容器
docker compose down

# 删除持久化数据（谨慎！会丢失聊天记录和设备配对）
rm -rf data/.openclaw/manager/*
rm -rf data/.openclaw/developer/*

# 重新构建并启动（Phase 1 会执行完整初始化）
docker compose up --build -d
docker compose logs -f
```

---

## 前置条件

| 条件 | 验证命令 | 期望结果 |
|------|---------|---------|
| Docker CLI | `docker --version` | `>= 27.x`，API `>= 1.44` |
| Docker Compose | `docker compose version` | `>= 2.x` |
| Colima（macOS） | `colima status` | `Running` |
| Agent .env 文件 | `test -f agents/manager/.env && echo OK` | `OK` |

---

## 第 1 步：环境检查

```bash
cd ~/ClawFleet

# Docker 版本（Client API 必须 >= 1.44）
docker version

# Colima 状态（macOS 用户）
colima status

# 检查本地是否有其他 openclaw 进程
ps aux | grep openclaw | grep -v grep

# 如果有本地 openclaw 服务在运行，停止它（避免端口冲突）
# launchctl list | grep openclaw          # 检查 macOS launchd 服务
# launchctl unload <plist-path>           # 停止 launchd 服务

# 每个 agent 的 .env 存在且包含必要配置
grep OPENCLAW_GATEWAY_TOKEN agents/manager/.env
grep OPENAI_API_KEY agents/manager/.env
grep OPENCLAW_GATEWAY_TOKEN agents/developer/.env
grep OPENAI_API_KEY agents/developer/.env

# data 目录结构
find data -maxdepth 3 -type f | sort
```

---

## 第 2 步：构建镜像

```bash
# 单独构建 Manager
docker compose build manager

# 单独构建 Developer
docker compose build developer

# 或同时构建
docker compose build
```

**✅ 成功：** 输出末尾显示类似 `Successfully built` 或 `Image built`

> 💡 镜像中已预装 `gh` CLI（GitHub）和常用工具（curl, wget, git, jq, vim）。

**❌ 常见错误：**

| 错误 | 原因 | 解决 |
|------|------|------|
| `client version too old` | Docker CLI 版本太低 | `brew reinstall docker` |
| `requires buildx 0.17.0` | buildx 插件太旧 | `brew install docker-buildx` |
| `pull access denied` | 无法拉取基础镜像 | 检查网络 / `docker login ghcr.io` |

---

## 第 3 步：启动 Manager

```bash
docker compose up manager -d
docker compose ps
docker compose logs -f manager
```

**✅ 成功标志（日志中出现）：**
```
[phase-2] Notion: configured
[phase-2] GitHub: authenticated, default repo=KevCinnabar/ClawFleet
[gateway] listening on ws://0.0.0.0:18789 (PID ...)
[heartbeat] started
[health-monitor] started
```

**❌ 常见日志错误：**

| 日志中的错误 | 原因 | 解决 |
|-------------|------|------|
| `Refusing to bind gateway to lan without auth` | Token 未注入 | 确认 `agents/manager/.env` 中有 `OPENCLAW_GATEWAY_TOKEN=...` |
| `Missing config` | 缺少 `--allow-unconfigured` | 检查 entrypoint.sh 最后一行 |
| `non-loopback Control UI requires allowedOrigins` | `--bind lan` 要求 CORS 配置 | 见下方「controlUi 配置」 |
| `EADDRINUSE` | 端口被占用 | `lsof -i :3001` 并 kill 占用进程 |
| `API rate limit reached` | OpenAI API 速率限制 | 等待或升级 API plan |
| `organization must be verified` | OpenAI 组织未验证 | 前往 platform.openai.com 验证组织 |

#### controlUi 配置（`--bind lan` 必须）

`--bind lan` 让 Gateway 绑定 `0.0.0.0`，OpenClaw 要求此时配置 Canvas UI 的 CORS 来源。

这由 `entrypoint.sh` Phase 1 自动配置。如果 `data/.openclaw/<agent>/openclaw.json` 已存在但缺少此配置，可手动添加：

```json
{
  "gateway": {
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  }
}
```

> ⚠️ **Volume 覆盖陷阱**：docker-compose 的 volume 挂载 `./data/.openclaw/manager:/home/node/.openclaw` 会**完全覆盖**容器内该目录。
> 因此必须在**宿主机的 `data/.openclaw/manager/openclaw.json`** 中写入配置，而非仅在 Dockerfile 中设置。
> 本项目通过 `entrypoint.sh` 在容器启动时动态写入来解决此问题。

---

## 第 4 步：验证 Manager

### 4.1 健康检查

```bash
curl -fsS http://localhost:3001/healthz && echo " ✅ healthy"
curl -fsS http://localhost:3001/readyz  && echo " ✅ ready"
```

### 4.2 浏览器访问 Canvas UI

在浏览器打开：

```
http://localhost:3001/#token=clawfleet-dev-token-2026
```

> **注意**：token 通过 `#token=`（hash fragment）传递，不是 `?token=`。
> hash fragment 不会发送到服务器日志，更安全。

### 4.3 设备配对（自动审批）

OpenClaw 有**两层认证**：① Token 验证 ② 设备配对审批。

本项目通过 `entrypoint.sh` 实现**自动审批**——后台每 3 秒扫描 pending 设备并自动批准。
首次打开 Canvas UI 时可能需要等待几秒后刷新页面。

如需手动审批（调试用）：

```bash
docker exec claw-manager openclaw devices list
docker exec claw-manager openclaw devices approve <requestId>
```

### 4.4 验证集成状态

```bash
# 查看所有 skills 状态
docker exec claw-manager openclaw skills list

# 验证 OpenAI auth-profiles.json 存在
docker exec claw-manager test -f /home/node/.openclaw/agents/main/agent/auth-profiles.json && echo "✅ OpenAI auth configured"

# 验证 GitHub CLI 认证
docker exec claw-manager gh auth status

# 验证 Notion API Key（检查文件是否存在）
docker exec claw-manager test -f /home/node/.config/notion/api_key && echo "✅ Notion configured"

# 查看 openclaw.json 中的配置
docker exec claw-manager cat /home/node/.openclaw/openclaw.json | python3 -m json.tool

# 查看 Slack 连接状态
docker exec claw-manager openclaw skills list | grep slack
```

**✅ 期望结果：**

| 集成 | 验证方式 | 期望状态 |
|------|---------|---------|
| Notion | `openclaw skills list \| grep notion` | `✓ ready` |
| GitHub | `openclaw skills list \| grep github` | `✓ ready` |
| Slack | `openclaw skills list \| grep slack` | `✓ ready`（需配置 Token） |

### 4.5 容器内 CLI 检查

```bash
docker exec -it claw-manager openclaw health
```

### 4.6 查看 Gateway 日志

```bash
docker exec claw-manager cat /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log
```

---

## 第 5 步：启动 Developer

```bash
docker compose up developer --build -d
docker compose logs -f developer
```

**✅ 成功标志：**
```
[phase-2] Notion: configured
[phase-2] GitHub: authenticated, default repo=KevCinnabar/ClawFleet
[gateway] listening on ws://0.0.0.0:18789 (PID ...)
```

### 验证 Developer

```bash
# 健康检查
curl -fsS http://localhost:3002/healthz && echo " ✅ healthy"

# Canvas UI
open "http://localhost:3002/#token=clawfleet-dev-token-2026"

# 验证集成
docker exec claw-developer openclaw skills list
docker exec claw-developer gh auth status
docker exec claw-developer test -f /home/node/.config/notion/api_key && echo "✅ Notion configured"
```

---

## 第 6 步：验证 Slack 连接

如果两个 Agent 都配置了 Slack，验证 Bot 是否在线：

```bash
# 检查 Manager Slack 连接
docker compose logs manager | grep -i slack

# 检查 Developer Slack 连接
docker compose logs developer | grep -i slack
```

**✅ 成功标志：** 日志中出现 `Slack: enabled (socket mode)` 且无错误

**❌ Slack 无反应的排查步骤：**

1. 确认 Bot Token 和 App Token 正确
2. 确认 Slack App 已安装到工作区
3. 确认 Bot 已被邀请到目标 Channel（`/invite @BotName`）
4. 确认 App 启用了 Socket Mode
5. 查看日志中是否有 `Agent failed before reply` 错误

---

## 全部启动与停止

```bash
# 启动所有服务
docker compose up --build -d

# 查看状态
docker compose ps

# 查看所有日志
docker compose logs -f

# 单独重启某个 Agent（修改 .env 后）
docker compose restart manager
docker compose restart developer

# 重新构建并启动（修改 Dockerfile 或 entrypoint.sh 后）
docker compose up manager --build -d

# 停止所有服务
docker compose down

# 停止并删除 volume（清除数据）
docker compose down -v
```

---

## 排错速查表

| 现象 | 排查命令 | 常见原因 |
|------|---------|---------|
| `docker.sock: no such file` | `colima status` | Colima 未运行，执行 `colima start` |
| 容器反复 restart | `docker compose logs <agent>` | 缺少 token 或缺少 `--allow-unconfigured` |
| `non-loopback Control UI requires...` | 检查 `data/.openclaw/*/openclaw.json` | 缺少 `gateway.controlUi` 配置，见第 3 步说明 |
| `Unauthorized` | 检查 URL 是否用了 `#token=` | 用了 `?token=` 会被服务器拒绝 |
| `device needs pairing approval` | `docker exec <container> openclaw devices list` | 新设备首次连接需审批，见第 4.3 步 |
| 无法访问端口 | `docker compose ps` | 容器未启动或端口未映射 |
| 镜像拉取失败 | `docker pull ghcr.io/openclaw/openclaw:latest` | 网络问题 |
| healthcheck 失败 | `docker exec <container> curl http://127.0.0.1:18789/healthz` | Gateway 未完全启动 |
| GitHub skill `✗ missing` | `docker exec <container> which gh` | `gh` CLI 未安装，需重新 build 镜像 |
| Notion 无法连接 | `docker exec <container> env \| grep NOTION` | `.env` 中缺少 `NOTION_API_KEY` |
| GitHub 无法认证 | `docker exec <container> gh auth status` | `.env` 中缺少 `GITHUB_TOKEN` |
| Phase 1 未执行 | `docker compose logs \| grep phase-1` | `openclaw.json` 已存在，需删除 `data/.openclaw/<agent>/*` |
| `API rate limit reached` | 查看 OpenAI Dashboard 用量 | 升级 API plan 或等待限流重置 |
| Slack Bot 无反应 | `docker compose logs <agent> \| grep -i slack` | Bot 未被邀请到 Channel，或 Token 错误 |
| `No API key found for provider` | `docker exec <container> cat ~/.openclaw/agents/main/agent/auth-profiles.json` | auth-profiles.json 缺失或 API Key 错误，检查 `.env` 中的 `OPENAI_API_KEY` 后重启 |

---

## OpenClaw Gateway 通信说明

OpenClaw Gateway 使用 **WebSocket (ws://)** 协议进行智能体通信，同时在同一端口上提供 HTTP 端点：

| 端点 | 协议 | 用途 | 是否需要 auth |
|------|------|------|-------------|
| `/healthz` | HTTP GET | 健康检查 | 否 |
| `/readyz` | HTTP GET | 就绪检查 | 否 |
| `/#token=...` | HTTP (Canvas UI) | 浏览器交互界面 | 是（通过 hash） |
| `ws://...` | WebSocket | 智能体通信 | 是（token） |

> 💡 **调试建议**：由于 Gateway 使用 WebSocket，`curl` 只能测试 HTTP 端点（`/healthz`、`/readyz`）。
> 对于 Canvas UI 和智能体通信，使用浏览器或 WebSocket 客户端（如 `websocat`）。

---

## 数据文件说明

### 共享文件（所有 Agent 可见）

| 文件 | 位置 | 用途 |
|------|------|------|
| `IDENTITY.md` | `data/workspace/` | 工作空间全局身份 |
| `SOUL.md` | `data/workspace/` | 共享行为准则 |
| `USER.md` | `data/workspace/` | 用户信息 |
| `TOOLS.md` | `data/workspace/` | 工具备忘录 |
| `HEARTBEAT.md` | `data/workspace/` | 心跳任务配置 |
| `AGENTS.md` | `data/workspace/` | OpenClaw 智能体行为指南 |
| `BOOTSTRAP.md` | `data/workspace/` | 首次启动引导 |

### Agent 专属文件（每个 Agent 独立）

| 文件 | 位置 | 用途 |
|------|------|------|
| `IDENTITY.md` | `data/agents/<agent>/` | 智能体身份定义 |
| `SOUL.md` | `data/agents/<agent>/` | 智能体行为准则 |
| `agent.yaml` | `data/agents/<agent>/` | 运行时配置（模型、集成开关等） |
| `.env` | `agents/<agent>/` | 环境变量（密钥、Token 等） |

> ⚠️ 工作空间级 `SOUL.md` 定义全局准则，Agent 级 `SOUL.md` 定义角色特有准则。两者不冲突，互为补充。

---

**最后更新**: 2026年3月15日
