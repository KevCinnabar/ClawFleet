OpenClaw Docker 安装页面中文解读

本文根据 OpenClaw 官方页面 https://docs.openclaw.ai/install/docker 的内容，整理成更容易理解的中文说明。

这页主要在讲什么

这页主要是在讲：如何使用 Docker 运行 OpenClaw，以及什么时候适合用 Docker，什么时候不太适合。

一个很重要的前提

Docker 不是必须的。

官方的意思是，如果你只是想在自己的电脑上本地开发，并且希望有更快、更直接的开发体验，那么不一定要用 Docker。Docker 更适合下面两种情况：
	1.	你想把 OpenClaw 跑在一个隔离、可丢弃的容器环境里
	2.	你想在没有完整本地依赖的主机上运行 OpenClaw

页面里还区分了两种 Docker 使用方式：
	•	Containerized Gateway：整个 OpenClaw gateway 都运行在 Docker 里
	•	Per-session Agent Sandbox：OpenClaw 主程序可以运行在宿主机上，但某些 agent 工具执行时使用 Docker 沙箱隔离

基本要求

官方要求至少具备以下条件：
	•	Docker Desktop 或 Docker Engine
	•	Docker Compose v2
	•	至少 2GB 内存，因为镜像构建时 pnpm install 在 1GB 主机上可能会因为内存不足被杀掉
	•	足够的磁盘空间用来存储镜像和日志

最推荐的启动方式：docker-setup.sh

官方推荐在仓库根目录执行：

./docker-setup.sh

这个脚本会自动帮你完成以下步骤：
	•	本地构建 gateway 镜像，或者如果设置了 OPENCLAW_IMAGE 就直接拉取远程镜像
	•	运行 onboarding 向导
	•	打印 provider 配置提示
	•	用 Docker Compose 启动 gateway
	•	生成 gateway token 并写入 .env

完成后，打开下面的地址：

http://127.0.0.1:18789/

然后把 token 粘贴到 Control UI 中。

如果之后还想重新获取 dashboard URL，可以执行：

docker compose run --rm openclaw-cli dashboard --no-open

这几个环境变量比较重要

页面列出了不少可选环境变量，比较关键的有：
	•	OPENCLAW_IMAGE：不本地 build，直接使用远程镜像，比如 ghcr.io/openclaw/openclaw:latest
	•	OPENCLAW_DOCKER_APT_PACKAGES：构建镜像时额外安装 apt 包，例如 ffmpeg、build-essential
	•	OPENCLAW_EXTENSIONS：提前把某些扩展依赖安装到镜像中
	•	OPENCLAW_EXTRA_MOUNTS：额外挂载宿主机目录到容器
	•	OPENCLAW_HOME_VOLUME：把 /home/node 持久化到 Docker volume
	•	OPENCLAW_SANDBOX=1：开启 Docker sandbox 支持

开启 sandbox 是什么意思

如果设置：

export OPENCLAW_SANDBOX=1
./docker-setup.sh

脚本会尝试初始化 agents.defaults.sandbox.* 相关配置。

如果你使用的是 rootless Docker，也可以指定 socket 路径，例如：

export OPENCLAW_DOCKER_SOCKET=/run/user/1000/docker.sock

文档还特别说明：
	•	只有在 sandbox 前置条件检查通过后，脚本才会挂载 docker.sock
	•	如果 sandbox 初始化失败，它会把 agents.defaults.sandbox.mode 重置为 off，避免留下坏配置
	•	如果缺少 Dockerfile.sandbox，脚本只会给出警告并继续；必要时需要手动构建 openclaw-sandbox:bookworm-slim

如果你不想本地 build

官方提供了 GitHub Container Registry 上的预构建镜像：

ghcr.io/openclaw/openclaw

常见 tag 包括：
	•	main：主分支最新构建
	•	<version>：某个发布版本
	•	latest：最新稳定版

例如：

export OPENCLAW_IMAGE="ghcr.io/openclaw/openclaw:latest"
./docker-setup.sh

这样脚本就会执行 docker pull，而不是 docker build。

但仍然需要在仓库根目录运行，因为还依赖本地的 docker-compose.yml 和辅助文件。

手动方式也可以

如果你不想使用 docker-setup.sh，文档也提供了手动流程：

docker build -t openclaw:local -f Dockerfile .
docker compose run --rm openclaw-cli onboard
docker compose up -d openclaw-gateway

如果启用了额外挂载或 home volume，脚本会生成 docker-compose.extra.yml，此时手动运行 compose 时也要把这个文件一起带上。

如果出现 unauthorized 或 pairing required

如果看到类似以下报错：
	•	unauthorized
	•	disconnected (1008): pairing required

可以重新获取 dashboard link，并审批浏览器设备请求：

docker compose run --rm openclaw-cli dashboard --no-open
docker compose run --rm openclaw-cli devices list
docker compose run --rm openclaw-cli devices approve <requestId>

关于挂载和持久化

1. 额外挂载目录

你可以通过 OPENCLAW_EXTRA_MOUNTS 把宿主机目录映射进容器，例如：

export OPENCLAW_EXTRA_MOUNTS="$HOME/.codex:/home/node/.codex:ro,$HOME/github:/home/node/github:rw"
./docker-setup.sh

它会自动生成 docker-compose.extra.yml。

路径格式必须是 source:target[:options]，而且不能有空格。macOS 和 Windows 下，这些路径还必须先在 Docker Desktop 里共享。

2. 持久化整个 /home/node

可以通过 OPENCLAW_HOME_VOLUME 指定 Docker named volume，这样即使容器被删除，home 目录里的内容仍然会保留。

3. 额外安装系统包

例如需要 ffmpeg 或编译工具链时，可以在构建镜像前设置：

export OPENCLAW_DOCKER_APT_PACKAGES="ffmpeg build-essential"
./docker-setup.sh

4. 预装扩展依赖

如果某些 extension 有自己的 package.json，可以提前安装到镜像里，避免首次加载时再装。

关于 Playwright

文档特别提到，如果你在容器里要使用 Playwright 浏览器：
	•	可以手动安装 Chromium
	•	最好把浏览器下载目录做持久化
	•	如果缺少系统依赖，建议在镜像构建阶段通过 OPENCLAW_DOCKER_APT_PACKAGES 安装，而不是运行时使用 --with-deps

健康检查和测试

文档提供了几种检查方式：

深度健康检查

docker compose exec openclaw-gateway node dist/index.js health --token "$OPENCLAW_GATEWAY_TOKEN"

E2E smoke test

scripts/e2e/onboard-docker.sh

QR import smoke test

pnpm test:docker:qr

lan 和 loopback 的区别

文档特别提醒，Docker 这里推荐使用 bind mode，例如 lan 或 loopback，而不是直接写 0.0.0.0 或 localhost。

默认情况下，docker-setup.sh 会把 OPENCLAW_GATEWAY_BIND 设为 lan，这样宿主机浏览器可以访问 127.0.0.1:18789。
	•	lan：宿主机浏览器和宿主机 CLI 都能访问 gateway 暴露出来的端口
	•	loopback：更偏向容器内部访问，宿主机直接访问可能失败

Sandbox 的默认行为

如果启用了 agent sandbox，默认行为大致是：
	•	默认镜像：openclaw-sandbox:bookworm-slim
	•	每个 agent 一个容器
	•	默认 workspaceAccess: "none"
	•	也支持只读 ro 或读写 rw
	•	空闲超过 24 小时或存活超过 7 天会自动清理
	•	默认没有外网网络访问

这说明官方的思路是：让 agent 的工具执行环境尽量隔离、最小权限、默认无网络，并按需开放能力。

最直白的总结

这页本质上在表达以下几点：
	1.	Docker 不是唯一安装方式，也不是默认最优开发方式。 如果你主要是本机开发并追求速度，普通安装方式可能更合适。
	2.	如果要使用 Docker，最推荐直接执行 ./docker-setup.sh，因为它会自动处理 build、onboard、compose 和 token 等步骤。
	3.	.env、额外挂载、home volume、sandbox、远程镜像等行为，主要都通过环境变量控制。
	4.	OpenClaw 的 Docker 设计并不只是“把程序装进容器”，还包含了 gateway、CLI、sandbox、安全隔离、浏览器工具限制 这一整套运行模型。

给你的实际理解建议

如果你现在的目标是“先把 OpenClaw 用 Docker 跑起来”，最实用的理解方式是：
	•	先准备好 Docker 和 Docker Compose
	•	进入 OpenClaw 仓库根目录
	•	直接执行 ./docker-setup.sh
	•	按页面提示完成 onboarding
	•	打开本地 dashboard
	•	后续再根据需要决定是否加 .env、mount、sandbox、远程镜像等配置

如果你只是想先快速开发和调试，Docker 不一定是最省事的路；但如果你更看重环境隔离、可迁移性和部署一致性，Docker 方式会更合适。