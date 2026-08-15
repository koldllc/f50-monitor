import AppKit
import F50Core
import SwiftUI

private enum CarrierLogoAssets {
    private static let images: [String: NSImage] = {
        let sourceDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let names = [
            "ChinaMobileLogo",
            "ChinaUnicomLogo",
            "ChinaTelecomLogo",
            "ChinaBroadnetLogo"
        ]

        return Dictionary(uniqueKeysWithValues: names.compactMap { name in
            let extensions = ["svg", "png"]
            let bundleURLs = extensions.compactMap {
                Bundle.main.url(forResource: name, withExtension: $0)
            }
            let sourceURLs = extensions.map {
                sourceDirectory.appendingPathComponent("\(name).\($0)")
            }
            for url in bundleURLs + sourceURLs {
                if let image = NSImage(contentsOf: url) {
                    return (name, image)
                }
            }
            return nil
        })
    }()

    static func image(named name: String) -> NSImage? {
        images[name]
    }
}

public struct F50PanelView: View {
    @ObservedObject var fetcher: F50Fetcher
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var screenMirroringManager: ScreenMirroringManager
    var onOpenSettings: () -> Void
    var onOpenSMS: () -> Void

    init(
        fetcher: F50Fetcher,
        updateManager: UpdateManager,
        screenMirroringManager: ScreenMirroringManager,
        onOpenSettings: @escaping () -> Void,
        onOpenSMS: @escaping () -> Void
    ) {
        self.fetcher = fetcher
        self.updateManager = updateManager
        self.screenMirroringManager = screenMirroringManager
        self.onOpenSettings = onOpenSettings
        self.onOpenSMS = onOpenSMS
    }


    private var subscriptionText: String {
        let qciVal = fetcher.status.qci.trimmingCharacters(in: .whitespaces)
        let dlVal = fetcher.status.qosDl.trimmingCharacters(in: .whitespaces)
        let ulVal = fetcher.status.qosUl.trimmingCharacters(in: .whitespaces)

        if qciVal.isEmpty && dlVal.isEmpty && ulVal.isEmpty {
            return "无数据"
        }

        var parts: [String] = []
        if !qciVal.isEmpty {
            parts.append("QCI：\(qciVal)")
        } else {
            parts.append("QCI：-")
        }

        if !dlVal.isEmpty {
            parts.append("⬇️ \(dlVal)")
        }
        if !ulVal.isEmpty {
            parts.append("⬆️ \(ulVal)")
        }

        return parts.joined(separator: "  ")
    }

    private var carrierLogoAssetName: String? {
        let carrier = fetcher.status.carrier.lowercased()

        if carrier.contains("移动") || carrier.contains("mobile") {
            return "ChinaMobileLogo"
        }
        if carrier.contains("联通") || carrier.contains("unicom") {
            return "ChinaUnicomLogo"
        }
        if carrier.contains("电信") || carrier.contains("telecom") {
            return "ChinaTelecomLogo"
        }
        if carrier.contains("广电") || carrier.contains("broadcast") {
            return "ChinaBroadnetLogo"
        }
        return nil
    }

    @ViewBuilder
    private var carrierLogoView: some View {
        if let assetName = carrierLogoAssetName,
           let image = CarrierLogoAssets.image(named: assetName) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "simcard.fill")
                .foregroundColor(.secondary)
        }
    }

    public var body: some View {
        VStack(spacing: 10) {
            // Header: Model & Connection Status
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(F50Theme.blue)
                    Text("F50 Monitor")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                }

                Spacer()

                // Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(fetcher.status.isOnline ? F50Theme.green : F50Theme.red)
                        .frame(width: 7, height: 7)
                    Text(fetcher.status.isOnline ? "在线" : "未在线")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(fetcher.status.isOnline ? F50Theme.green : F50Theme.red)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill((fetcher.status.isOnline ? F50Theme.green : F50Theme.red).opacity(0.12)))

                if updateManager.availableVersion != nil {
                    Button(action: updateManager.installAvailableUpdate) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(F50Theme.green)
                    }
                    .buttonStyle(.borderless)
                    .help(updateManager.statusText)
                }

                Button(action: {
                    fetcher.fetchData()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("立即刷新")
            }
            .padding(.horizontal, 4)

            if !fetcher.status.isOnline {
                // Error Alert Box
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(F50Theme.orange)
                        Text(fetcher.status.errorMessage ?? "无法连接到 F50 后台")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    Text("请在设置中检查管理密码及 IP 地址")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(F50Theme.orange.opacity(0.12)))
            }

            // 1. Network & 3 Signal Metrics Card
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        if !fetcher.status.carrier.isEmpty && fetcher.status.carrier != "未知" {
                            HStack(spacing: 4) {
                                carrierLogoView
                                Text(fetcher.status.carrier)
                            }
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        }

                        Text(fetcher.status.networkType)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(F50Theme.blue.opacity(0.12)))
                            .foregroundColor(F50Theme.blue)

                        if !fetcher.status.currentBands.isEmpty {
                            Text(fetcher.status.currentBands)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(F50Theme.purple.opacity(0.12)))
                                .foregroundColor(F50Theme.purple)
                        }
                    }

                    Spacer()

                    // Signal Bar Indicators (Bottom-aligned)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(1...5, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(bar <= fetcher.status.signalBar ? F50Theme.green : Color.primary.opacity(0.12))
                                .frame(width: 4, height: CGFloat(Double(bar) * 2.8 + 4))
                        }
                    }
                }
                .padding(.top, 4)
                .padding(.horizontal, 4)

                // Subscription Status / QCI Line
                HStack(spacing: 6) {
                    Text("签约状态:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    let subText = subscriptionText
                    Text(subText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(subText == "无数据" ? .secondary : .primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(F50Theme.blue.opacity(0.06)))

                Divider()

                // 3 Signal Values & Status Bars (Ordered: RSRP, SINR/SNR, RSRQ)
                HStack(spacing: 8) {
                    // Column 1: RSRP
                    VStack(spacing: 4) {
                        Text("RSRP")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(fetcher.status.rsrp)
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())

                        // Status Bar & Tag
                        let q = fetcher.status.rsrpQuality
                        VStack(spacing: 2) {
                            ProgressView(value: q.ratio, total: 1.0)
                                .tint(q.color)
                                .scaleEffect(x: 1, y: 0.7, anchor: .center)
                            Text(q.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(q.color)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 36)

                    // Column 2: SINR / SNR
                    VStack(spacing: 4) {
                        Text("SINR / SNR")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(fetcher.status.snr)
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())

                        // Status Bar & Tag
                        let q = fetcher.status.snrQuality
                        VStack(spacing: 2) {
                            ProgressView(value: q.ratio, total: 1.0)
                                .tint(q.color)
                                .scaleEffect(x: 1, y: 0.7, anchor: .center)
                            Text(q.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(q.color)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 36)

                    // Column 3: RSRQ
                    VStack(spacing: 4) {
                        Text("RSRQ")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(fetcher.status.rsrq)
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())

                        // Status Bar & Tag
                        let q = fetcher.status.rsrqQuality
                        VStack(spacing: 2) {
                            ProgressView(value: q.ratio, total: 1.0)
                                .tint(q.color)
                                .scaleEffect(x: 1, y: 0.7, anchor: .center)
                            Text(q.label)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(q.color)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))

            // 2. Speeds Card
            HStack(spacing: 12) {
                // Download Speed
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(F50Theme.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时下载")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatSpeed(fetcher.status.dlSpeed))
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(F50Theme.green)
                    }
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(F50Theme.green.opacity(0.08)))

                // Upload Speed
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(F50Theme.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时上传")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatSpeed(fetcher.status.ulSpeed))
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(F50Theme.blue)
                    }
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(F50Theme.blue.opacity(0.08)))
            }

            // 3. Traffic Statistics Card
            VStack(spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(F50Theme.cyan)
                        Text("套餐流量")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 百分比与重置天数已移至进度条下方（trafficLimit > 0 时）
                    if fetcher.status.trafficLimit <= 0 {
                        HStack(spacing: 6) {
                            let packageUsed = fetcher.status.packageTotal > 0
                                ? fetcher.status.packageTotal
                                : fetcher.status.monthlyTotal
                            Text("已用流量：\(F50Status.formatBytes(packageUsed))")
                                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundColor(.primary)
                            if let days = fetcher.status.daysUntilReset {
                                Text(days == 0 ? "(今天重置)" : "(\(days)天后重置)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if fetcher.status.trafficLimit > 0 {
                    VStack(spacing: 4) {
                        HStack {
                            let packageUsed = fetcher.status.packageTotal > 0
                                ? fetcher.status.packageTotal
                                : fetcher.status.monthlyTotal
                            Text("已用流量：\(F50Status.formatBytes(packageUsed))")
                            Spacer()
                            Text("总流量：\(F50Status.formatBytes(fetcher.status.trafficLimit))")
                        }
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())

                        ProgressView(value: fetcher.status.trafficUsageRatio, total: 1.0)
                            .tint(fetcher.status.trafficUsageColor)
                            .scaleEffect(x: 1, y: 0.8, anchor: .center)

                        // 进度条下方一行：左侧套餐已用比例，右侧重置天数提醒
                        HStack(spacing: 6) {
                            Text(String(format: "%.0f%%", fetcher.status.trafficUsageRatio * 100))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(fetcher.status.trafficUsageColor.opacity(0.15)))
                                .foregroundColor(fetcher.status.trafficUsageColor)
                            Spacer()
                            if let days = fetcher.status.daysUntilReset {
                                Text(days == 0 ? "今天重置" : "\(days)天后重置")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Divider()

                // 2 Metrics Columns: 当日流量, 本月已用
                HStack(spacing: 8) {
                    // Column 1: 当日流量
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            Image(systemName: "sun.max.fill")
                                .font(.system(size: 11))
                                .foregroundColor(F50Theme.orange)
                            Text("当日流量")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        let daily = fetcher.status.ufiDailyUsage > 0
                            ? fetcher.status.ufiDailyUsage
                            : fetcher.status.dailyTotal
                        Text(F50Status.formatBytes(daily))
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)

                    Divider().frame(height: 28)

                    // Column 2: 本月已用
                    VStack(spacing: 3) {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                                .foregroundColor(F50Theme.purple)
                            Text("本月已用")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        let monthly = fetcher.status.ufiMonthlyUsage > 0
                            ? fetcher.status.ufiMonthlyUsage
                            : fetcher.status.monthlyTotal
                        Text(F50Status.formatBytes(monthly))
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))

            // 3. Hardware Metrics Grid
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    // CPU Usage Metric
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("CPU 占用率")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(fetcher.status.cpuUsage > 0 ? String(format: "%.0f%%", fetcher.status.cpuUsage) : "--")
                                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundColor(fetcher.status.cpuColor)
                        }
                        ProgressView(value: min(100.0, max(0.0, fetcher.status.cpuUsage)), total: 100.0)
                            .tint(fetcher.status.cpuColor)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))

                    // Memory Usage Metric
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("内存 占用率")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(fetcher.status.memUsage > 0 ? String(format: "%.0f%%", fetcher.status.memUsage) : "--")
                                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundColor(fetcher.status.memColor)
                        }
                        ProgressView(value: min(100.0, max(0.0, fetcher.status.memUsage)), total: 100.0)
                            .tint(fetcher.status.memColor)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.03)))
                }

                HStack(spacing: 12) {
                    // Temperature
                    HStack(spacing: 8) {
                        Image(systemName: "thermometer.medium")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(fetcher.status.tempColor)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("芯片温度")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(fetcher.status.temperature > 0 ? String(format: "%.1f ℃", fetcher.status.temperature) : "-- ℃")
                                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundColor(fetcher.status.tempColor)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(fetcher.status.tempColor.opacity(0.08)))

                    // Connected Devices (Wi-Fi)
                    HStack(spacing: 8) {
                        Image(systemName: "wifi")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(F50Theme.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Wi-Fi 连接设备")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("\(fetcher.status.connectedDevices) 台")
                                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        }
                        Spacer()
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(F50Theme.purple.opacity(0.08)))
                }
            }

            if screenMirroringManager.isEnabled, let msg = screenMirroringManager.statusMessage, !msg.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: screenMirroringManager.isConnecting ? "arrow.triangle.2.circlepath" : "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(F50Theme.purple)
                    Text(msg)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Spacer()
                    Button(action: { screenMirroringManager.clearStatusMessage() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(F50Theme.purple.opacity(0.1)))
            }

            Divider()

            // 4. Actions
            HStack(spacing: 8) {
                // Open Web Dashboard Button (First!)
                Button(action: {
                    if let url = URL(string: fetcher.baseURLString) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                        Text("打开 Web 后台")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(F50Theme.blue)

                // Screen Mirroring Button (Icon-only, no text, no color tint)
                if screenMirroringManager.isEnabled {
                    Button(action: {
                        if screenMirroringManager.isDependenciesInstalled {
                            screenMirroringManager.startMirroring(baseURLString: fetcher.baseURLString)
                        } else {
                            screenMirroringManager.requestInstallDependencies()
                        }
                    }) {
                        Group {
                            if screenMirroringManager.isConnecting {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "tv")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .padding(6)
                    }
                    .buttonStyle(.bordered)
                    .disabled(screenMirroringManager.isConnecting || !fetcher.status.isOnline)
                    .help(screenMirroringManager.isDependenciesInstalled ? "无线 ADB 投屏" : "未检测到投屏组件，点击配置")
                }

                // SMS Button
                Button(action: onOpenSMS) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "envelope")
                            .font(.system(size: 11, weight: .medium))
                        if fetcher.status.smsUnreadCount > 0 {
                            Text(fetcher.status.smsUnreadCount > 99 ? "99+" : "\(fetcher.status.smsUnreadCount)")
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(F50Theme.red))
                                .offset(x: 9, y: -7)
                        }
                    }
                    .padding(6)
                }
                .buttonStyle(.bordered)
                .help("读取短信")

                // Settings Button
                Button(action: {
                    onOpenSettings()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .medium))
                        .padding(6)
                }
                .buttonStyle(.bordered)
                .help("设置")

                // Quit Button
                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Image(systemName: "power")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(F50Theme.red)
                        .padding(6)
                }
                .buttonStyle(.bordered)
                .help("退出程序")
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .alert("请求下载配置授权", isPresented: $screenMirroringManager.showPermissionAlert) {
            Button("允许并下载") {
                screenMirroringManager.downloadAndInstallStandaloneDependencies()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("无线投屏功能需要依赖官方独立组件包 (scrcpy + ADB)。\n\n点击“允许并下载”将自动在线下载并配置独立组件（无需安装 Homebrew 或终端操作）。")
        }
    }
}


