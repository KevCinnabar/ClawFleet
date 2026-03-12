# ClawFleet 测试与验证指南

## 前置条件

| 条件 | 验证命令 | 期望结果 |
|------|---------|---------|
| Docker CLI | `docker --version` | `>= 29.x`，API `>= 1.44` |
| Docker Compose | `docker compose version` | `>= 2.x` |
| Colima（macOS） | `colima status` | `Running` |
| .env 文件 | `test -f .env && echo OK` | `OK` |

---

## ⚠️ 关键说明

### OpenClaw Gateway 是 WebSocket 服务

Gateway 监听的是 **WebSocket 协议**（`ws://`），不是 HTTP REST API。
`curl http://localhost:3001` 不会返回正常结果，这是**预期行为**。

### OpenClaw 配置路径

OpenClaw 的实际配置路径是 `$OPENCLAW_HOME/.openclaw/openclaw.json`。

由于 Dockerfile 设置了 `ENV OPENCLAW_HOME=/data/.openclaw`，容器内的配置文件路径为：
```
/data/.openclaw/.openclaw/openclaw.json
```

当前 Dockerfile 在构建时已通过 `openclaw doctor --fix` 和 `openclaw config set` 将配置烘焙进镜像，**无需手动初始化**。

运行时修改会通过 volume 持久化到宿主机的 `data/.openclaw/` 目录。

---

## 第 1 步：环境检查

```bash
cd ~/ClawFleet

# Docker 版本（Client API 必须 >= 1.44）
docker version

# Colima 状态（macOS 用户）
colima status

# .env 存在且非空
wc -l .env

# data 目录结构
find data -type f | sort
```

**预期 data 目录结构：**
```
data/agents/developer/IDENTITY.md
data/agents/developer/SOUL.md
data/agents/developer/agent.yaml
data/agents/manager/IDENTITY.md
data/agents/manager/SOUL.md
data/agents/manager/agent.yaml
data/workspace/.gitkeep
```

> 注意：`data/.openclaw/` 下的运行时配置由镜像自动生成，首次启动前可以为空。

---

## 第 2 步：构建镜像

```bash
docker compose build manager
docker compose build developer
```

**✅ 成功：** 输出末尾显示 `Successfully built`

**❌ 失败排查：**

| 错误 | 原因 | 解决 |
|------|------|------|
| `client version too old` | Docker CLI 版本太低 | `brew reinstall docker` |
| `requires buildx 0.17.0` | buildx 插件太旧 | `brew install docker-buildx` |
| `pull access denied` | 无法拉取基础镜像 | 检查网络 / `docker login` |

---

## 第 3 步：启动 Manager（单独测试）

```bash
docker compose up manager -d
docker compose ps
docker compose logs -f manager
```

**✅ 成功标志（日志中出现）：**
```
[gateway] listening on ws://0.0.0.0:3000 (PID ...)
[heartbeat] started
[health-monitor] started
```

**❌ 常见日志错误：**

| 日志中的错误 | 原因 | 解决 |
|-------------|------|------|
| `Missing config. Run openclaw setup` | 镜像构建时初始化失败 | 重新 `docker compose build manager` |
| `unknown option '--host'` | CMD 参数错误 | Dockerfile CMD 应为 `gateway run --port 3000 --bind lan` |
| `unknown option '--config'` | CMD 参数错误 | 同上，OpenClaw gateway 不支持 --config |
| `EADDRINUSE` | 端口被占用 | `lsof -i :3001` 并 kill 占用进程 |
| `non-loopback Control UI requires...` | 首次启动自动修复 | OpenClaw 会自动写入 `allowedOrigins`，等待重启 |

---

## 第 4 步：验证 Manager 服务

Gateway 使用固定 token 认证（在 `.env` 中配置 `OPENCLAW_GATEWAY_TOKEN=clawfleet-dev-token-2026`）。

### 4.1 浏览器访问 Canvas UI
```
http://localhost:3001/#token=clawfleet-dev-token-2026
```

### 4.2 容器内 CLI 检查（不需要 token）
```bash
docker exec -it claw-manager openclaw health
docker exec -it claw-manager openclaw gateway status
```

### 4.3 WebSocket 连接测试
```bash
brew install websocat
websocat "ws://localhost:3001?token=clawfleet-dev-token-2026"
```

**✅ 成功标志：**
- 浏览器能打开 Canvas 对话界面
- `openclaw health` 返回健康状态
- WebSocket 能建立连接

**❌ 常见错误：**

| 错误 | 原因 | 解决 |
|------|------|------|
| `{"error":"Unauthorized"}` | token 不对或 URL 格式错 | 用 `#token=` 不是 `?token=` |
| `Refusing to bind gateway to lan without auth` | 环境变量未注入 | `docker compose config` 检查 |
| `Connection refused` | Gateway 未运行 | `docker compose up manager -d` |

---

## 第 5 步：启动 Developer（单独测试）

```bash
docker compose up developer -d
docker compose ps
docker compose logs -f developer

# 验证
docker exec -it claw-developer openclaw health
```

浏览器访问 Developer Canvas：
```
http://localhost:3002/#token=clawfleet-dev-token-2026
```

---

## 第 6 步：全部启动

```bash
docker compose up -d
docker compose ps
docker compose logs -f
```

**✅ 预期结果：**
```
NAME             STATUS    PORTS
claw-manager     Up        0.0.0.0:3001->3000/tcp
claw-developer   Up        0.0.0.0:3002->3000/tcp
```

**✅ 服务访问：**

| 服务 | WebSocket | Canvas UI |
|------|-----------|-----------|
| Manager | `ws://localhost:3001` | `http://localhost:3001/#token=clawfleet-dev-token-2026` |
| Developer | `ws://localhost:3002` | `http://localhost:3002/#token=clawfleet-dev-token-2026` |

---

## 第 7 步：进入容器调试

```bash
# 进入 manager 容器
docker exec -it claw-manager sh

# 容器内检查
ls /data/.openclaw/.openclaw/     # 应有 openclaw.json
ls /data/agents/manager/          # 应有 agent.yaml, IDENTITY.md, SOUL.md
cat /data/.openclaw/.openclaw/openclaw.json
env | grep OPENAI                 # 检查环境变量是否注入
openclaw --version
openclaw health
openclaw gateway status

# 退出
exit
```

---

## 第 8 步：停止和清理

```bash
# 停止所有
docker compose down

# 停止单个
docker compose stop manager

# 停止并删除镜像（重新构建时）
docker compose down --rmi all
```

---

## 常见问题速查表

| 现象 | 可能原因 | 解决 |
|------|---------|------|
| 容器一直 Restarting | `openclaw.json` 缺失或格式错 | 重新 `docker compose build --no-cache manager` |
| `client version too old` | Docker CLI 版本低 | `brew reinstall docker` |
| `requires buildx 0.17.0` | buildx 太旧 | `brew install docker-buildx` |
| `unknown option` | Dockerfile CMD 参数错误 | CMD 应为 `gateway run --port 3000 --bind lan` |
| 端口冲突 | 3001 或 3002 被占用 | `lsof -i :3001` |
| `.env` 不生效 | 格式错误或路径错 | `docker compose config` 查看解析结果 |
| `curl http://localhost:3001` 无响应 | Gateway 是 WebSocket 不是 HTTP | 用 `websocat ws://localhost:3001` 或浏览器访问 `/__openclaw__/canvas/` |
| `{"error":"Unauthorized"}` | `.env` 中缺少 `OPENCLAW_GATEWAY_TOKEN` 或 URL 格式错 | URL 用 `http://localhost:3001/#token=clawfleet-dev-token-2026`（注意是 `#` 不是 `?`） |
| `non-loopback Control UI requires...` | 首次 bind=lan 需要 allowedOrigins | OpenClaw 自动修复，等容器自动重启即可 |

---

## 配置文件清单

```
ClawFleet/
├── .env                                       ← 环境变量（密钥，不提交 git）
├── docker-compose.yml                         ← 服务编排
├── agents/                                    ← 构建目录（只有 Dockerfile）
│   ├── manager/Dockerfile
│   └── developer/Dockerfile
└── data/                                      ← 运行时数据（volume 挂载）
    ├── .openclaw/                             ← OpenClaw 运行时状态（由镜像自动生成）
    │   ├── manager/.openclaw/openclaw.json
    │   └── developer/.openclaw/openclaw.json
    ├── agents/                                ← Agent 身份和配置
    │   ├── manager/
    │   │   ├── agent.yaml
    │   │   ├── IDENTITY.md
    │   │   └── SOUL.md
    │   └── developer/
    │       ├── agent.yaml
    │       ├── IDENTITY.md
    │       └── SOUL.md
    └── workspace/.gitkeep                     ← 共享工作空间
```

---

## 快速验证脚本

```bash
cd ~/ClawFleet

echo "=== 必需文件检查 ==="
for f in \
  .env \
  docker-compose.yml \
  agents/manager/Dockerfile \
  agents/developer/Dockerfile \
  data/agents/manager/agent.yaml \
  data/agents/manager/IDENTITY.md \
  data/agents/manager/SOUL.md \
  data/agents/developer/agent.yaml \
  data/agents/developer/IDENTITY.md \
  data/agents/developer/SOUL.md \
; do
  if [ -f "$f" ] && [ -s "$f" ]; then
    echo "✅ $f"
  else
    echo "❌ $f (缺失或为空)"
  fi
done

echo ""
echo "=== Dockerfile CMD 检查 ==="
grep "CMD" agents/manager/Dockerfile
grep "CMD" agents/developer/Dockerfile

echo ""
echo "=== 容器状态 ==="
docker compose ps 2>/dev/null || echo "❌ Docker Compose 不可用"

echo ""
echo "=== 端口检查 ==="
lsof -i :3001 -sTCP:LISTEN > /dev/null 2>&1 && echo "✅ 3001 有服务监听" || echo "⚠️  3001 无服务"
lsof -i :3002 -sTCP:LISTEN > /dev/null 2>&1 && echo "✅ 3002 有服务监听" || echo "⚠️  3002 无服务"

echo ""
echo "=== Gateway 健康检查 ==="
docker exec claw-manager openclaw health 2>/dev/null || echo "⚠️  Manager 未运行"
docker exec claw-developer openclaw health 2>/dev/null || echo "⚠️  Developer 未运行"
```
