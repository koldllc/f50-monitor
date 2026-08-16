import SwiftUI
import SafariServices
import F50Core

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        config.barCollapsingEnabled = true
        let vc = SFSafariViewController(url: url, configuration: config)
        vc.dismissButtonStyle = .done
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

/// iOS 主状态面板：信号、速度、流量、硬件指标
struct StatusView: View {
    @ObservedObject var fetcher: F50Fetcher
    @State private var webURLToOpen: IdentifiableURL?

    private var status: F50Status { fetcher.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    connectionHeader
                    if !status.isOnline {
                        errorBox
                    }
                    signalCard
                    speedCard
                    trafficCard
                    hardwareCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .refreshable {
                await fetcher.fetchDataAsync()
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("F50 Monitor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            if let url = URL(string: fetcher.ufiURLString) {
                                webURLToOpen = IdentifiableURL(url: url)
                            }
                        } label: {
                            Label("UFI后台（2333端口）", systemImage: "wifi.router")
                        }

                        Button {
                            if let url = URL(string: fetcher.routerURLString) {
                                webURLToOpen = IdentifiableURL(url: url)
                            }
                        } label: {
                            Label("中兴后台（80端口）", systemImage: "network")
                        }
                    } label: {
                        Image(systemName: "safari")
                            .font(.body)
                            .foregroundColor(F50Theme.blue)
                    }
                    .help("打开后台")
                }
            }
            .sheet(item: $webURLToOpen) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - 连接状态头部

    private var connectionHeader: some View {
        HStack {
            HStack(spacing: 8) {
                Circle()
                    .fill(status.isOnline ? F50Theme.green : F50Theme.red)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.isOnline ? "在线" : "未在线")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(status.isOnline ? F50Theme.green : F50Theme.red)
                    Text("更新于 \(status.lastUpdated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button {
                fetcher.fetchData()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2.bold())
                    Text("立即刷新")
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
                .foregroundColor(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }

    private var errorBox: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundColor(F50Theme.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.errorMessage ?? "无法连接到 F50 后台")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(.primary)
                Text("请在设置中检查管理密码及 IP 地址，并确认已连接 F50 Wi-Fi")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(F50Theme.orange.opacity(0.1)))
    }

    // MARK: - 信号卡片

    private var signalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if !status.carrier.isEmpty && status.carrier != "未知" {
                    HStack(spacing: 5) {
                        carrierLogoView
                        Text(status.carrier)
                    }
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                }

                Text(status.networkType)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(F50Theme.blue.opacity(0.12)))
                    .foregroundColor(F50Theme.blue)

                if !status.currentBands.isEmpty {
                    Text(status.currentBands)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(F50Theme.purple.opacity(0.12)))
                        .foregroundColor(F50Theme.purple)
                }

                signalBars

                Spacer()
            }

            // 信号指标：RSRP / SINR / RSRQ
            HStack(spacing: 8) {
                signalMetric("RSRP", value: status.rsrp, quality: status.rsrpQuality)
                signalMetric("SINR / SNR", value: status.snr, quality: status.snrQuality)
                signalMetric("RSRQ", value: status.rsrq, quality: status.rsrqQuality)
            }

            // 签约状态（QCI & 上下行速率）
            HStack(spacing: 6) {
                Text("签约状态：")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                let subText = subscriptionText
                Text(subText)
                    .font(.caption.weight(.bold).monospaced())
                    .foregroundColor(subText == "无数据" ? .secondary : .primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(F50Theme.blue.opacity(0.06)))
        }
        .cardContainer()
    }

    @ViewBuilder
    private var carrierLogoView: some View {
        if let assetName = carrierLogoAssetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "simcard.fill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
    }

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...5, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= status.signalBar ? F50Theme.green : Color.primary.opacity(0.15))
                    .frame(width: 3, height: CGFloat(Double(bar) * 2.0 + 3))
            }
        }
        .padding(.leading, 2)
    }

    private var carrierLogoAssetName: String? {
        let carrier = status.carrier.lowercased()
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

    private var subscriptionText: String {
        let qciVal = status.qci.trimmingCharacters(in: .whitespaces)
        let dlVal = status.qosDl.trimmingCharacters(in: .whitespaces)
        let ulVal = status.qosUl.trimmingCharacters(in: .whitespaces)

        if qciVal.isEmpty && dlVal.isEmpty && ulVal.isEmpty {
            return "无数据"
        }

        var parts: [String] = []
        parts.append(qciVal.isEmpty ? "QCI：-" : "QCI：\(qciVal)")
        if !dlVal.isEmpty { parts.append("⬇️ \(dlVal)") }
        if !ulVal.isEmpty { parts.append("⬆️ \(ulVal)") }
        return parts.joined(separator: "  ")
    }

    private func signalMetric(_ title: String, value: String, quality: (label: String, color: Color, ratio: Double)) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
            ProgressView(value: quality.ratio)
                .tint(quality.color)
                .frame(height: 3)
                .padding(.horizontal, 10)
            Text(quality.label)
                .font(.caption2.weight(.bold))
                .foregroundColor(quality.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    // MARK: - 速度卡片

    private var speedCard: some View {
        HStack(spacing: 10) {
            speedColumn("实时下载", speed: status.dlSpeed, color: F50Theme.green, icon: "arrow.down.circle.fill")
            speedColumn("实时上传", speed: status.ulSpeed, color: F50Theme.blue, icon: "arrow.up.circle.fill")
        }
        .cardContainer()
    }

    private func speedColumn(_ title: String, speed: Double, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }
            Text(F50Status.formatSpeed(speed))
                .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    // MARK: - 流量卡片

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                cardHeader("套餐流量", icon: "chart.bar.fill", color: F50Theme.cyan)
                Spacer()
                if status.trafficLimit <= 0, let days = status.daysUntilReset {
                    Text(days == 0 ? "今天重置" : "\(days)天后重置")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundColor(.secondary)
                }
            }

            let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text("已用流量：\(F50Status.formatBytes(packageUsed))")
                        .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    Spacer()
                    if status.trafficLimit > 0 {
                        Text("总流量：\(F50Status.formatBytes(status.trafficLimit))")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }

                if status.trafficLimit > 0 {
                    ProgressView(value: status.trafficUsageRatio)
                        .tint(status.trafficUsageColor)
                    HStack {
                        Text(String(format: "%.0f%%", status.trafficUsageRatio * 100))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(status.trafficUsageColor.opacity(0.15)))
                            .foregroundColor(status.trafficUsageColor)
                        Spacer()
                        if let days = status.daysUntilReset {
                            Text(days == 0 ? "今天重置" : "\(days)天后重置")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            // 当日流量 & 本月已用
            HStack(spacing: 10) {
                usageColumn("当日流量", value: status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal, icon: "sun.max.fill", color: F50Theme.orange)
                usageColumn("本月已用", value: status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal, icon: "calendar", color: F50Theme.purple)
            }
        }
        .cardContainer()
    }

    private func usageColumn(_ title: String, value: UInt64, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }
            Text(F50Status.formatBytes(value))
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    // MARK: - 硬件卡片

    private var hardwareCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader("硬件状态", icon: "cpu.fill", color: F50Theme.purple)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    metricBar("CPU 占用率", value: status.cpuUsage, color: status.cpuColor)
                    metricBar("内存 占用率", value: status.memUsage, color: status.memColor)
                }
                HStack(spacing: 10) {
                    hardwareValue("芯片温度", value: status.temperature > 0 ? String(format: "%.1f ℃", status.temperature) : "-- ℃", color: status.tempColor, icon: "thermometer.medium")
                    hardwareValue("Wi-Fi 连接设备", value: "\(status.connectedDevices) 台", color: F50Theme.purple, icon: "wifi")
                }
            }
        }
        .cardContainer()
    }

    private func metricBar(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
                Text(value > 0 ? String(format: "%.0f%%", value) : "--")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundColor(color)
            }
            ProgressView(value: min(100, max(0, value)), total: 100)
                .tint(color)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    private func hardwareValue(_ title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    // MARK: - 通用标题

    private func cardHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundColor(color)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
        }
    }
}

private extension View {
    func cardContainer() -> some View {
        self.padding(16)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
    }
}
