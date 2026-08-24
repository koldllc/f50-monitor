# F50 Monitor Android

这是安装在 F50 本机的 Android MVP：前台常驻服务负责只读采集和 LAN API，WebView 复用 `windows` Vue 界面。

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

令牌会在首次访问时随机生成并保存在应用私有目录，首选在 Android 设置页查看 LAN API 配对信息。`adb shell run-as ...` 只适用于 debuggable 的 debug APK。API 是只读的，不提供短信、AT 控制、配置写入或 scrcpy 接口。

## 当前限制

- 只读取本机 `127.0.0.1` Router goform；字段缺失时保留缓存并降级到 `/proc` CPU、内存和 thermal 温度。
- 展锐 `vendor.sprd.hardware.tool.IToolControl/default`（API >33）或 `vendor.sprd.hardware.log.ILogControl/default`（旧版）发送 `AT+CGEQOSRDP=1` 的只读探测可能受固件/SELinux 权限限制，失败时 QCI/速率字段为空。
- Android 端界面隐藏短信、scrcpy 投屏、在线反馈和 Windows 专属设置；这些能力不会通过 Android bridge 或 LAN API 暴露。
- 当前是调试 APK，未包含签名、应用商店发布和跨固件实机验收。
