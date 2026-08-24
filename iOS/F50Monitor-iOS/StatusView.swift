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

// MARK: - Custom Progress Bar
private struct CustomProgressBar: View {
    var value: Double // 0.0 ... 1.0
    var color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: height)

                let clampedValue = min(1.0, max(0.0, value))
                Capsule()
                    .fill(color)
                    .frame(width: max(height, geo.size.width * CGFloat(clampedValue)), height: height)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Speed Wave Sparkline Shape & View
private struct SpeedWaveShape: Shape {
    var points: [Double] // Normalized values (0.0 ... 1.0)
    var isFilled: Bool = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let effectivePoints: [Double]
        if points.count >= 3 {
            effectivePoints = points
        } else {
            // Default smooth undulating resting wave
            effectivePoints = [0.15, 0.45, 0.22, 0.60, 0.35, 0.70, 0.30, 0.48, 0.25]
        }

        let count = effectivePoints.count
        let stepX = rect.width / CGFloat(count - 1)
        let coords: [CGPoint] = effectivePoints.enumerated().map { i, val in
            let clamped = max(0.06, min(0.94, val))
            let y = rect.height * CGFloat(1.0 - clamped)
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }

        path.move(to: coords[0])
        for i in 0..<(count - 1) {
            let p0 = i > 0 ? coords[i - 1] : coords[i]
            let p1 = coords[i]
            let p2 = coords[i + 1]
            let p3 = i + 2 < count ? coords[i + 2] : p2

            let cp1 = CGPoint(
                x: p1.x + (p2.x - p0.x) / 5.5,
                y: p1.y + (p2.y - p0.y) / 5.5
            )
            let cp2 = CGPoint(
                x: p2.x - (p3.x - p1.x) / 5.5,
                y: p2.y - (p3.y - p1.y) / 5.5
            )
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }

        if isFilled {
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: rect.height))
            path.closeSubpath()
        }

        return path
    }
}

private struct SpeedWaveView: View {
    var samples: [Double]
    var color: Color
    var currentSpeed: Double

    private var normalizedPoints: [Double] {
        if samples.count < 3 {
            if currentSpeed > 0 {
                return [0.20, 0.50, 0.28, 0.65, 0.35, 0.72, 0.30, 0.50, 0.25]
            } else {
                return [0.12, 0.18, 0.14, 0.20, 0.15, 0.19, 0.13, 0.17, 0.12]
            }
        }
        let maxVal = max(1024.0, samples.max() ?? 1024.0)
        return samples.map { val in
            let ratio = val / maxVal
            return 0.12 + 0.76 * ratio
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SpeedWaveShape(points: normalizedPoints, isFilled: true)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.25), color.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            SpeedWaveShape(points: normalizedPoints, isFilled: false)
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .clipped()
    }
}

/// iOS 主状态面板：系统原生导航与全填充卡片仪表盘
struct StatusView: View {
    @ObservedObject var fetcher: F50Fetcher
    @State private var webURLToOpen: IdentifiableURL?
    @Environment(\.colorScheme) private var colorScheme

    private var status: F50Status { fetcher.status }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let isCompact = geo.size.height < 700
                let minContentHeight: CGFloat = isCompact ? 570 : 620
                let cardSpacing: CGFloat = isCompact ? 6 : 8
                let verticalPadding: CGFloat = isCompact ? 6 : 8

                ScrollView(showsIndicators: false) {
                    VStack(spacing: cardSpacing) {
                        if fetcher.isDemoMode {
                            demoModeBanner
                        } else if !status.isOnline {
                            errorBox
                        }

                        signalCard
                        speedCard
                        trafficCard
                        hardwareCard
                    }
                    .padding(.horizontal, isCompact ? 12 : 16)
                    .padding(.vertical, verticalPadding)
                    .frame(width: geo.size.width)
                    .frame(minHeight: max(minContentHeight, geo.size.height))
                }
                .scrollDisabled(geo.size.height >= minContentHeight)
            }
            .background(F50Theme.panelBackground(for: colorScheme).ignoresSafeArea())
            .navigationTitle("F50 Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ControlGroup {
                        Button {
                            Task {
                                await fetcher.fetchDataAsync()
                            }
                        } label: {
                            Label("立即刷新", systemImage: "arrow.clockwise")
                        }

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
                            Label("打开后台", systemImage: "safari")
                        }
                    }
                }
            }
            .sheet(item: $webURLToOpen) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Reusable Card Background View
    private var cardBackgroundView: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(F50Theme.cardBackground(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(F50Theme.cardBorder(for: colorScheme), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.02), radius: 6, y: 2)
    }

    private var demoModeBanner: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(F50Theme.blue)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("演示模式")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("DEMO")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(F50Theme.blue)
                        .clipShape(Capsule())
                }
                Text("当前展示模拟 5G 信号与全量数据，审核/体验无需物理硬件")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("退出") {
                fetcher.isDemoMode = false
            }
            .font(.caption.weight(.medium))
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(F50Theme.blue.opacity(0.12))
        )
    }

    private var errorBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(F50Theme.orange)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.errorMessage ?? "无法连接到 F50 随身 WiFi")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.primary)
                    Text("请检查是否已连接设备 Wi-Fi，并确认设置中的设备地址正确")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(F50Theme.orange.opacity(0.12))
        )
    }

    // MARK: - 1. 信号与网络卡片
    private var signalCard: some View {
        VStack(spacing: 10) {
            // Row 1: Carrier logo + Name + Mode capsule + Band capsule + Signal bars + Spacer + Online Status Badge
            HStack(spacing: 7) {
                if !status.carrier.isEmpty && status.carrier != "未知" {
                    HStack(spacing: 6) {
                        carrierLogoView
                        Text(status.carrier)
                    }
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                }

                Text(status.networkType)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8.5)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(F50Theme.blue.opacity(0.12)))
                    .foregroundColor(F50Theme.blue)

                if !status.currentBands.isEmpty {
                    Text(status.currentBands)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8.5)
                        .padding(.vertical, 3.5)
                        .background(Capsule().fill(F50Theme.purple.opacity(0.12)))
                        .foregroundColor(F50Theme.purple)
                }

                // Signal Bars
                signalBars

                Spacer()

                // Compact Online/Offline Status Badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(status.isOnline ? F50Theme.green : F50Theme.red)
                        .frame(width: 7, height: 7)
                    Text(status.isOnline ? "在线" : "未在线")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(status.isOnline ? F50Theme.green : F50Theme.red)
                }
                .padding(.horizontal, 8.5)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill((status.isOnline ? F50Theme.green : F50Theme.red).opacity(0.12))
                )
            }

            // Row 2: Inset Subscription Banner
            subscriptionBanner

            Divider()
                .opacity(0.4)

            // Row 3: 3 Signal Metrics Columns
            HStack(spacing: 10) {
                let rsrpQ = status.rsrpQuality
                signalColumn("RSRP", value: status.rsrp, quality: rsrpQ)

                Divider()
                    .frame(height: 38)
                    .opacity(0.4)

                let snrQ = status.snrQuality
                signalColumn("SINR / SNR", value: status.snr, quality: snrQ)

                Divider()
                    .frame(height: 38)
                    .opacity(0.4)

                let rsrqQ = status.rsrqQuality
                signalColumn("RSRQ", value: status.rsrq, quality: rsrqQ)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackgroundView)
    }

    private func signalColumn(_ title: String, value: String, quality: (label: String, color: Color, ratio: Double)) -> some View {
        VStack(spacing: 4.5) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)

            CustomProgressBar(value: quality.ratio, color: quality.color, height: 6.5)
                .padding(.horizontal, 4)

            Text(quality.label)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundColor(quality.color)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var carrierLogoView: some View {
        if let assetName = carrierLogoAssetName {
            Image(assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
        } else {
            Image(systemName: "simcard.fill")
                .font(.system(size: 19))
                .foregroundColor(.secondary)
        }
    }

    private var signalBars: some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(1...5, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= status.signalBar ? F50Theme.green : Color.primary.opacity(0.12))
                    .frame(width: 3.5, height: CGFloat(Double(bar) * 2.8 + 4))
            }
        }
        .padding(.leading, 3)
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

    private var subscriptionBanner: some View {
        HStack(spacing: 8) {
            Text("签约状态：")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.secondary)

            let qciVal = status.qci.trimmingCharacters(in: .whitespaces)
            let dlVal = status.qosDl.trimmingCharacters(in: .whitespaces)
            let ulVal = status.qosUl.trimmingCharacters(in: .whitespaces)

            if qciVal.isEmpty && dlVal.isEmpty && ulVal.isEmpty {
                Text("无数据")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                Text("QCI: \(qciVal.isEmpty ? "-" : qciVal)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                if !dlVal.isEmpty {
                    HStack(spacing: 3.5) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(F50Theme.blue)
                                .frame(width: 15, height: 15)
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8.5, weight: .heavy))
                                .foregroundColor(.white)
                        }
                        Text(dlVal)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .padding(.leading, 2)
                }

                if !ulVal.isEmpty {
                    HStack(spacing: 3.5) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3.5)
                                .fill(F50Theme.blue)
                                .frame(width: 15, height: 15)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8.5, weight: .heavy))
                                .foregroundColor(.white)
                        }
                        Text(ulVal)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    .padding(.leading, 1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6.5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.035))
        )
    }

    // MARK: - 2. 实时速率卡片
    private var speedCard: some View {
        HStack(spacing: 10) {
            // Realtime Download Card
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(F50Theme.green)
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3.5) {
                        Text("实时下载")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatSpeed(status.dlSpeed))
                            .font(.system(size: 19.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(F50Theme.green)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer(minLength: 4)

                SpeedWaveView(
                    samples: status.dlHistory,
                    color: F50Theme.green,
                    currentSpeed: status.dlSpeed
                )
                .frame(minHeight: 28, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardBackgroundView)

            // Realtime Upload Card
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(F50Theme.blue)
                            .frame(width: 32, height: 32)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3.5) {
                        Text("实时上传")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatSpeed(status.ulSpeed))
                            .font(.system(size: 19.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(F50Theme.blue)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                Spacer(minLength: 4)

                SpeedWaveView(
                    samples: status.ulHistory,
                    color: F50Theme.blue,
                    currentSpeed: status.ulSpeed
                )
                .frame(minHeight: 28, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(cardBackgroundView)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 3. 套餐与统计流量卡片
    private var trafficCard: some View {
        VStack(spacing: 8.5) {
            // Header: Icon + 套餐流量
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(F50Theme.cyan)
                    Text("套餐流量")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundColor(.primary)
                }
                Spacer()
            }

            // Usage & Limit Line
            let packageUsed = status.packageTotal > 0
                ? status.packageTotal
                : status.monthlyTotal

            HStack {
                Text("已用流量：  \(F50Status.formatBytes(packageUsed))")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundColor(.primary)

                Spacer()

                if status.trafficLimit > 0 {
                    Text("总流量：  \(F50Status.formatBytes(status.trafficLimit))")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                } else {
                    Text("总流量：  不限")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            // Progress Bar
            CustomProgressBar(
                value: status.trafficLimit > 0 ? status.trafficUsageRatio : 0.0,
                color: status.trafficUsageColor,
                height: 8
            )

            // Percentage pill & Reset days
            HStack(spacing: 6) {
                if status.trafficLimit > 0 {
                    Text(String(format: "%.0f%%", status.trafficUsageRatio * 100))
                        .font(.system(size: 11.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7.5)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(status.trafficUsageColor.opacity(0.15)))
                        .foregroundColor(status.trafficUsageColor)
                }

                Spacer()

                if let days = status.daysUntilReset {
                    Text(days == 0 ? "今天重置" : "\(days)天后重置")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .opacity(0.4)

            // 2 Metrics Columns: 当日流量 & 本月已用
            HStack(spacing: 10) {
                // Column 1: 当日流量
                VStack(spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 12.5))
                            .foregroundColor(F50Theme.orange)
                        Text("当日流量")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    let daily = status.ufiDailyUsage > 0
                        ? status.ufiDailyUsage
                        : status.dailyTotal
                    Text(F50Status.formatBytes(daily))
                        .font(.system(size: 16.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 30)
                    .opacity(0.4)

                // Column 2: 本月已用
                VStack(spacing: 4) {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12.5))
                            .foregroundColor(F50Theme.purple)
                        Text("本月已用")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    let monthly = status.ufiMonthlyUsage > 0
                        ? status.ufiMonthlyUsage
                        : status.monthlyTotal
                    Text(F50Status.formatBytes(monthly))
                        .font(.system(size: 16.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(cardBackgroundView)
    }

    // MARK: - 4. 硬件状态网格
    private var hardwareCard: some View {
        VStack(spacing: 9) {
            // Row 1: CPU & Memory
            HStack(spacing: 10) {
                // CPU Usage
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CPU 占用率")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(status.cpuUsage > 0 ? String(format: "%.0f%%", status.cpuUsage) : "--")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(status.cpuColor)
                    }
                    CustomProgressBar(
                        value: min(1.0, max(0.0, status.cpuUsage / 100.0)),
                        color: status.cpuColor,
                        height: 6
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackgroundView)

                // Memory Usage
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("内存 占用率")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(status.memUsage > 0 ? String(format: "%.0f%%", status.memUsage) : "--")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(status.memColor)
                    }
                    CustomProgressBar(
                        value: min(1.0, max(0.0, status.memUsage / 100.0)),
                        color: status.memColor,
                        height: 6
                    )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackgroundView)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Row 2: Chip Temperature & Wi-Fi Devices
            HStack(spacing: 10) {
                // Temperature
                HStack(spacing: 10) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(status.tempColor)
                    VStack(alignment: .leading, spacing: 3.5) {
                        Text("芯片温度")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(status.temperature > 0 ? String(format: "%.1f ℃", status.temperature) : "-- ℃")
                            .font(.system(size: 16.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(status.tempColor)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackgroundView)

                // Connected Devices
                HStack(spacing: 10) {
                    Image(systemName: "wifi")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(F50Theme.purple)
                    VStack(alignment: .leading, spacing: 3.5) {
                        Text("Wi-Fi 连接设备")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(status.connectedDevices) 台")
                            .font(.system(size: 16.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(cardBackgroundView)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
