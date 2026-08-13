# F50 Monitor ⚡

专为中兴 (ZTE) F50 5G 随身 WiFi (MiFi) 打造的轻量级 macOS 菜单栏状态监控应用。

![F50 Monitor 预览图](assets/preview.png)

> 💡 **说明**：显示全部完整数据（如 CPU/内存占用率、芯片温度及 QCI 签约速率等）需要设备安装 **UFI 高级后台 (UFI-TOOLS)**；理论上也适用于其他已安装 UFI 高级后台的随身 WiFi 设备。

## ✨ 特性

- ⚡ **菜单栏实时常驻**：支持自定义显示模式（仅图标、实时速率、CPU/内存占用、芯片温度、连接设备数、完整模式）。
- 📶 **蜂窝信号监控**：实时获取网络制式（5G SA/NSA, 4G LTE）、运营商、信号强度，以及 RSRP、SINR/SNR、RSRQ 信号指标与评级。
- 📊 **硬件状态感知**：监控 CPU 占用率、内存占用率、芯片温度及已连接设备数（需启用扩展 API 支持）。
- 🚀 **QCI & 签约速率**：支持通过 UFI-TOOLS 获取 QoS 及 QCI 签约上下行速率。
- ⚙️ **便捷交互**：一键刷新、一键直达 Web 后台、自定义刷新频率及后台管理密钥。
- 🔄 **自动更新**：启动时自动检测 GitHub Releases，可自动下载、校验并安装新版本，也可在设置中手动检查。

## 📥 安装与使用

### 直接下载

前往 [Releases](https://github.com/kelvinsze/f50-monitor/releases) 下载最新版本的 `F50.Monitor.zip`，解压后双击运行即可。

> **提示**：首次运行时若提示“未识别的开发者”，请在 macOS **系统设置 ➔ 隐私与安全性** 中点击“仍要打开”。

### 本地构建

系统要求：macOS 13.0+ (Ventura 及以上)

```bash
# 克隆仓库
git clone https://github.com/kelvinsze/f50-monitor.git
cd f50-monitor

# 编译并生成 F50 Monitor.app
./build.sh
```

构建完成后，可在当前目录直接运行 `F50 Monitor.app`。

## 📄 许可证

[MIT License](LICENSE)
