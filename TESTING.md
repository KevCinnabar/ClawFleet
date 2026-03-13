# ClawFleet 测试与验证指南

> 基于 [OpenClaw Docker 文档](https://docs.openclaw.ai/install/docker) 和本项目实际配置编写。

## 为什么不用 `docker-setup.sh`？

OpenClaw 官方仓库提供了 `docker-setup.sh` 一键脚本，它会自动完成镜像构建、onboarding、token 生成和 Compose 启动等步骤。**这是官方推荐的最简启动方式。**

但 ClawFleet 是一个**独立的编排项目**，不是从 OpenClaw 仓库根目录运行的，因此无法直接使用 `docker-setup.sh`。本项目的做法是：

| 对比项 | `docker-setup.sh`（官方） | ClawFleet（本项目） |
|--------|--------------------------|-------------------|
| 运行位置 | OpenClaw 仓库根目录 | 独立项目目录 |
| 镜像来源 | 本地 build 或 `OPENCLAW_IMAGE` 拉取 | 直接 `FROM ghcr.io/openclaw/openclaw:latest` |
| Onboarding | 脚本自动运行 `onboard` 向导 | 通过 `--allow-unconfigured` 跳过 |
| Token 管理 | 脚本自动生成并写入 `.env` | 手动在 `.env` 中配置 `OPENCLAW_GATEWAY_TOKEN` |
| 容器数量 | 单个 gateway | 多个智能体（Manager + Developer），各自独立容器 |
| 配置注入 | 脚本自动处理 | 通过 volume 挂载 `data/agents/` 中的 IDENTITY.md、SOUL.md |

> 💡 如果你只想快速体验单个 OpenClaw 实例，建议直接使用官方的 `docker-setup.sh`。
> ClawFleet 的价值在于**多智能体编排**——每个角色一个容器，各自独立的身份和数据。

详见：[OpenClaw Docker 文档解读](./doc/openclaw-docker.md)

---

## 架构概览

```
宿主机 (macOS)
├── docker-compose.yml
├── .env                          ← API Key + Gateway Token
├── agents/
│   ├── manager/Dockerfile        ← FROM ghcr.io/openclaw/openclaw:latest
│   └── developer/Dockerfile
└── data/                         ← volume 挂载（运行时持久化）
    ├── .openclaw/manager/        → 容器内 /home/node/.openclaw
    ├── .openclaw/developer/      → 容器内 /home/node/.openclaw
    ├── agents/manager/           → 容器内 /home/node/.openclaw/agents/manager
    ├── agents/developer/         → 容器内 /home/node/.openclaw/agents/developer
    └── workspace/                → 容器内 /home/node/.openclaw/workspace

端口映射：
  Manager:   宿主机 3001 → 容器 18789
  Developer: 宿主机 3002 → 容器 18789
```

---

## 前置条件

| 条件 | 验证命令 | 期望结果 |
|------|---------|---------|
| Docker CLI | `docker --version` | `>= 27.x`，API `>= 1.44` |
| Docker Compose | `docker compose version` | `>= 2.x` |
| Colima（macOS） | `colima status` | `Running` |
| .env 文件 | `test -f .env && echo OK` | `OK` |

---

## 第 1 步：环境检查

```bash
cd ~/ClawFleet

# Docker 版本（Client API 必须 >= 1.44）
docker version

# Colima 状态（macOS 用户）
colima status

# .env 存在且包含必要配置
grep OPENCLAW_GATEWAY_TOKEN .env
grep OPENAI_API_KEY .env

# data 目录结构
find data -type f | sort
```

---

## 第 2 步：构建镜像

```bash
docker compose build manager
```

**✅ 成功：** 输出末尾显示类似 `Successfully built` 或 `Image built`

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
[gateway] listening on ws://0.0.0.0:18789 (PID ...)
[heartbeat] started
[health-monitor] started
```

**❌ 常见日志错误：**

| 日志中的错误 | 原因 | 解决 |
|-------------|------|------|
| `Refusing to bind gateway to lan without auth` | Token 未注入 | 确认 `.env` 中有 `OPENCLAW_GATEWAY_TOKEN=...` |
| `Missing config` | 缺少 `--allow-unconfigured` | 检查 Dockerfile CMD 是否包含该参数 |
| `non-loopback Control UI requires allowedOrigins` | `--bind lan` 要求 CORS 配置 | 见下方「controlUi 配置」 |
| `EADDRINUSE` | 端口被占用 | `lsof -i :3001` 并 kill 占用进程 |

#### controlUi 配置（`--bind lan` 必须）

`--bind lan` 让 Gateway 绑定 `0.0.0.0`，OpenClaw 要求此时配置 Canvas UI 的 CORS 来源。

修复方式：在**宿主机** `data/.openclaw/<agent>/openclaw.json` 中加入：

```json
{
  "gateway": {
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  }
}
```

> ⚠️ **Volume 覆盖陷阱**：Dockerfile 中 `RUN openclaw config set ...` 写入的配置在 `~/.openclaw/openclaw.json`，
> 但 docker-compose 的 volume 挂载 `./data/.openclaw/manager:/home/node/.openclaw` 会**完全覆盖**容器内该目录。
> 因此必须在**宿主机的 `data/.openclaw/manager/openclaw.json`** 中写入配置，而非仅在 Dockerfile 中设置。

---

## 第 4 步：验证服务

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


### 4.4 容器内 CLI 检查

```bash
docker exec -it claw-manager openclaw health
```

### 4.5 查看 Gateway 日志

```bash
docker exec claw-manager cat /tmp/openclaw/openclaw-$(date +%Y-%m-%d).log
```

---

## 第 5 步：启动 Developer（可选）

```bash
docker compose up developer --build -d
docker compose logs -f developer

# 验证
curl -fsS http://localhost:3002/healthz && echo " ✅ healthy"
```

Canvas UI 地址：`http://localhost:3002/#token=clawfleet-dev-token-2026`

---

## 全部启动与停止

```bash
# 启动所有服务
docker compose up --build -d

# 查看状态
docker compose ps

# 查看所有日志
docker compose logs -f

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
| 容器反复 restart | `docker compose logs manager` | 缺少 token 或缺少 `--allow-unconfigured` |
| `non-loopback Control UI requires...` | 检查 `data/.openclaw/*/openclaw.json` | 缺少 `gateway.controlUi` 配置，见第 3 步说明 |
| `Unauthorized` | 检查 URL 是否用了 `#token=` | 用了 `?token=` 会被服务器拒绝 |
| `device needs pairing approval` | `docker exec claw-manager openclaw devices list` | 新设备首次连接需审批，见第 4.3 步 |
| 无法访问 3001 | `docker compose ps` | 容器未启动或端口未映射 |
| 镜像拉取失败 | `docker pull ghcr.io/openclaw/openclaw:latest` | 网络问题 |
| healthcheck 失败 | `docker exec claw-manager curl http://127.0.0.1:18789/healthz` | Gateway 未完全启动 |

---

## OpenClaw Gateway 通信说明

OpenClaw Gateway 使用 **WebSocket (ws://)** 协议进行智能体通信，同时在同一端口上提供 HTTP 端点：

| 端点 | 协议 | 用途 | 是否需要 auth |
|------|------|------|-------------|
| `/healthz` | HTTP GET | 健康检查 | 否 |
| `/readyz` | HTTP GET | 就绪检查 | 否 |
| `/#token=...` | HTTP (Canvas UI) | 浏览器交互界面 | 是（通过 hash） |
| `ws://...` | WebSocket | 智能体通信 | 是（token） |

---

**最后更新**: 2026年3月13日
