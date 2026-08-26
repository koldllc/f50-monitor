# iOS App 内嵌网络测速：公共节点可用性研究

> 调研日期：2026-08-24。仅依据服务方官方文档、官方源码与条款。这里的“可用”同时考虑技术可接入与服务授权；开源客户端许可证不等于公共服务器的长期使用许可。

## 结论

若 F50 iOS App 需要用户手动触发的公网测速，**M-Lab NDT7 是目前授权边界最清晰的公共基础设施**。它明确允许第三方、闭源和商业客户端，但商业 App 必须联系 M-Lab 以赞助或实物贡献方式支持平台，并接受测试数据（含公网 IP）永久公开。

若无法接受该隐私边界，推荐 **自建 LibreSpeed**。Cloudflare 的公共端点适合原型或备用，但官方没有给原生 iOS 第三方 App 长期依赖公共端点的明确 SLA/服务授权。**Ookla 不应私接**，第三方 App 集成需购买 SDK/Custom 等商业授权。

| 方案 | 第三方 App 直接使用 | 费用 | 生产建议 |
| --- | --- | --- | --- |
| M-Lab NDT7 | **明确允许**；商业 App 需贡献平台 | 无 API Key；贡献方式需联系确认 | 公共节点首选，但必须知情同意、隐私披露与容错 |
| Cloudflare Speed Test | 官方 JS 包默认直连公共端点；原生重实现及长期服务承诺不明确 | 未公布端点费用或配额 | 仅作备用，发布前向 Cloudflare 确认用途 |
| LibreSpeed 公共实例 | 软件可商用；每个公共节点的带宽授权并不随开源许可证自动获得 | 软件免费，节点由各运营者承担 | 不依赖志愿节点；自建或逐个获授权 |
| Ookla | 消费服务禁止商业/自动化滥用；嵌入须商业授权 | 报价制 | 只有签约 SDK/Speedtest Powered 才可用 |

## 1. M-Lab NDT7：公共节点首选

### 许可与费用

- [M-Lab Developer Resources](https://www.measurementlab.net/develop/) 明确允许把测量客户端集成到任意应用，并允许商业、闭源客户端；NDT 无需 API Key。
- 现行 [Acceptable Use Policy](https://www.measurementlab.net/aup/)（2025-07-15 更新）新增要求：商业应用的集成开发者必须通过资金赞助或实物贡献支持平台，并联系 `hello@measurementlab.net`；M-Lab 也保留以后调整限额、要求注册或收费的权利。
- 互动用户不得超过 **40 次/天**；自动软硬件客户端建议不超过 **4 次/天**，且应随机分散测试时间。

### 协议与 iOS 接入

1. 调用 [Locate API v2](https://www.measurementlab.net/develop/locate-v2/)：`https://locate.measurementlab.net/v2/nearest/ndt/ndt7`。
2. 使用返回的完整 URL 和 `access_token`，不要写死节点或删除查询参数。
3. [NDT7 协议](https://github.com/m-lab/ndt-server/blob/main/spec/ndt7-protocol.md) 是 TLS WebSocket 单连接测试：下载、上传路径分别为 `/ndt/v7/download`、`/ndt/v7/upload`，WebSocket 子协议为 `net.measurementlab.ndt.v7`；每个方向通常不超过 10 秒。
4. 官方组织提供 [Swift iOS 参考客户端](https://github.com/m-lab/ndt7-client-ios)（Apache-2.0），但 M-Lab 将其标为 community-supported，且仓库示例较旧；集成前应审计 ATS、并发与现代 Swift 兼容性。

客户端必须识别 Locate 的 `204 No Content`、保留多个候选节点回退，并使用可识别的 `User-Agent`。

### 隐私与稳定性

- [现行隐私政策](https://www.measurementlab.net/privacy/) 明确：测量值、时间、客户端公网 IP 和可能的应用/系统元数据会无限期保存并公开发布；不能为单次测试选择退出公开数据集。
- 测试必须由用户在知情同意后主动发起；第三方客户端必须发布符合 M-Lab 政策及 GDPR 要求的隐私政策。不得向 M-Lab 提交设备标识、套餐、信号指标等额外可关联数据。
- 平台是 **best-effort、工作时间支持**，无正式 SLA；容量不足或限流时可返回 204，也可封禁影响平台健康的集成。

## 2. Cloudflare Speed Test：可调用，但服务边界不够明确

### API 与授权边界

[Cloudflare 官方测速引擎](https://github.com/cloudflare/speedtest) 使用 MIT 许可证，并把下列公共端点设为默认值：

- 下载/延迟：`GET https://speed.cloudflare.com/__down?bytes=<字节数>`（延迟可用 `bytes=0`）
- 上传：`POST https://speed.cloudflare.com/__up`

官方包依赖浏览器 `PerformanceResourceTiming`，并不是原生 Swift SDK。iOS 可以通过 WKWebView 复用官方引擎，或自行用 `URLSession` 实现相同 HTTP 请求和计时；但后者的计时口径需重新校准。

MIT 只明确授权**代码**。官方 README 的默认端点和无 Key 示例说明公共服务面向集成使用，但没有找到承诺“任意原生第三方 App 可长期、批量、商业使用这些端点”的独立条款、配额或 SLA。因此不能把端点存活视为合同保证，商业上线前应取得 Cloudflare 书面确认。

### 隐私、流量与稳定性

- README 明确表示 Cloudflare 会在测试完成时收集测量结果，用于汇总互联网质量洞察；请求本身也会向 Cloudflare 暴露公网 IP。App 应在触发前说明第三方数据接收方，并链接 [Cloudflare 隐私政策](https://www.cloudflare.com/privacypolicy/)。
- 官方默认阶梯包含最高 250 MB 下载请求，多轮请求可能消耗大量蜂窝流量；产品应展示流量提示、允许取消，并降低默认档位。
- 公共 TURN 丢包服务已弃用；丢包测试需自备 TURN。官方还把部分配置标记为 experimental，可在补丁版本变更。
- 未公布 API Key、费用、流量配额或公共测速端点 SLA；应实现超时、取消和替代方案。

## 3. LibreSpeed：代码自由，公共节点不是公共资源承诺

### 协议与部署

[LibreSpeed 官方仓库](https://github.com/librespeed/speedtest) 的测速协议是普通 HTTP/XHR：

- 下载：`garbage.php`
- 上传与 ping/jitter：`empty.php`
- 可选 IP/ISP：`getIP.php`
- 多节点通过 JSON 配置 `server`、`dlURL`、`ulURL`、`pingURL`、`getIpURL`

项目按 LGPLv3 发布，可用于商业 App，但修改 LibreSpeed 库本身时需遵守 LGPL 的再发布义务。官方提供 Docker 后端，自建时软件免费，服务器和出口带宽自付。

### 公共实例的限制

[官方仓库内的实例列表](https://github.com/librespeed/speedtest/blob/master/docker/test/servers.json) 和 CLI 默认服务器列表包含 LibreSpeed 及第三方赞助节点，但列表的存在不等于所有节点运营者授权另一个 App 持续消耗其带宽。节点可变更、下线、限速或调整隐私政策，也没有统一 SLA。

因此生产方案应二选一：

- 自建至少两个区域节点并自行监控容量；或
- 逐个与节点运营者取得书面许可，服务端下发动态列表并健康检查。

[官方部署文档](https://github.com/librespeed/speedtest/blob/master/doc.md) 表明 telemetry 可选；关闭 telemetry 仍会有 Web 服务器访问日志，`getIP.php` 还会处理客户端 IP。若启用 telemetry，可保存测速结果、IP/ISP 等信息，隐私政策、保留周期和删除方式均由节点运营者负责。

## 4. Ookla：没有可供任意 App 免费复用的公共 API

- [Speedtest 消费服务条款](https://www.speedtest.net/about/terms) 限制为个人、非商业使用，并禁止未经许可抓取、提取、逆向或把服务用于商业目的。不能通过逆向网站/官方 App 接口或抓取服务器列表绕过授权。
- 官方 [`@ookla/speedtest-js-sdk`](https://www.npmjs.com/package/@ookla/speedtest-js-sdk) 明确要求购买许可证；签约后可测试 Ookla 公共服务器网络或私有服务器，并取得下载、上传、延迟、抖动、IP、ISP、位置等字段。
- [Speedtest Custom 条款](https://account.speedtestcustom.com/terms-conditions) 也只在付费订阅与有限许可范围内开放。原生 iOS 应询价 Speedtest Powered/Mobile SDK，具体测试量、超额费用、数据保留、DPA 与 SLA 以商业合同为准。

## 对 F50 的建议

1. MVP 采用 **M-Lab NDT7**，仅允许用户手动触发；按钮前明确提示“会消耗流量，公网 IP 与测速结果将由 M-Lab 永久公开”。
2. 发布商业版本前联系 M-Lab 确认贡献方式，并更新 App 隐私政策与 App Store Privacy Nutrition Labels。
3. 若产品不能接受数据公开，改为**自建 LibreSpeed**；不要随机借用公共实例。
4. Cloudflare 仅作为可关闭的备用提供者；Ookla 只在取得商业授权后接入。
5. 无论使用哪家，都由服务端下发 provider 配置，客户端做超时、取消、限频和故障降级，避免把单一公共端点写成不可替换依赖。
