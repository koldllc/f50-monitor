# F50 Monitor Android

这是安装在 F50 本机的 Android 应用：前台常驻服务负责状态采集与只读 LAN API，WebView 复用 `windows` Vue 界面，并通过本机 typed bridge 提供设备控制。

## 构建与安装

先构建 Android Web 资源（需要 npm）：

```bash
cd windows
npm run build:android
```

再使用 Android Studio 打开 `android/` 构建，或在已安装 Gradle 8.9、JDK 17 和 Android SDK 的环境执行：

```bash
gradle -p ../android assembleDebug
adb install -r ../android/app/build/outputs/apk/debug/app-debug.apk
```

Gradle task 会调用同一个 `npm run build:android` 并把 `windows/dist` 临时复制到 APK assets；`dist` 和 `build/` 均不应提交。当前工程未提交 Gradle wrapper，因此没有全局 Gradle 时请使用 Android Studio。

也可以只安装已生成的 APK：

```bash
adb install -r android/app/build/outputs/apk/debug/app-debug.apk
adb shell am start -n com.kold.f50.monitor.android/.MainActivity
```

首次打开后会显示 Android 前台服务通知。服务通过 `START_STICKY` 维持运行，并在配置允许时监听 `BOOT_COMPLETED`；某些 F50 固件仍可能需要在系统设置中允许“自启动”和“忽略电池优化”。Android 14+ 使用 `specialUse` 前台服务类型，避免把路由器监控误报成 `dataSync`。

## LAN API

服务监听 `0.0.0.0:8787`：

```text
GET /health
GET /api/v1/status
GET /api/v1/capabilities
```

只有 `/health` 无需鉴权。其它请求必须带 `X-F50-Agent-Key`。安装后可通过 adb 读取持久化令牌（仅用于调试/局域网配对）：

```bash
adb shell run-as com.kold.f50.monitor.android cat shared_prefs/f50_agent.xml
```

令牌会在首次访问时随机生成并保存在应用私有目录，首选在 Android 设置页查看 LAN API 配对信息。`adb shell run-as ...` 只适用于 debuggable 的 debug APK。`8787` API 保持只读；移动数据、APN、客户端、SMS、网络模式、Band / Cell Lock 与重启仅通过应用本机的 typed bridge 暴露，不提供任意 shell、AT 或 goform 透传。

## 当前限制

- 优先尝试 `192.168.0.1` Router goform，旧版 `127.0.0.1` 配置会自动迁移；MU300 固件若阻止本机回连 LAN Web 服务，则降级到 Android Telephony、`sipa_eth0` 及 `/proc` 的只读状态。
- 展锐 `vendor.sprd.hardware.tool.IToolControl/default`（API >33）或 `vendor.sprd.hardware.log.ILogControl/default`（旧版）发送 `AT+CGEQOSRDP=1` 的只读探测可能受固件/SELinux 权限限制，失败时 QCI/速率字段为空。
- Android 端仍隐藏 scrcpy 投屏、在线反馈和 Windows 专属设置。设备控制依赖目标固件的 Router goform；各写操作必须以真实设备回读结果验收。
- 当前是调试 APK，未包含签名、应用商店发布和跨固件实机验收。
