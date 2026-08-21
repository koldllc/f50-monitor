# ☁️ F50 Monitor - 诊断反馈收集 Worker (Cloudflare Worker)

用于接收应用端「一键自动提交」的设备脱敏诊断报告，自动在 GitHub 仓库创建 Issue 或推送到飞书/企业微信/钉钉群，实现 0 服务器维护成本的一键反馈通道。

---

## 🚀 2 分钟极速部署教程

### 第一步：创建 Cloudflare Worker

1. 登录 [Cloudflare Dashboard](https://dash.cloudflare.com/)。
2. 在左侧菜单点击 **Compute (Workers) -> Workers & Pages**。
3. 点击 **Create application -> Create Worker**。
4. 命名为 `f50-feedback-api`，点击 **Deploy**。

### 第二步：粘贴 Worker 代码

1. 进入创建好的 Worker 详情页，点击右上角 **Edit code**。
2. 将本目录下的 [`worker.js`](worker.js) 内容完整复制并覆盖粘贴。
3. 点击右上角 **Deploy** 部署生效。

### 第三步：配置环境变量与密钥（可选）

在 Worker 详情页 -> **Settings** -> **Variables and Secrets** 中添加：

| 变量名 | 类型 | 说明 | 示例 |
| :--- | :--- | :--- | :--- |
| `GITHUB_REPO` | Plaintext 文本 | 您的 GitHub 仓库 | `koldllc/f50-monitor` |
| `GITHUB_TOKEN` | Secret 加密密钥 | GitHub Personal Access Token (需勾选 `repo` 权限) | `ghp_xxxxxx...` |
| `NOTIFY_WEBHOOK` | Secret 加密密钥 | 飞书/企业微信/钉钉/Telegram 机器人 Webhook URL | `https://open.feishu.cn/...` |

---

## 📲 在客户端应用中启用

部署完成后，Worker 会分配一个专属地址（如 `https://f50-feedback-api.yourname.workers.dev`）。

在 App 端的反馈页面中设置该地址，用户即可在诊断完成后直接点击 **「一键在线直传到云端」** 完成自动提交！
