# 中兴 F50：不借助 UFI/MiniKano 直接调用 AT 的可行性

## 结论

**可行，且 F50 最值得优先验证的路径不是直接打开 modem tty，而是经 ADB shell 调用展锐（Spreadtrum/Unisoc）厂商 Binder 服务。** UFI-TOOLS 的公开源码已经给出了完整调用方式；`/api/AT` 只是把这条本机命令包装成 HTTP，并不是 AT 能力本身。

F50 在 UFI-TOOLS 中被归入“中兴 + 展锐/紫光 Android”设备，因此 Qualcomm QMI/DIAG 路线属于其他 Qualcomm Android 设备的备选研究方向，并非当前 F50 的首选实现。

## 实机验证（2026-08-21）

已在目标 `192.168.0.1:5555` 上通过标准 ADB 完成只读验证：

- 设备：`F50`（product/device：`MU300`）
- Android API：33（Android 13）
- ADB 身份：`uid=2000(shell)`，SELinux：`Permissive`
- Binder 服务：`vendor.sprd.hardware.log.ILogControl/default`
- `AT` 返回：`OK`
- `AT+CGEQOSRDP=1` 返回：`+CGEQOSRDP: 1,8,0,0,0,0,500000,100000`，即 QCI `8`、下行 `500 Mbps`、上行 `100 Mbps`

这证明该设备可以完全绕过 UFI/MiniKano，通过 ADB shell 直接调用展锐 Binder 获取 QCI 与签约速率。首次握手曾因临时 ADB 服务状态异常未完成；使用隔离的 ADB server 重新连接后成功，不是设备能力缺失。

## 路径对比

| 路径 | F50 可行性 | 是否通常需要 root | 说明 |
| --- | --- | --- | --- |
| ADB shell → 展锐 Binder `service call` | **高，首选** | **源码中未使用 root；仍需实机验证 shell 域权限** | UFI-TOOLS 实际采用的底层路径，可直接查询 `AT+CGEQOSRDP=1` |
| ADB shell → `/dev/stty_lte*` 等 modem tty | 中低 | 通常需要 | 节点可能不存在、被 RIL 占用，且受 Unix 权限与 SELinux 双重限制 |
| Qualcomm QMI/QRTR | F50 不适用；Qualcomm 设备可研究 | 通常需要系统/厂商权限 | QMI 是结构化 modem 协议，不是任意 AT 透传 |
| Qualcomm DIAG/QCDM | F50 不适用；Qualcomm 设备可研究 | Android 内部访问通常需要 root，或需厂商方式开放 USB DIAG | DIAG 也不是 AT；可读取专有诊断日志/协议数据 |
| ZTE 原生 80 端口 goform | **未发现任意 AT 透传证据** | 不适用 | `cmd=` 是读取已注册字段，不等于执行 AT；UFI 的 `/api/AT` 是独立接口 |

## 1. F50 的直接路径：展锐 Binder 服务

UFI-TOOLS 的 [`send_at.go`](https://github.com/kanoqwq/UFI-TOOLS/blob/http-server-version/app/src/main/assets/shell/send_at.go) 明确按 Android API 版本执行两套命令：

```sh
# Android 13 及以下（API <= 33）
adb shell service call vendor.sprd.hardware.log.ILogControl/default 1 \
  s16 "miscserver" s16 "sendAt 0 AT+CGEQOSRDP=1"

# Android 14 及以上（API > 33）
adb shell service call vendor.sprd.hardware.tool.IToolControl/default 3 \
  i32 0 s16 "AT+CGEQOSRDP=1"
```

其中 `0` 是卡槽号。AOSP 的 [`service` 命令源码](https://android.googlesource.com/platform/frameworks/native/+/master/cmds/service/service.cpp) 说明 `service call SERVICE CODE ...` 会查找 Binder 服务、写入接口 token 和参数，再发起事务；因此这不是 tty 写入，也不是 QMI/DIAG。

UFI-TOOLS 的 [`atModule.kt`](https://github.com/kanoqwq/UFI-TOOLS/blob/http-server-version/app/src/main/java/com/minikano/f50_sms/modules/at/atModule.kt) 仅把请求转为 `sendat -n <slot> -c <command>`，再由上述 `send_at.go` 调 Binder。其 [`ShellKano.kt`](https://github.com/kanoqwq/UFI-TOOLS/blob/http-server-version/app/src/main/java/com/minikano/f50_sms/utils/ShellKano.kt) 使用普通 `sh -c`，没有 `su`；Manifest 也没有共享 system UID。因此从公开实现看，**该 AT 查询本身不依赖 UFI 的 root shell**。

`service call` 原始输出是 Parcel 十六进制转储。UFI 的解析器会提取每个 8 位十六进制字，按小端 UTF-16 还原文本；直接接入 F50 Monitor 时应在 macOS 端做同样解析，而不必安装 UFI APK。

### 权限边界

ADB 在量产安全构建上通常降权到 `shell` UID 2000；AOSP [`adbd` 源码](https://android.googlesource.com/platform/system/core/+/9d04b677e3473e30c29fee3824405046410a0a37/adb/daemon/main.cpp) 可见其切换到 `AID_SHELL`。能否调用厂商 Binder 服务还取决于 F50 固件的 service-manager/Binder 权限和厂商 SELinux 策略，不能只根据“ADB 可连接”推断成功。

建议先做只读探测：

```sh
adb shell getprop ro.build.version.sdk
adb shell service list | grep -E 'vendor\.sprd\.hardware\.(log|tool)'
adb shell getenforce
# 然后只发送 AT 或 AT+CGEQOSRDP=1，检查返回和 logcat 中的 avc denied
```

若服务存在但事务返回 `Permission denied`、`FAILED_TRANSACTION` 或出现 `avc: denied`，才需要 root、调整 SELinux 策略，或由具有厂商授权上下文的进程代理；**不要先假定必须 root**。

## 2. ADB shell 直接访问 modem tty

ADB shell 不会自动拥有 modem 设备权限。AOSP SELinux 仅给 `shell`/`vendor_shell` 通用 `tty_device` 的读写规则（[`shell.te`](https://android.googlesource.com/platform/system/sepolicy/+/refs/heads/android12-qpr3-release/public/shell.te)、[`vendor_shell.te`](https://android.googlesource.com/platform/system/sepolicy/+/refs/tags/android-vts-14.0_r11/public/vendor_shell.te)）；真正的 modem 节点可能被标为 `radio_device` 或厂商私有类型，而 AOSP [`hal_telephony.te`](https://android.googlesource.com/platform/system/sepolicy/+/c2af2e2ec4c99604966a54121427a85d11fd4367/public/hal_telephony.te) 将 `radio_device` 读写授予 telephony HAL，并未普遍授予 shell。

开源的 [BeaRerM](https://github.com/Luckyji6/BeaRerM) 会为 Unisoc 尝试 `/dev/stty_lte0`、`/dev/stty_lte1`，为 Qualcomm 尝试 `/dev/smd7`、`smd8`、`smd11`、`at_usb0`、`at_mdm0`；但它明确要求 `su`，并指出被 RIL 占用的节点无法打开。该项目对 Unisoc/Qualcomm 的这些路径也只标记为“可能”，并未在 F50 上验证。

因此 tty 路线的前置检查是：节点是否存在、`ls -lZ` 的 owner/group/SELinux label、是否被 RIL 独占，以及发送裸 `AT\r` 是否返回 `OK`。即使传统 Unix 权限允许，SELinux 仍可能拒绝；即使能打开，也不应与 RIL 并发抢占。对 F50，Binder 路径比猜 tty 节点更可靠。

## 3. Qualcomm 设备：QMI/QRTR 与 DIAG

### QMI/QRTR

[libqmi 官方文档](https://mobile-broadband.pages.freedesktop.org/docs/libqmi/api-reference/) 将 QMI 定义为 Qualcomm modem 的结构化服务协议；[libqmi 的 QRTR 支持说明](https://github.com/linux-mobile-broadband/libqmi/blob/main/NEWS) 表明 QMI 可经 Qualcomm IPC Router 访问。它提供 NAS、WDS、QoS 等具体服务；例如公开实现仅有部分 QoS flow/network status 查询。**QMI 不是通用 AT 字符串通道**，所以不能把 `AT+CGEQOSRDP=1` 原样塞进 QMI；需要找到对应 QMI 消息、厂商私有服务，或直接解析 Android Radio HAL 已暴露的数据。

在 Android 上还会遇到 `/dev/cdc-wdm*`、QRTR socket、服务 ACL 和 SELinux 权限问题。若目标只是 F50 的 QCI，转向 Qualcomm QMI 会走错平台。

### DIAG/QCDM

[QCSuper 的 DIAG 协议说明](https://github.com/P1sec/QCSuper/blob/master/docs/The%20Diag%20protocol.md) 指出：旧式 Qualcomm Android 可通过 `/dev/diag`，通常需 root；USB modem/已开放诊断组合则可能出现伪串口。DIAG 使用自己的帧、IOCTL、日志和子系统命令，并不是 AT 透传。[QCSuper README](https://github.com/P1sec/QCSuper) 还说明较新内核常不再提供 `/dev/diag`，往往要 root 后切换 `sys.usb.config=diag,adb`，或使用厂商专用途径开放 USB DIAG。

DIAG 可以通过专有 LTE/NR 日志获得更底层信息，但 QCI/5QI 是否可直接解析取决于日志 ID、modem 版本和解析器支持，工程量和固件耦合都明显高于 F50 的展锐 Binder AT 路径。

## 4. ZTE 原生 goform 是否能透传 AT

目前没有找到 F50 原生 goform 支持“任意 AT 命令”的公开源码或一手文档。公开的 ZTE goform 客户端把 `/goform/goform_get_cmd_process?cmd=...` 用作已注册状态字段查询，把 `/goform/goform_set_cmd_process` 用作固定 `goformId` 动作；例如 [zte-lte-modem](https://github.com/teixeluis/zte-lte-modem) 的实现即如此。

更关键的是，UFI-TOOLS 将两者明确分开：

- [`/api/AT`](https://github.com/kanoqwq/UFI-TOOLS/blob/http-server-version/API_Doc.md) → 本机 `sendat` → 展锐 Binder；
- `/api/goform/...` → 代理设备原生 goform。

因此不能把 UFI 的 `/api/AT` 当成 ZTE 80 端口原生接口。除非从 F50 固件的 Web 二进制/前端资源中找到专用 `goformId` 或隐藏 CGI，并完成只读实测，否则应判定：**原生 goform 没有已知的通用 AT 透传能力**。

## 建议落地顺序

1. 通过现有 ADB 5555 通道执行 `getprop` 与 `service list`。
2. 根据 API Level 调用对应展锐 Binder，只测试 `AT` 和只读的 `AT+CGEQOSRDP=1`。
3. 在 macOS 端解析 Parcel UTF-16 输出，复用现有 QCI/QoS 解析逻辑。
4. Binder 被权限拒绝时，再检查 `id`、`ls -lZ`、`logcat` 的 SELinux 证据；不要直接降级为猜 tty。
5. 仅当 Binder 服务在目标固件中不存在时，才评估 root tty 或固件逆向；QMI/DIAG 不应作为 Unisoc F50 的替代实现。

`AT+CGEQOSRDP` 的标准含义可核对 [ETSI TS 127 007](https://www.etsi.org/deliver/etsi_ts/127000_127099/127007/08.14.00_60/ts_127007v081400p.pdf)：它读取已建立 PDP context 的网络分配 EPS QoS 参数，包括 QCI；该命令在标准中为可选实现，因此服务可达也不保证每个固件/网络都返回数据。
