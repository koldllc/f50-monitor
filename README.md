# F50 Monitor ⚡

面向中兴 (ZTE) F50 / V50 5G 随身 WiFi (MiFi) 的桌面端（macOS / Windows）状态监控与短信管理应用。

![F50 Monitor 2.0 功能海报](assets/f50-monitor-v2.0-poster.jpg)

> 💡 **提示**：应用已实现数据通道全面重构，不再主要依赖 UFI 高级后台代理。只需设备开启 ADB，应用即可通过 5555 端口原生 Socket 读取 CPU/内存占用率、芯片温度及 QCI 签约速率等全量指标。数据接口按优先级 **80 (中兴 Router 后台) ➔ 5555 (原生 ADB 调试端口) ➔ 2333 (UFI 高级后台)** 自动无缝降级与回退；理论上也适用于其他已开启 ADB 的展锐/高通随身 WiFi 设备。
> 
> 📖 **玩机教程**：如需了解如何开启设备 ADB 调试、修改 IMEI、全量分区备份、解锁 Bootloader 或跨固件刷机，请参阅 [**中兴 F50 / 飞猫 U20 开启 ADB、改串与刷机全指南 🛠️**](docs/ADB_AND_FLASHING_GUIDE.md)。

## ✅ 适配设备

- F50
- F50 Pro
- V50（已验证 MU3351V1.0.0B22）
- U30 Air
- M3
- 飞猫 U20（刷中兴固件或开启 ADB 后可用）

---

## 📖 玩机与设备配置指南

想要充分发挥 F50 Monitor 的全部硬件监控特性（如 QCI 速率、实时温度与 CPU/内存占用），建议开启设备的 ADB 调试端口。

我们整理了详尽的设备玩机指引文档：
👉 [**中兴 F50 / 飞猫 U20 开启 ADB、改串与刷机全指南 🛠️**](docs/ADB_AND_FLASHING_GUIDE.md)

**指南包含核心内容**：
- 🔌 **开启 ADB 调试**：中兴原生后台 URL 注入法 (`#usb_port`) 与飞猫 U20 PowerShell 自动签名开启脚本。
- 📱 **工程模式与改串 (IMEI)**：通过投屏与紫光展锐工程暗码 (`*#*#83781#*#*`) 发送 AT 指令免 Root 改串。
- 💾 **全分区备份与底层刷机**：基于 `spd_dump` 的 70+ 全量分区备份、工程 U-Boot 刷入、Bootloader 解锁与跨固件互刷。
- 🛡️ **基带安全规范**：跨机刷入时规避覆盖 `nr_*`、`prodnv`、`miscdata` 等私有基带与校准分区。
- 🩹 **救砖与故障排除**：飞猫 U20 刷 F50 固件后反复重启修复（大电流供电 + RESET 重置）及固件版本推荐。

---

## 📦 各平台下载安装

前往 [GitHub Releases](https://github.com/koldllc/f50-monitor/releases/latest) 下载最新稳定版本：

| 平台 / 设备 | 推荐下载文件 | 说明 |
| :--- | :--- | :--- |
| 🍏 **macOS (苹果电脑)** | [**`f50-monitor-macos.zip`**](https://github.com/koldllc/f50-monitor/releases/latest) | 菜单栏常驻工具，解压即用（支持 Apple Silicon M 系列芯片与 Intel Mac） |
| 🪟 **Windows (主流电脑)** | [**`f50-monitor-windows-x64.exe`**](https://github.com/koldllc/f50-monitor/releases/latest) | 适用 99% 常见 Windows 电脑（Intel / AMD 处理器），绿色单文件免安装 |
| 🪟 **Windows (ARM 设备)** | [**`f50-monitor-windows-arm64.exe`**](https://github.com/koldllc/f50-monitor/releases/latest) | 适用高通骁龙 ARM 架构 Windows 设备（如 Surface Pro 11 等） |

> 🍏 **macOS 首次运行提示**：若提示“未识别的开发者”，请在 macOS **系统设置 ➔ 隐私与安全性** 中点击“仍要打开”。  

---

## ✨ 核心特性

- 🔄 **数据通道全面重构 (80 ➔ 5555 ➔ 2333)**：不再主要依赖 UFI 代理接口。应用内置多级降级机制，优先通过中兴 Router 原厂官方后台（80 端口）获取基础网络与信号数据，若未就绪或需拓展硬件指标则自动回退至 5555 端口通过原生 TCP Socket 与 ADB 交互直读底层 `/proc` 与 Binder 服务，最后兜底 UFI / MiniKano 工具箱代理（2333 端口）。只要开启 ADB 即可轻松获取 CPU/内存负载、芯片温度与 QCI 签约速率等全量数据。
- 🩺 **自动化诊断与一键反馈**：新增跨平台的自动化诊断反馈通道。遇到连接异常、数据缺失或新设备适配需求时，应用可一键自动采集完整的网络接口响应、系统版本与日志诊断数据，本地完成密码/IMEI/电话等敏感信息安全脱敏，直接提交反馈或生成 Issue，方便开发者快速定位 Bug 与高效适配新设备。
- ⚡ **菜单栏 / 任务栏实时常驻**：支持自定义显示模式（仅图标、实时速率、套餐用量、CPU/内存占用、芯片温度、Wi-Fi 设备数）。
- 📶 **蜂窝信号与频段感知**：实时获取网络制式（5G SA/NSA, 4G LTE）、`B3 + n78` 聚合频段、运营商标志，以及 RSRP、SINR/SNR、RSRQ 信号质量评级。
- 📊 **硬件状态与容错感知**：全面适配多源硬件指标抓取，监控 CPU/内存负载与芯片各热切片温度；未就绪或断开时优雅展示 `--` 占位。
- 🌐 **内网穿透与自签名证书信任**：支持直接输入域名直连穿透服务，苹果 ATS 全域网络放开，深度支持自签名 SSL 与各类反向代理。
- 💬 **短信读写与验证码识别**：查看最近短信、未读角标通知提醒，支持应用内直接发送短信及验证码一键复制。
- 🔁 **流量账单日与重置倒计时**：自动识别设备流量清零日（账单日），面板与小组件显示“N 天后重置”。
- 📺 **无线投屏 (scrcpy)**：通过无线 ADB + scrcpy 将设备屏幕镜像到电脑，内置依赖组件一键自动配置。
- 🚪 **登录自启动与自动更新**：支持开机静默启动驻留；macOS 端内置 GitHub Releases 自动增量检测与更新。

---

## 🛠️ 各端本地构建与开发

### 🍏 macOS 版 (SwiftUI)

系统要求：macOS 13.0+ (Ventura 及以上)

```bash
# 有多个本地分支时先选择，然后编译、打包并自动安装到应用程序目录
./build.sh
```

### 🪟 Windows 版 (Tauri 2.0 + Vue 3 + Rust)

环境要求：Node.js 20+、Rust 1.75+、WebView2

```bash
cd windows

# 1. 安装依赖
npm install

# 2. 启动前端 Mock 调试
npm run dev

# 3. 启动桌面端调试
npm run tauri dev

# 4. 构建单文件可执行程序
npm run tauri build -- --no-bundle
```

---

## 📄 许可证

[MIT License](LICENSE)
