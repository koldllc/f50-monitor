# F50 Android 13 更底层采集与反向控制可行性

> 研究日期：2026-08-25。目标平台是 F50 / MU300、Android 13、展锐（Spreadtrum/Unisoc）。本文是源码与 API 层面的可行性判断；除文中已注明的既有只读验证外，所有写操作都仍需目标固件实机验证。

## 结论

**能做，但不能把“装一个普通 APK”理解为自然拥有路由器系统权限。** 最现实的路线是分层代理：

1. 普通 APK 继续承担 UI、只读缓存和 `8787` LAN API；
2. 优先复用设备原生 Router `80` 的固定 `goformId`，或已安装 UFI-TOOLS `2333` 的签名 API；
3. 没有 UFI 时，以 ADB/Shizuku 的 `shell` 身份调用经过白名单的 Android shell/Binder 操作；
4. Band Lock、Cell Lock、明确区分 5G SA/NSA 等展锐专有能力，最终仍需厂商 Binder/AT、Root，或 OEM 预装的系统代理。

当前 Android Agent 的 `Runtime.exec("sh")` **仍是应用自身 UID，不是 ADB shell，也不是 Root**。因此现有 `service call vendor.sprd...` 只读探测能否成功，完全取决于厂商 Binder/SELinux 是否放行普通应用；引入 Shizuku 后才会变成 UID 2000 `shell`，Root/Sui 才可能是 UID 0。Shizuku 官方说明也强调 ADB 与 Root 权限差异很大，并且权限随 Android/厂商版本变化。[Shizuku API](https://github.com/RikkaApps/Shizuku-API/blob/master/README.md)

## 权限层级

| 层级 | 实际身份与边界 | 对 F50 的价值 |
| --- | --- | --- |
| 普通 APK | 独立应用 UID + SELinux 沙箱；只能用公开 API、用户授予的危险权限和设备明确放行的 Binder | 安全、易安装，适合只读状态和控制 UI；系统网络配置能力很少 |
| ADB / Shizuku | 通常是 UID 2000 `shell`、`u:r:shell:s0`；可执行 `cmd`/`svc`/`service call`，但不是 Root，权限随固件变化，重启后 Shizuku 通常需重启 | F50 已验证 shell 可经展锐 Binder读取 AT；适合作为低侵入控制代理 |
| Root / Sui | UID 0，但仍受 SELinux、设备节点占用和厂商实现约束 | 可操作厂商服务、iptables/netd/hostapd、系统数据库；工程与失联风险显著增加 |
| 系统签名 / `priv-app` | 需 OEM 平台密钥，或预装到系统镜像并加入 privileged-permission allowlist；仅把 APK 放到 `/system` 不等于获得全部权限 | 产品化最稳，但第三方通常拿不到平台签名，且还可能需要 vendor SELinux 策略 |
| Router `80` / UFI `2333` | 不是 Android 权限提升。`80` 是设备原生 Web 后端；`2333` 是 UFI-TOOLS 对 goform、AT 和可选 RootShell 的封装 | 对既有 F50 最接近“设备管理 API”；但端点、参数、鉴权和固件兼容性都不是 Android 标准 |

Android 的应用沙箱和 SELinux 会同时限制普通 APK。[AOSP Application Sandbox](https://source.android.com/docs/security/app-sandbox)；`WRITE_APN_SETTINGS`、`TETHER_PRIVILEGED` 等在 AOSP 中是 `signature|privileged` 权限，[AOSP framework manifest](https://android.googlesource.com/platform/frameworks/base/+/master/core/res/AndroidManifest.xml)。priv-app 还必须在系统镜像的特权权限 allowlist 中，[AOSP privileged permission allowlist](https://source.android.com/docs/core/permissions/perms-allowlist)。

## 能力矩阵

标记：✅ 有标准/已有实现路径；🟡 取决于权限、厂商 Binder 或固件；❌ 该层级没有可靠通用路径。

| 能力 | 普通 APK | ADB / Shizuku (`shell`) | Root | 系统签名 / priv-app | Router `80` / UFI `2333` | 判断 |
| --- | --- | --- | --- | --- | --- | --- |
| 5G SA / NSA / 自动 | ❌ 公开 API 只能按 RAT 允许 NR/LTE，不能明确选择 SA/NSA | 🟡 AOSP `cmd phone` 可改允许 RAT；SA/NSA 仍需展锐专有命令 | ✅ 可调用厂商 Binder/AT；需命令白名单 | 🟡 `MODIFY_PHONE_STATE` 仍只覆盖 RAT，SA/NSA 需 vendor 接口 | ✅ UFI 已提供 5G/4G/3G、NSA、SA 等模式；80 的具体 `goformId` 需从固件确认 | **优先 UFI/原厂接口；不把 NR bitmask 误称为 SA/NSA 开关** |
| 移动数据开关 | 🟡 仅 carrier privileges 或 `MODIFY_PHONE_STATE` 可调用 `setDataEnabledForReason` | ✅ `svc data enable/disable` 在新系统转到 `cmd phone data` | ✅ | ✅ | ✅ UFI 已实现；80 通常有固定 goform 动作但需目标固件确认 | **低难度，适合首批写控制** |
| APN | ❌ Android 11+ 读取/写入 APN 数据库都要求 privileged `WRITE_APN_SETTINGS`（carrier privileges 是例外路径） | ❌ AOSP Android 13 的 shell manifest 没有 `WRITE_APN_SETTINGS`；厂商另行放行时才可能例外 | ✅ 技术上可改 provider/厂商配置，但错误会立即断网 | ✅ 需 privileged allowlist | ✅ UFI 已有增删改/自动手动 APN；80 可优先复用原厂动作 | **优先原厂/UFI，不直接改数据库** |
| DNS | 🟡 `VpnService` 只能为本机 VPN 指定 DNS，不等于修改热点客户端 DNS | ✅ AOSP shell 有 `WRITE_SECURE_SETTINGS`，可改本机全局 Private DNS；但不保证作用于 tethering 下游客户端 | 🟡 可改 netd/dnsmasq/iptables 或 DHCP，强依赖固件且容易失联 | 🟡 Device Owner 可用公开 API 管全局 Private DNS；热点下游仍需 Tethering/OEM 集成 | ❌ UFI 用户文档未给出 DNS 项；80 是否有对应 goform 尚无证据 | **先定义“设备自身 DNS”还是“Wi-Fi 客户端 DNS”；后者需 DHCP/tethering 实测** |
| 整机重启 | ❌ `PowerManager.reboot()` 要求 signature `REBOOT` | ✅ `adb reboot` / shell power 命令 | ✅ | ✅ | ✅ UFI 已实现重启；80 原厂动作需抓取确认 | **低难度，但远程调用必须二次确认** |
| Wi-Fi 客户端列表 | 🟡 公共 Soft AP 回调/邻居信息受权限和实现限制 | ✅ AOSP shell 有 `NETWORK_SETTINGS`，可用受限 Soft AP 接口或 dumpsys；字段质量仍依固件 | ✅ 可组合 hostapd/ARP/DHCP 数据 | ✅ Tethering/Wi-Fi 系统接口更完整 | ✅ 80 已有数量字段；UFI 显示主机名、MAC、IP、接入类型 | **优先 UFI/Router；Android 底层作为补充** |
| 踢设备 / 黑名单 | ❌ 公共第三方 API 不提供通用热点客户端强制断开 | 🟡 AOSP 内部支持 Soft AP force-disconnect，但 shell CLI/权限和芯片能力须实测 | ✅ hostapd 或系统 Wi-Fi service 可做，仍需驱动支持 | ✅ 需 `TETHER_PRIVILEGED`/NetworkStack 类权限及硬件支持 | ✅ UFI 已实现按 MAC 拉黑/解封；这是比“只踢一次”更稳定的控制 | **优先 UFI 黑名单；避免 802.11 注入式 deauth** |
| SMS 收发 | 🟡 在安装器 allowlist、用户授予 `SEND_SMS`/`RECEIVE_SMS` 等 hard-restricted 权限后可发送/接收；写 SMS Provider 通常仅默认 SMS 应用 | ✅ AOSP Android 13 shell 声明了 SMS 权限，但 OEM/AppOps 仍需实测；裸 `service call isms` 的 transaction code 不稳定 | ✅ 可走 framework/Binder/厂商路径 | ✅ | ✅ 当前 F50 已通过 UFI goform 读取和发送 | **普通 APK 可做，但默认 SMS 角色和隐私范围需单独设计** |
| 网络模式（仅 4G、NR+LTE 等） | 🟡 只有 carrier privileges 或 `MODIFY_PHONE_STATE` 才可 `setAllowedNetworkTypesForReason` | ✅ 可调用 phone shell/隐藏 Binder；需按 Android 13 实测参数 | ✅ | ✅ | ✅ UFI 已实现常见模式 | **AOSP 可覆盖 RAT，厂商模式以 UFI/AT 为准** |
| Band Lock | ❌ 无 AOSP 公共 API | 🟡 AOSP SystemApi `setSystemSelectionChannels` 可限制 modem 扫描的 band/channel，但依赖 Radio HAL ≥1.3、厂商可返回 not supported，且不等同于强制 serving-band lock；真正锁频仍需展锐接口 | ✅ 可走厂商 Binder/AT；切勿抢占 modem tty | 🟡 AOSP 限制扫描路径可用，真正锁频仍需要展锐私有接口 | ✅ UFI 已实现 4G/5G 锁频与解锁 | **高风险、强厂商耦合，必须先获取“解锁/恢复自动”命令** |
| Cell Lock | ❌ 无 AOSP 公共 API | 🟡 同上；需验证写事务和 SELinux | ✅ | 🟡 仍需要展锐私有接口 | ✅ UFI 文档给出 `CELL_LOCK`，参数为 PCI、EARFCN、RAT（4G=12、5G=16） | **最高失联风险；只允许 typed API，禁止任意透传** |

### 关键一手依据

- Android 13 的 `TelephonyManager.setAllowedNetworkTypesForReason()` 接受 GSM/UMTS/LTE/NR 等 bitmask，要求 `MODIFY_PHONE_STATE` 或 carrier privileges；API 没有 SA/NSA 选择参数。[Android TelephonyManager](https://developer.android.com/reference/android/telephony/TelephonyManager#setAllowedNetworkTypesForReason(int,%20long))
- `setDataEnabledForReason()` 同样要求 `MODIFY_PHONE_STATE`，部分 USER/CARRIER 场景可由 carrier privileges 调用。[Android TelephonyManager](https://developer.android.com/reference/android/telephony/TelephonyManager#setDataEnabledForReason(int,%20boolean))；AOSP 的 `svc data` 已转发到 `cmd phone data enable/disable`，[AOSP `svc`](https://android.googlesource.com/platform/frameworks/base/+/b8f1b91abbd7/cmds/svc/svc)。
- Android 13 的 shell 权限清单包含 `MODIFY_PHONE_STATE`、`REBOOT`、`NETWORK_SETTINGS`、`WRITE_SECURE_SETTINGS` 和 SMS 权限，但没有 `WRITE_APN_SETTINGS`。[AOSP Android 13 Shell manifest](https://android.googlesource.com/platform/frameworks/base/+/android-13.0.0_r83/packages/Shell/AndroidManifest.xml)
- Android 11 起，访问 Telephony APN provider 要求 privileged `WRITE_APN_SETTINGS`。[Android 11 behavior change](https://developer.android.com/about/versions/11/behavior-changes-11#access-apn-database)
- `PowerManager.reboot()` 要求 `REBOOT`，Android 13 的 PowerManagerService 会在 Binder 入口强制检查该权限。[Android 13 PowerManager](https://android.googlesource.com/platform/frameworks/base/+/refs/tags/android-13.0.0_r83/core/java/android/os/PowerManager.java)；[Android 13 PowerManagerService](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/android13-release/services/core/java/com/android/server/power/PowerManagerService.java)
- AOSP Soft AP 明确存在“按客户端强制断开”的硬件 capability，且实现会对黑名单客户端调用 `forceClientDisconnect()`；这不是普通第三方 APK 的稳定公开控制面。[SoftApCapability](https://android.googlesource.com/platform/packages/modules/Wifi/+/77baf392228746e5f58437f0a51816de0dc7f440/framework/java/android/net/wifi/SoftApCapability.java)；[SoftApManager](https://android.googlesource.com/platform/packages/modules/Wifi/+/ab7b9b91f4/service/java/com/android/server/wifi/SoftApManager.java)
- `VpnService.Builder.addDnsServer()` 只为所建立的 VPN 网络设置解析器；`Settings.Global` 明确说明普通应用不可直接写全局设置；公开的全局 Private DNS 管理 API 面向 Device Owner。[VpnService.Builder](https://developer.android.com/reference/android/net/VpnService.Builder#addDnsServer(java.net.InetAddress))；[Settings.Global](https://developer.android.com/reference/android/provider/Settings.Global)；[DevicePolicyManager](https://developer.android.com/reference/android/app/admin/DevicePolicyManager#setGlobalPrivateDnsModeSpecifiedHost(android.content.ComponentName,%20java.lang.String))
- Android 的 SMS 危险权限还受默认 handler/Play 政策约束；Android Q 起应通过 `RoleManager.ROLE_SMS` 请求默认短信角色。[Android default handlers](https://developer.android.com/guide/topics/permissions/default-handlers)；[Telephony.Sms.Intents](https://developer.android.com/reference/android/provider/Telephony.Sms.Intents#ACTION_CHANGE_DEFAULT)
- UFI-TOOLS 的一手项目文档明确列出数据开关、SA/NSA/网络模式、APN、Band Lock、Cell Lock、短信、重启、接入设备与黑名单；同时说明部分高级功能依赖具体机型、固件和 Root。[UFI-TOOLS User Doc](https://github.com/kanoqwq/UFI-TOOLS/blob/http-server-version/User_Doc.md)；[UFI-TOOLS README](https://github.com/kanoqwq/UFI-TOOLS)
- AOSP 的 `setSystemSelectionChannels()` 是限制 modem 扫描 band/channel 的 SystemApi，Radio HAL 可以返回 unsupported；不能把它当成已验证的强制 serving-band lock。[TelephonyManager source](https://android.googlesource.com/platform/frameworks/base/+/7516354f0637411d63507f6329b77a879882be3e/telephony/java/android/telephony/TelephonyManager.java)；[Android 13 RIL](https://android.googlesource.com/platform/frameworks/opt/telephony/+/refs/heads/android13-dev/src/java/com/android/internal/telephony/RIL.java)

注意：UFI-TOOLS 是相关设备的开源实现证据，不是 ZTE/Unisoc 的稳定 API 合约。端点与参数必须以安装版本源码和目标固件实测为准。

## 更底层“数据获取”路线

建议按侵入性从低到高合并数据，而不是用 Root 全量替换 Router 数据：

1. **Router `80`**：继续作为运营状态、信号、当前频段、流量和 Wi-Fi 数量的首选来源。它最贴近设备原生管理面。
2. **Android 公开 API**：补充 `ServiceState`、`SignalStrength`、`CellInfo`、`NetworkCapabilities`、电池、thermal、`/proc`。蜂窝小区信息会受 `READ_PHONE_STATE`、位置权限、位置开关和运营商裁剪影响。
3. **ADB/Shizuku shell**：按固定频率读取 `dumpsys telephony.registry`、`dumpsys connectivity`、`dumpsys wifi`，以及白名单展锐 Binder AT。shell 输出不是稳定 schema，必须按 Android/固件版本适配。
4. **展锐 Binder/AT**：当前目标机已经以 ADB shell 验证 `vendor.sprd.hardware.log.ILogControl/default` 的 `AT+CGEQOSRDP=1` 可读取 QCI/AMBR；详见仓库现有 [direct-at-without-ufi.md](./direct-at-without-ufi.md)。下一步只做只读命令枚举与返回格式记录，不先尝试写命令。
5. **Root/vendor 节点**：只有 Binder 不足时才研究 `/dev/stty_lte*`、RIL 日志或 vendor service。直接占用 modem tty 可能与 RIL 冲突，不应成为默认采集路径。

当前 Agent 只声明网络、启动和前台服务权限，`capabilities()` 也明确返回 `readOnly: true`；`8787` 仅暴露 `/health`、`/api/v1/status`、`/api/v1/capabilities`。这是一条应保留的安全边界，而不是缺少几个 command handler 而已。

## 建议实施路线

### Phase 0：保持 `8787 v1` 只读

- 不在现有 `/api/v1` 上加入任意 shell、任意 AT 或任意 goform 透传。
- 增加只读 capability probe：`app`、`shell/Shizuku`、`root`、`router80`、`ufi2333`、vendor Binder 服务存在性与实际权限。
- 先记录每项能力的 `supported / permission_required / unverified / unavailable`，不要仅凭服务存在就显示可操作。

### Phase 1：先接低风险、可恢复控制

优先顺序：**移动数据开关 → 网络模式（自动/仅 4G）→ Wi-Fi 客户端黑名单/解封 → SMS**。

- 首选 Router `80` 的已确认固定 `goformId`；其次代理 UFI `2333` 的明确 API。
- 若走 Shizuku，只暴露硬编码动作，不接受调用方传入 shell 字符串。
- 每次写入后重新读取状态，只有“写请求成功 + 状态收敛”才报告成功。

### Phase 2：高风险蜂窝控制

SA/NSA、APN、Band Lock、Cell Lock 必须具备：

- 写前快照；
- 明确的恢复自动/解锁动作；
- 30–120 秒 watchdog 自动回滚；
- 若控制请求来自当前热点客户端，必须预警“操作可能立即断开本连接”；
- 离线恢复入口（USB ADB 或本机 UI），不能只依赖将被改变的蜂窝/Wi-Fi 链路。

### Phase 3：仅在确有需求时做 Root / OEM 系统代理

- 对量产体验，OEM 平台签名 + priv-app + vendor SELinux policy 最稳，但这需要固件合作，不是 APK 工程内部可解决。
- 对现有个人设备，Root/Sui 比伪装成系统应用更现实；仍应把 Root 进程缩成最小权限代理。
- 不建议为了 DNS 单项能力引入 Root；先澄清 DNS 的作用域，并验证原厂 DHCP/tethering 是否已有可配置入口。

## 控制 API 的安全约束

远程控制比当前只读 `X-F50-Agent-Key` 风险高一个等级。建议新建独立的 `control v2`，并满足：

- 默认关闭；首次必须在设备本机开启并配对；
- 只允许 typed actions，例如 `setMobileData(enabled)`、`setNetworkMode(mode)`，绝不提供 `execShell(command)` / `sendAT(command)`；
- 请求包含 nonce、时间戳、短有效期并防重放；控制密钥与只读密钥分离；
- 限制来源网段、速率和失败次数，记录操作者、前后状态与结果，但不记录 APN 密码/SMS 正文等敏感内容；
- 重启、APN、Band/Cell Lock、拉黑当前管理端必须二次确认；
- 服务端强制参数范围：Band 白名单、PCI/EARFCN/RAT 类型校验、禁止 shell 元字符；
- 提供“恢复自动网络 + 解锁频段/基站 + 恢复 APN”的本机紧急按钮。

## 需要实机确认的清单

1. F50 普通 APK、ADB shell、Shizuku shell、Root 四种身份各自的 `id`、SELinux context 和 vendor Binder 调用结果。
2. 从目标固件原厂 Web 前端/实际请求确定 Router `80` 的每个写入 `goformId`，而不是从其他 ZTE 型号照搬。
3. 从当前安装的 UFI-TOOLS 版本确认 `2333` 的 API path、鉴权、签名、请求体和回滚命令。
4. 只读枚举展锐网络模式、Band/Cell 当前值；确认“恢复自动/解除锁定”后才进行第一次写入。
5. DNS 分别验证：Android 本机、USB/RNDIS 客户端、Wi-Fi 热点客户端；三者不能用一次 `getprop` 或本机 `nslookup` 互相代替。
6. 踢设备验证应使用自己控制的测试客户端，并确认是否只是瞬时断开、是否能自动重连，以及黑名单是否跨重启保留。

## 最终建议

Android Agent 可以演进成设备控制代理，但产品边界应是：**普通 APK 做编排和安全面，Router/UFI/Shizuku/Root 作为可插拔执行后端**。近期最高性价比是先接 Router `80` / UFI `2333` 已存在的固定动作，并加入状态回读与自动回滚；不要一开始就 Root 化，也不要把任意 shell/AT 暴露到 `8787`。
