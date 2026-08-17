# F50 Monitor for Windows ⚡ (Tauri + Rust + Vue 3)

专为中兴 (ZTE) F50 5G 随身 WiFi (MiFi) 打造的 Windows 任务栏系统托盘轻量监控应用。基于 **Tauri 2.0 (Rust) + Vue 3 + Vite** 构建，内存占用低（~35MB），体积小巧（~10MB）。

---

## ✨ Windows 版本特性

- ⚡ **Windows 任务栏托盘常驻**：支持右下角托盘图标自定义显示模式、悬浮卡片面板一键呼出与快捷右键菜单。
- 📶 **蜂窝信号质量感知**：实时监控 5G SA/NSA 与 4G LTE 制式、频段聚合（`B3 + n78`）、运营商，以及 RSRP、SINR、RSRQ 信号评级。
- 🚀 **QCI & 签约速率**：通过 UFI-TOOLS 解析 QoS 签约上下行速率。
- 📊 **硬件与连接监控**：实时监控 CPU 占用率、内存占用率、芯片温度及已连接 Wi-Fi 设备数量。
- 📈 **实时动态速率波形**：Bézier 贝塞尔平滑波形图展示当前下载/上传瞬时速率走势。
- 🔁 **套餐用量与重置倒计时**：清晰掌握套餐累计用量、当日累计、本月累计与账单重置天数提醒。
- 💬 **短信收发与验证码快捷复制**：读取短信箱、未读红点标记、正则表达式一键提取并复制验证码，并支持在应用内直接发送短信。
- 📺 **无线投屏 (scrcpy)**：内置 Windows 独立组件一键自动下载与配置，一键通过无线 ADB 拉起 scrcpy 超低延迟投屏窗口。
- 🚪 **开机自启动**：一键开启 Windows 登录时静默启动并常驻托盘。
- 🌐 **后台双入口直达**：快速直达中兴路由器官方后台 (80 端口) 或 UFI 高级后台 (2333 端口)。

---

## 🛠️ 本地开发与构建

### 1. 前置环境要求

- **Node.js**：v18+ 及 npm / pnpm
- **Rust 工具链**：[https://rustup.rs/](https://rustup.rs/) (安装 stable-x86_64-pc-windows-msvc)
- **Windows 构建工具**：Visual Studio 2022 (勾选 "C++ 桌面开发")
- **WebView2 运行时**：Windows 10/11 通常已内置

### 2. 依赖安装

进入 `windows` 目录执行：

```bash
cd windows
npm install
```

### 3. 本地开发预览

```bash
# 纯前端界面调试（含完整 Mock 数据源）
npm run dev

# 启动完整 Tauri 桌面端调试（带 Rust 原生托盘与网络请求）
npm run tauri dev
```

### 4. 打包 Windows 安装包与单文件 Exe

```bash
npm run tauri build
```

打包完成后，可在 `src-tauri/target/release/bundle/msi/` 或 `src-tauri/target/release/bundle/nsis/` 中获取安装包与可执行文件。

---

## 📁 目录架构说明

```
windows/
├── index.html                  # Web 入口页面
├── package.json                # 前端与 Tauri 脚本配置
├── vite.config.js              # Vite 打包配置
├── src/                        # 前端界面源码 (Vue 3)
│   ├── App.vue                 # 顶级悬浮面板与视图路由
│   ├── main.js                 # 渲染入口与窗口失焦隐藏处理
│   ├── stores/
│   │   └── f50Store.js         # 响应式状态管理、Tauri IPC 桥接与 Mock 数据
│   ├── components/
│   │   ├── Header.vue          # 运营商 Logo、网络制式 Badge、状态指示与操作栏
│   │   ├── SpeedCard.vue       # 实时速率与平滑贝塞尔波形图
│   │   ├── SignalCard.vue      # 信号强度格子与 RSRP/SINR/RSRQ 评级轨道
│   │   ├── TrafficCard.vue     # 套餐流量进度、重置倒计时与当日/本月用量
│   │   ├── HardwareCard.vue    # CPU、内存、温度仪表盘与 Wi-Fi 设备数
│   │   ├── SMSView.vue         # 短信列表、未读提醒与验证码一键复制
│   │   ├── ComposeSMSView.vue  # 发送短信交互表单
│   │   ├── SettingsView.vue    # 连接 IP、密码/Token、刷新频率与开机启动设置
│   │   ├── ScreenMirrorModal.vue# scrcpy 一键下载与无线投屏启动器
│   │   └── FooterActions.vue   # 底部双后台直达与功能入口
│   ├── styles/
│   │   └── theme.css           # F50Theme 低饱和度配色体系与暗黑模式
│   └── assets/                 # 运营商矢量图标 (移动/联通/电信/广电)
└── src-tauri/                  # Rust 原生后端
    ├── Cargo.toml              # Rust 依赖 (reqwest, sha2, md5, hmac, zip, winreg)
    ├── tauri.conf.json         # 托盘、无边框透明悬浮窗与权限配置
    └── src/
        ├── main.rs             # 应用程序入口
        ├── lib.rs              # Tauri IPC 命令注册与后台轮询线程
        ├── models.rs           # 数据结构定义 (F50Status, F50Configuration 等)
        ├── crypto.rs           # UFI kano_sign 签名、SHA-256、MD5 与 GSM UTF-16BE 编码
        ├── fetcher.rs          # 中兴 80 / UFI 2333 双端口轮询引擎与短信收发
        ├── scrcpy.rs           # Windows 版 scrcpy 自动获取与无线 ADB 控制
        ├── autostart.rs        # Windows 注册表开机自启适配
        ├── config.rs           # AppData 配置持久化存储
        └── tray.rs             # 任务栏托盘图标与屏幕吸附定位
```
