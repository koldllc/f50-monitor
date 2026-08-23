# F50 Monitor - App Store 提审与审核材料指南 🚀

本指南整理了 **F50 Monitor (iOS 版)** 提交至 Apple App Store 审核时所需的全部元数据、审核备注（Review Notes）、隐私申报与合规问答。

---

## 📌 一、 基本版本与工程信息

- **App 名称 (App Name)**: `F50 Monitor`
- **副标题 (Subtitle)**: `5G随身WiFi状态监控与短信管理` (或 `MiFi Monitor & SMS Manager`)
- **App 类别 (Category)**: `工具 (Utilities)` / `网络 (Networking)`
- **版本号 (Marketing Version)**: `2.3.0`
- **构建版本号 (Build / Current Project Version)**: `9`
- **主 App Bundle Identifier**: `com.kold.f50.monitor.ios`
- **Widget Bundle Identifier**: `com.kold.f50.monitor.ios.widget`
- **App Group**: `group.com.f50.monitor`

---

## 📝 二、 审核备注 (App Review Notes - 必填 & 核心重点)

> 💡 **复制以下中英文对照审核备注填入 App Store Connect 的「审核信息 → 备注（Notes）」栏中**：

### 英文版 (Recommended for Global Reviewers):
```text
Dear Apple Review Team,

F50 Monitor is a companion utility designed for portable 5G Wi-Fi devices (such as ZTE F50 5G MiFi).

[How to Test without Hardware - Demo Mode]:
Since physical portable Wi-Fi hardware may not be available in your review lab, the app includes a fully functional "Demo Mode" with simulated 5G signal, speed fluctuations, traffic usage, and SMS interactions.
1. When launched, if no physical device is detected on Wi-Fi, tap the blue button "进入演示模式（无需物理硬件）" (Enter Demo Mode) on the main Status page.
2. Alternatively, go to the "设置" (Settings) tab and switch on "开启演示模式 (Demo Mode)".
3. You will be able to test and review the 5G signal gauge, real-time speed charts, data plan usage progress, SMS list, verification code extraction, and diagnostic feedback UI. Submitting feedback in Demo Mode is simulated locally and sends no data.

[Local Network & ATS Explanation]:
- Local Network Permission (NSLocalNetworkUsageDescription): Used strictly to discover and connect directly to the user's portable Wi-Fi gateway (default 192.168.0.1) and native ADB port (5555) via point-to-point sockets to read signal and throughput metrics.
- App Transport Security (ATS): The app permits cleartext connections only to local-network device hosts. Public endpoints remain subject to ATS; no cleartext credentials are sent to public servers.

[Privacy & Feedback]:
- Diagnostic feedback is only submitted if the user explicitly triggers it via Settings -> 问题反馈与设备适配.
- Gateway diagnostic fields are filtered or masked on-device before transmission. An optional screenshot is uploaded as selected by the user and may contain visible information; the UI warns users not to include sensitive content.

Thank you for your review!
```

### 中文备用版:
```text
尊敬的苹果审核团队：

F50 Monitor 是专为 5G 随身 WiFi（如中兴 F50 等设备）打造的本地状态监控与短信管理工具。

【无硬件环境审核测试方法 - 演示模式】：
考虑到审核实验室可能未配备该随身 WiFi 物理硬件，应用内已深度内置“演示模式 (Demo Mode)”：
1. 启动应用后，在首屏“状态”页直接点击“进入演示模式（无需物理硬件）”蓝色按钮；
2. 或在“设置”页中开启“开启演示模式 (Demo Mode)”开关；
3. 即可体验 5G SA 信号仪表盘、实时速率波动波形、套餐用量进度、短信读取、验证码自动识别提取、模拟短信发送及反馈界面；演示模式中的反馈提交仅在本地模拟，不发送任何数据。

【权限与网络说明】：
- 本地网络权限 (NSLocalNetworkUsageDescription)：仅用于用户主动连接 F50 随身 WiFi 网关 (192.168.0.1) 及 5555 端口原生 Socket 读取信号与状态。
- ATS 与 HTTP 说明：因随身 WiFi 设备管理页面仅支持局域网 HTTP，App 仅为本地网络设备放行明文连接；公网连接仍受 ATS 保护，不涉及公网明文传输。
- 诊断反馈：仅在用户于设置中主动发起反馈时上传网关响应中已脱敏的兼容性数据；用户选取的截图会按原样上传，界面会提示不要包含敏感内容。

感谢您的审核！
```

---

## 🔒 三、 App 隐私问卷 (App Privacy Nutrition Label) 填写指引

在 App Store Connect 的“App 隐私”问卷中，如实按以下指引勾选：

1. **是否收集数据？** 选 **“是，我们从此 App 中收集数据”**（因包含主动反馈通道）。
2. **收集的数据类型 (Data Types)**：
   - **诊断数据 (Diagnostics)**：
     - 勾选 **其他诊断数据 (Other Diagnostic Data)**
     - 用途：**App 功能 (App Functionality)**
     - 是否与用户身份关联：**是 (Linked to User)**（提交联系方式时会与同次反馈关联）
     - 是否用于追踪：**否 (Not Used for Tracking)**
     - 该项覆盖设备型号、系统/应用版本、信号、频段、流量、连接状态及脱敏后的运行日志。
   - **联系信息 (Contact Info)**：
     - 勾选 **电子邮件地址 (Email Address)** 与 **其他用户联系信息 (Other User Contact Info)**（微信、QQ、GitHub ID 等）
     - 用途：**App 功能 (App Functionality)**
     - 是否与用户身份关联：**是 (Linked to User)**
     - 是否用于追踪：**否 (Not Used for Tracking)**
   - **用户内容 (User Content)**：
     - 勾选 **照片或视频 (Photos or Videos)**（可选截图）与 **其他用户内容 (Other User Content)**（问题描述）
     - 用途：**App 功能 (App Functionality)**；与用户身份关联：**是**；不用于追踪。
3. **数据追踪 (Tracking)**：
   - 选 **“否，我们不会将数据用于追踪目的”**。

---

## 🌐 四、 相关 URL 准备

- **隐私政策网址 (Privacy Policy URL)**:
  `https://github.com/koldllc/f50-monitor/blob/main/docs/PRIVACY_POLICY.md`
  *(或部署至自定义域名如 `https://koldllc.com/privacy-policy-f50-monitor`)*
- **支持网址 (Support URL)**:
  `https://github.com/koldllc/f50-monitor/issues`
- **营销网址 (Marketing URL, 选填)**:
  `https://github.com/koldllc/f50-monitor`

---

## 🛡️ 五、 出口合规证明 (Export Compliance)

- **应用是否使用加密？** 选 **“是”**。
- **是否符合加密豁免条款？** 选 **“是 (Yes, Exempt)”**。
  *(应用仅使用系统标准加密 API 如 HTTPS/TLS 与本地 Keychain 存储，符合苹果标准加密豁免。Info.plist 中已配置 `ITSAppUsesNonExemptEncryption = false`)*。

---

## 🔞 六、 年龄分级 (Age Rating)

- 所有内容（暴力、色情、赌博、医疗、恐怖等）均勾选 **“无 / 否”**。
- 最终评级为：**4+ (适合所有年龄段)**。
