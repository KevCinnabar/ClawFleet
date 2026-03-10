# Notion 集成配置指南

## 获取 Notion API Key

### 步骤 1: 访问 Notion 集成页面
访问 [Notion 集成管理页面](https://www.notion.so/profile/integrations/public)

### 步骤 2: 创建新集成
1. 在左侧菜单中找到 **Build** → **Internal Integrations**
2. 点击 **"Create a new integration"** 按钮
3. 填写集成信息表单：
   - Integration Name（集成名称）
   - Associated Workspace（关联的工作区）
   - Logo（可选）
4. 提交表单

### 步骤 3: 获取 API Key
1. 创建成功后，复制 **Internal Integration Secret** (API Key)
2. 妥善保存此密钥，不要泄露给他人

### 步骤 4: 配置到项目
将获取的 API Key 配置到以下位置：
```
skills.entries.notion.apiKey
```

## 注意事项
- API Key 具有访问您 Notion 数据的权限，请妥善保管
- 如果密钥泄露，请及时在 Notion 集成管理页面重新生成
- 确保将密钥配置到正确的配置项中
