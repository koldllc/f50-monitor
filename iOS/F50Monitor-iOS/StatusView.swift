import SwiftUI
import F50Core

/// iOS 主状态面板：信号、速度、流量、硬件指标
struct StatusView: View {
    @ObservedObject var fetcher: F50Fetcher

    private var status: F50Status { fetcher.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    connectionHeader
                    if !status.isOnline {
                        errorBox
                    }
                    signalCard
                    speedCard
                    trafficCard
                    hardwareCard
                }
                .padding()
            }
            .navigationTitle("F50 Monitor")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Link(destination: URL(string: fetcher.baseURLString) ?? URL(string: "http://192.168.0.1:2333")!) {
                            Image(systemName: "safari")
                        }
                        .help("打开 Web 后台")
                        Button {
                            fetcher.fetchData()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 连接状态头部

    private var connectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(status.isOnline ? "在线" : "未在线")
                    .font(.title3.bold())
                    .foregroundColor(status.isOnline ? .green : .red)
                Text("最后更新 \(status.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("刷新") { fetcher.fetchData() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private var errorBox: some View {
        VStack(spacing: 6) {
            Label(status.errorMessage ?? "无法连接到 F50 后台", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundColor(.orange)
            Text("请在设置中检查后台地址与口令，并确认手机已连接 F50 的 WiFi")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }

    // MARK: - 信号卡片

    private var signalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("蜂窝信号", icon: "cellularbars", color: .blue)

            HStack {
                HStack(spacing: 6) {
                    if let assetName = carrierLogoAssetName {
                        Image(assetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "simcard.fill")
                            .foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.networkType)
                            .font(.headline)
                        Text(status.carrier)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if !status.currentBands.isEmpty {
                        Text(status.currentBands)
                            .font(.caption.monospaced())
                            .foregroundColor(.purple)
                    }
                }
                Spacer()
                signalBars
            }

            HStack(spacing: 8) {
                signalMetric("RSRP", value: status.rsrp, quality: status.rsrpQuality)
                signalMetric("SINR", value: status.snr, quality: status.snrQuality)
                signalMetric("RSRQ", value: status.rsrq, quality: status.rsrqQuality)
            }

            // 签约状态（QCI & 上下行签约速率）
            HStack {
                Text("签约状态")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(subscriptionText)
                    .font(.caption.bold().monospaced())
                    .foregroundColor(subscriptionText == "无数据" ? .secondary : .primary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue.opacity(0.06)))
        }
        .cardStyle()
    }

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...5, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 2)
                    .fill(bar <= status.signalBar ? Color.green : Color.gray.opacity(0.25))
                    .frame(width: 5, height: CGFloat(bar * 4 + 4))
            }
        }
    }

    /// 运营商 logo 资源名（与 macOS 版匹配逻辑一致）
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

    /// 签约状态（QCI & 上下行签约速率），与 macOS 面板一致
    private var subscriptionText: String {
        let qciVal = status.qci.trimmingCharacters(in: .whitespaces)
        let dlVal = status.qosDl.trimmingCharacters(in: .whitespaces)
        let ulVal = status.qosUl.trimmingCharacters(in: .whitespaces)

        if qciVal.isEmpty && dlVal.isEmpty && ulVal.isEmpty {
            return "无数据"
        }

        var parts: [String] = []
        parts.append(qciVal.isEmpty ? "QCI：-" : "QCI：\(qciVal)")
        if !dlVal.isEmpty {
            parts.append("⬇️ \(dlVal)")
        }
        if !ulVal.isEmpty {
            parts.append("⬆️ \(ulVal)")
        }
        return parts.joined(separator: "  ")
    }

    private func signalMetric(_ title: String, value: String, quality: (label: String, color: Color, ratio: Double)) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold().monospaced())
            ProgressView(value: quality.ratio)
                .tint(quality.color)
            Text(quality.label)
                .font(.caption2.bold())
                .foregroundColor(quality.color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
    }

    // MARK: - 速度卡片

    private var speedCard: some View {
        HStack(spacing: 12) {
            speedColumn("下载", speed: status.dlSpeed, color: .green, icon: "arrow.down.circle.fill")
            speedColumn("上传", speed: status.ulSpeed, color: .blue, icon: "arrow.up.circle.fill")
        }
        .cardStyle()
    }

    private func speedColumn(_ title: String, speed: Double, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(F50Status.formatSpeed(speed))
                .font(.title3.bold().monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.08)))
    }

    // MARK: - 流量卡片

    private var trafficCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("套餐流量", icon: "chart.bar.fill", color: .cyan)

            let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
            HStack {
                Text("已用 \(F50Status.formatBytes(packageUsed))")
                    .font(.subheadline.bold().monospaced())
                Spacer()
                if status.trafficLimit > 0 {
                    Text("共 \(F50Status.formatBytes(status.trafficLimit))")
                        .font(.subheadline.monospaced())
                        .foregroundColor(.secondary)
                }
            }
            if status.trafficLimit > 0 {
                ProgressView(value: status.trafficUsageRatio)
                    .tint(status.trafficUsageColor)
                HStack {
                    Text(String(format: "%.1f%%", status.trafficUsageRatio * 100))
                        .font(.caption.bold())
                        .foregroundColor(status.trafficUsageColor)
                    Spacer()
                    if let days = status.daysUntilReset {
                        Text(days == 0 ? "今天重置" : "\(days) 天后重置")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                usageColumn("当日流量", value: status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal, icon: "sun.max.fill", color: .orange)
                Divider().frame(height: 30)
                usageColumn("本月已用", value: status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal, icon: "calendar", color: .purple)
            }
        }
        .cardStyle()
    }

    private func usageColumn(_ title: String, value: UInt64, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(F50Status.formatBytes(value))
                .font(.subheadline.bold().monospaced())
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 硬件卡片

    private var hardwareCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            cardTitle("硬件状态", icon: "cpu.fill", color: .indigo)

            HStack(spacing: 12) {
                metricBar("CPU", value: status.cpuUsage, color: status.cpuColor)
                metricBar("内存", value: status.memUsage, color: status.memColor)
            }
            HStack(spacing: 12) {
                hardwareValue("芯片温度", value: status.temperature > 0 ? String(format: "%.1f℃", status.temperature) : "--", color: status.tempColor, icon: "thermometer.medium")
                hardwareValue("连接设备", value: "\(status.connectedDevices) 台", color: .purple, icon: "laptopcomputer.and.iphone")
            }
        }
        .cardStyle()
    }

    private func metricBar(_ title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value > 0 ? String(format: "%.0f%%", value) : "--")
                    .font(.caption.bold().monospaced())
                    .foregroundColor(color)
            }
            ProgressView(value: min(100, max(0, value)), total: 100)
                .tint(color)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground)))
    }

    private func hardwareValue(_ title: String, value: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.subheadline.bold().monospaced())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemBackground)))
    }

    // MARK: - 通用

    private func cardTitle(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.bold())
            .foregroundColor(color)
    }
}

private extension View {
    func cardStyle() -> some View {
        self.padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}
