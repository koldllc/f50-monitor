# 中兴 F50 / 飞猫 U20 开启 ADB、改串与刷机全指南 🛠️

本指南整理自社区开源项目及极客玩机经验（参考 [Daniel-Hwang/U20-F50](https://github.com/Daniel-Hwang/U20-F50) 与 [很多无尾熊 - 肥猫小助手](https://www.cnblogs.com/gnz48/p/19433970)），旨在为中兴 (ZTE) F50 / V50 / U30 / M3 及飞猫 (Flymodem) U20 系列随身 WiFi 用户提供清晰、安全、易懂的 ADB 开启、改串 (IMEI)、全量备份、Bootloader 解锁、固件刷机与救砖操作指引。

> [!CAUTION]
> **免责声明**：刷机、解锁 Bootloader 及修改底层参数存在一定风险，操作不当可能导致设备变砖、失去保修或基带信号丢失。请务必在操作前**完整备份全部分区**，并严格遵守国家相关无线电与通信终端管理法规。

---

## 📑 目录

- [一、必备工具与运行环境下载](#一必备工具与运行环境下载)
- [二、开启 ADB 调试模式](#二开启-adb-调试模式)
  - [2.1 中兴原生设备（F50 / V50 / U30 / M3 等）](#21-中兴原生设备f50--v50--u30--m3-等)
  - [2.2 飞猫 U20 设备（Web 签名脚本法）](#22-飞猫-u20-设备web-签名脚本法)
- [三、投屏与工程模式改串 (IMEI)](#三投屏与工程模式改串-imei)
- [四、完整备份与底层刷机全流程](#四完整备份与底层刷机全流程)
  - [4.1 第一步：全分区备份（强力推荐）](#41-第一步全分区备份强力推荐)
  - [4.2 第二步：刷入工程 U-Boot](#42-第二步刷入工程-u-boot)
  - [4.3 第三步：解锁 Bootloader 与 Fastboot](#43-第三步解锁-bootloader-与-fastboot)
  - [4.4 第四步：固件还原与系统互刷](#44-第四步固件还原与系统互刷)
  - [4.5 ⚠️ 核心保护：禁止刷入/分享的私有基带分区](#45-️-核心保护禁止刷入分享的私有基带分区)
- [五、各机型固件版本推荐与实用技巧](#五各机型固件版本推荐与实用技巧)
- [六、常见故障排查与救砖指南 (FAQ)](#六常见故障排查与救砖指南-faq)

---

## 一、必备工具与运行环境下载

在进行任何玩机操作前，请先准备好以下工具和运行库（主要适用于 Windows 环境）：

### 1. 核心工具与固件资源
- **肥猫小助手（全功能集成工具箱）**：[123 网盘下载](https://www.123865.com/s/cNeKVv-Z9Yo3)
- **Daniel-Hwang 极客工具包**：[GitHub 仓库 (Daniel-Hwang/U20-F50)](https://github.com/Daniel-Hwang/U20-F50)
- **投屏工具**：[QtScrcpy](https://github.com/barry-ran/QtScrcpy) 或 [scrcpy](https://github.com/Genymobile/scrcpy)
- **提取组件**：紫光展锐电话拨号 APK、中兴短信收发客户端 APK（可在上述仓库中获取）

### 2. Windows 必备运行库与驱动
- 微软常用运行库合集：[蓝奏云下载](https://wwvv.lanzout.com/ilTPP3caa4yj)
- .NET 8.0 运行时环境：[蓝奏云下载](https://wwvv.lanzout.com/i7EiH3caaete)
- 紫光展锐/高通通用安卓驱动集：[蓝奏云下载](https://wwvv.lanzout.com/iFQc83caag6d)

---

## 二、开启 ADB 调试模式

开启 ADB 后，不仅可以通过桌面端进行状态控制，[**F50 Monitor**](../README.md) 也可通过 5555 端口原生读取 CPU 负载、内存、芯片温度及 QCI 签约速率。

### 2.1 中兴原生设备（F50 / V50 / U30 / M3 等）

中兴官方 Web 后台内置了隐藏的调试开关，通过 URL Hash 即可直接调出：

1. 电脑连接设备 Wi-Fi 或通过 USB 数据线直连电脑。
2. 浏览器打开官方管理后台（默认地址一般为 `http://192.168.0.1`），输入密码登录。
3. 在**同一浏览器**中新建标签页，访问以下地址：
   ```text
   http://192.168.0.1/index.html#usb_port
   ```
4. 在页面中将 **USB 调试模式** 设置为开启，点击 **应用** 并确认重启。
5. （可选）若需开启极致性能模式，可在同浏览器访问：
   ```text
   http://192.168.0.1/index.html#performance_mode
   ```

### 2.2 飞猫 U20 设备（Web 签名脚本法）

飞猫 U20 后台未开放 `#usb_port` 页面，需通过计算 SHA256 签名向后台 `goform` 接口提交开关指令：

#### 方法 A：PowerShell 一键开启（推荐）
1. 电脑连上飞猫 U20（默认网关为 `192.168.88.1`），并在浏览器中登录后台。
2. 在 Windows 上打开 **PowerShell**，粘贴并运行以下脚本：

```powershell
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36"

# 1. 获取版本标识并计算密钥
$s = Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.88.1/goform/goform_get_cmd_process?isTest=false&cmd=Language%2Ccr_version%2Cwa_inner_version&multi_data=1" -WebSession $session -Headers @{
  "Accept"="application/json, text/javascript, */*; q=0.01"
  "Referer"="http://192.168.88.1/index.html"
  "X-Requested-With"="XMLHttpRequest"
}
$vs = $s.Content | ConvertFrom-Json
$ss = $vs.wa_inner_version + $vs.cr_version
$sha256 = New-Object System.Security.Cryptography.SHA256CryptoServiceProvider
$key = ([System.BitConverter]::ToString($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ss)))).Replace("-", "")

# 2. 获取 RD 校验码
Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.88.1/goform/goform_get_cmd_process?isTest=false&cmd=RD" -WebSession $session -Headers @{
  "Accept"="application/json, text/javascript, */*; q=0.01"
  "Referer"="http://192.168.88.1/index.html"
  "X-Requested-With"="XMLHttpRequest"
}

# 3. 混合签名并下发开启 ADB 命令
$ck = $session.Cookies.GetCookies("http://192.168.88.1/goform")["JSESSIONID"].Value
$hash = ([System.BitConverter]::ToString($sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($key + $ck)))).Replace("-", "")
$body = "isTest=false&goformId=USB_PORT_SETTING&usb_port_switch=1&AD=" + $hash

Invoke-WebRequest -UseBasicParsing -Uri "http://192.168.88.1/goform/goform_set_cmd_process" -Method "POST" -WebSession $session -Headers @{
  "Accept"="application/json, text/javascript, */*; q=0.01"
  "Origin"="http://192.168.88.1"
  "Referer"="http://192.168.88.1/index.html"
  "X-Requested-With"="XMLHttpRequest"
} -ContentType "application/x-www-form-urlencoded; charset=UTF-8" -Body $body

Write-Host "✅ 飞猫 U20 ADB 开启指令已发送！"
```

#### 方法 B：批处理工具一键执行
直接下载 Daniel-Hwang 仓库中的 `u20一键打开adb并安装.zip`，解压后双击运行 `开启adb.bat` 即可全自动完成开启与辅助 APK 安装。

---

## 三、投屏与工程模式改串 (IMEI)

通过紫光展锐 (Unisoc) 原厂工程模式，可免 Root 直接向 Modem 发送 AT 指令修改 IMEI：

1. **投屏连接设备**：
   - 确保设备已开 ADB，使用 USB 连接电脑后启动 `QtScrcpy` 或 `scrcpy`，点击连接投屏进入 Android 桌面。
2. **打开拨号键盘**：
   - 打开系统中的“电话 / 拨号”应用（若无拨号应用，可先通过 ADB 安装 `F50-u20电话拨号.apk`：`adb install F50-u20电话拨号.apk`）。
3. **进入紫光展锐工程模式**：
   - 在拨号盘输入暗码：
     ```text
     *#*#83781#*#*
     ```
   - 系统将自动跳转至 **EngineerMode**（工程模式）界面。
4. **发送 AT 指令改串**：
   - 点击顶部导航标签栏的 **DEBUG&LOG**。
   - 找到并点击 **Send AT Command** 选项。
   - 在 **AT Command:** 输入框中输入（注意英文字符及双引号）：
     ```text
     AT+SPIMEI=0,"你的15位新IMEI"
     ```
     > 💡 说明：`0` 表示卡槽 1（主卡），`1` 表示卡槽 2。
   - 点击 **SEND** 按钮。若下方输出显示 **`OK`**，即表示修改成功。
5. **重启验证**：
   - 重启随身 WiFi，重新登录 Web 管理后台或在工程模式中查看 IMEI 是否已成功更新。

---

## 四、完整备份与底层刷机全流程

紫光展锐平台基于 `spd_dump` 工具链进行底层的下载与分区读写。

### 4.1 第一步：全分区备份（强力推荐）

在改动任何分区之前，**必须**完整备份原厂全部分区（约 73 个镜像文件）：

```bat
:: 执行 1_backup_first.bat
adb wait-for-device
adb reboot autodloader
spd_dump --wait 300 exec_addr 0x65012f48 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0xb4fffe00 exec path backup_dir r splloader read_parts partition1.xml reset
```

### 4.2 第二步：刷入工程 U-Boot

工程 U-Boot（`engineering-uboot_signed.bin`）能够解除官方 U-Boot 对 Fastboot 的限制：

```bat
:: 执行 2_flash_factory_uboot.bat
adb wait-for-device
adb reboot autodloader
spd_dump --wait 300 exec_addr 0x65012f48 fdl fdl1-dl.bin 0x65000800 fdl fdl2-dl.bin 0xb4fffe00 exec w uboot engineering-uboot_signed.bin reset
```

### 4.3 第三步：解锁 Bootloader 与 Fastboot

刷入工程 U-Boot 后，即可正常重启进入 Fastboot 模式：

```bash
adb reboot bootloader
fastboot devices
# 解锁 bootloader（或运行一步解锁批处理工具）
fastboot flashing unlock
```

### 4.4 第四步：固件还原与系统互刷

可使用 **肥猫小助手** 的【7 还原系统备份】功能将中兴官方固件（如 F50 B09）解压至 `flash` 目录直接刷入飞猫 U20 或 F50。

固件包标准目录结构建议：
```text
ZTE-F50_FLYMODEM_ZYV1.0.0B09/          # 固件包根目录
├── flash/                            # 镜像文件目录（必须命名为 flash）
│   ├── boot_a.bin
│   ├── boot_b.bin
│   ├── system.bin
│   └── ...                           # 其余系统分区镜像
└── explain.txt                       # 固件说明文件（UTF-8 编码）
```

> 💡 **打包提示**：建议使用 7-Zip 将上述结构压缩为 `.7z`，并将文件后缀更名为 `.kkbin`（助手通用固件格式）。

---

### 4.5 ⚠️ 核心保护：禁止刷入/分享的私有基带分区

向他人分享固件或刷入来源未知的全量备份包时，**务必删除以下分区文件**，避免基带校验损坏或串号被覆盖：

| 分区文件名 | 分区类型 | 常见大小 | 分区存储的关键数据与风险说明 |
| :--- | :--- | :--- | :--- |
| **`nr_*` (如 `nr_fixnv`)** | RAW | ~14.7 MB | **蜂窝 Modem 核心参数**：包含 GSM/LTE/5G NR 射频校准、SIMLOCK、原机 IMEI/MEID。**刷错会导致无基带、无信号**！ |
| **`prodnv`** | FS (EXT4) | ~64 MB | **外设校准数据**：Wi-Fi / 蓝牙真实 MAC 地址、TSX 晶振校准、LCD PQ 参数等。 |
| **`miscdata`** | RAW | ~1 MB | **设备元数据**：原厂 SN 序列号、站位检测 (PhaseCheck)、出厂自定义数据。 |

---

## 五、各机型固件版本推荐与实用技巧

### 1. 社区公认稳定固件版本
- **中兴 F50 / 飞猫 U20**：推荐 **B09**（功能最全、功耗与发热平衡极佳，避免 B13 部分工具兼容性收紧）
- **中兴 U30 普通版**：推荐 **B17**
- **中兴 U30 亚太版**：推荐 **B14**
- **中兴 U30 全球版**：推荐 **B11**
- **中兴 M3**：推荐 **B05 / B07**

> ⚠️ **强烈建议**：刷好系统后，请在 Web 后台中**关闭系统自动更新 (OTA)**，避免自动升至高版本导致 ADB 开关或扩展接口失效。

### 2. 肥猫小助手内置快捷按键
在肥猫小助手主控制台输入以下指令可快速调出对应工具：
- `[ H ]`：打开飞猫助手官方帮助文档
- `[ AA ]`：打开 CMD 常用命令速查
- `[ DD ]`：一键杀死并重新启动 ADB 服务进程
- `[ HH ]`：打开 SPD 指令集帮助文档
- `[ 33 ]`：调出 iPerf3 网络性能测速工具（测带宽/延迟/丢包）
- `[ 55 ]`：启动带有调试信息的 Scrcpy 投屏窗口
- `[ 88 ]`：快速打开 UFI 高级管理后台（2333 端口）

---

## 六、常见故障排查与救砖指南 (FAQ)

### Q1: 飞猫 U20 刷完中兴 F50 固件后一直反复重启，无法进入系统？
- **原因**：刷入 F50 固件后首次开机会自动执行一次恢复出厂设置流程，此时瞬时功耗较高。如果插在电脑 USB 口或低功率充电头（如 5V/1A）供电，会导致供电不足掉电重启。
- **解决办法**：
  1. 将设备插入支持 **5V/2A 或 9V/2A 以上的大功率充电头**。
  2. 设备会继续反复重启若干次，直到正面 **两颗 LED 指示灯均呈现白色常亮** 状态。
  3. 此时使用卡针轻按一下设备侧面的 **RESET** 复位孔（若未立即响应则按住约 2 秒）。
  4. 设备将自动重启并成功初始化进入 F50 系统。

---

### Q2: 肥猫小助手窗口无法拖入固件包？
- **原因**：Windows 11 / Windows Terminal 的 UAC 提权限制阻止了跨权限窗口拖拽。
- **解决办法**：
  1. 将固件文件拖拽到窗口**左上角区域**，待光标出现“粘贴文件路径”提示后再松开鼠标。
  2. 或在文件管理器中右键“复制文件路径”，在小助手控制台界面直接**右键点击**粘贴。

---

### Q3: 刷机后提示 ADB 无法连接或端口被占用？
1. 检查电脑设备管理器中是否正确安装了紫光展锐 ADB 驱动（带有 Android Composite ADB Interface 标识）。
2. 在命令行中执行 `adb kill-server && adb devices`，或在肥猫小助手中输入 `DD` 重启 ADB 守护进程。
3. 确保随身 WiFi 处于开机完全就绪状态（Wi-Fi 广播已正常发出）。

---

> 📖 **回到项目首页**：[返回 F50 Monitor README](../README.md)
