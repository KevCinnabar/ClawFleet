# GitHub 集成配置指南

## 获取 GitHub Personal Access Token (PAT)

### 步骤 1: 访问 Token 设置页面

GitHub → Settings → Developer settings → Personal access tokens → **Fine-grained tokens**

直达链接：[https://github.com/settings/tokens?type=beta](https://github.com/settings/tokens?type=beta)

### 步骤 2: 创建 Fine-grained PAT

1. 点击 **"Generate new token"**
2. 填写 Token 信息：
   - **Token name**: `ClawFleet-Agent`
   - **Expiration**: 建议 90 天
   - **Repository access**: 选择 `Only select repositories` → 选择 `ClawFleet`
3. 权限设置（最小权限）：
   - **Contents**: Read and write（代码读写）
   - **Issues**: Read and write（Issue 管理）
   - **Pull requests**: Read and write（PR 管理）
   - **Metadata**: Read-only（自动勾选）
4. 点击 **"Generate token"**
5. 复制并保存 Token

### 步骤 3: 配置到项目

将 Token 填入 Agent 的 `.env` 文件：

```dotenv
GITHUB_TOKEN=github_pat_xxxxxxxxxxxxxxxx
GITHUB_REPOSITORY=YourOrg/ClawFleet
```

`entrypoint.sh` 会在容器启动时自动通过 `gh auth login --with-token` 完成认证。

## 环境需求

镜像中已预装 `gh` CLI，无需额外安装：

```bash
# 验证（在容器内）
docker exec claw-manager gh auth status
docker exec claw-manager gh repo view
```

## 注意事项

- Fine-grained PAT 比 Classic PAT 更安全，权限范围更小
- Manager 和 Developer 可以共用同一个 PAT
- Token 过期后需重新生成并更新 `.env`，然后 `docker compose restart <agent>`
- 不要将 Token 提交到 Git（`.gitignore` 已排除 `.env` 文件）
