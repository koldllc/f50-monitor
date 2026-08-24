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

// MARK: - Custom Progress Bar
private struct CustomProgressBar: View {
    var value: Double // 0.0 ... 1.0
    var color: Color
    var height: CGFloat = 5

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
            effectivePoints = [0.25, 0.45, 0.20, 0.55, 0.30, 0.65, 0.35, 0.50, 0.30]
        }

        let count = effectivePoints.count
        let stepX = rect.width / CGFloat(count - 1)
        let coords: [CGPoint] = effectivePoints.enumerated().map { i, val in
            let clamped = max(0.08, min(0.92, val))
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
                return [0.25, 0.45, 0.28, 0.60, 0.35, 0.68, 0.32, 0.52, 0.30]
            } else {
                return [0.15, 0.22, 0.16, 0.25, 0.18, 0.24, 0.15, 0.20, 0.15]
            }
        }
        let maxVal = max(1024.0, samples.max() ?? 1024.0)
        return samples.map { val in
            let ratio = val / maxVal
            return 0.15 + 0.70 * ratio
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            SpeedWaveShape(points: normalizedPoints, isFilled: true)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.01)],
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

// MARK: - Action Icon Button
private struct PanelActionButton<Content: View>: View {
    var action: () -> Void
    var width: CGFloat? = 38
    var height: CGFloat = 36
    var tooltip: String? = nil
    var content: () -> Content

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: width, height: height)
                .background(
                    RoundedRectangle(cornerRadius: 11)
                        .fill(isHovered ? F50Theme.controlHover(for: colorScheme) : F50Theme.controlBackground(for: colorScheme))
                )
                .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(tooltip ?? "")
    }
}

// MARK: - Backend Button
private struct BackendMenuButton: View {
    let routerURLString: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        Button {
            guard let url = URL(string: routerURLString) else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "safari")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(F50Theme.blue)
                Text("打开后台")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 11)
                    .fill(isHovered ? F50Theme.controlHover(for: colorScheme) : F50Theme.controlBackground(for: colorScheme))
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("打开中兴后台（80端口）")
    }
}

// MARK: - Main Panel View
struct F50PanelView: View {
    @ObservedObject var fetcher: F50Fetcher
    @ObservedObject var updateManager: UpdateManager
    @ObservedObject var screenMirroringManager: ScreenMirroringManager
    var onOpenSettings: () -> Void
    var onOpenFileShare: () -> Void
    var onOpenSMS: () -> Void
    var onOpenFeedback: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(FileSharingPreferences.enabledDefaultsKey) private var isFileSharingEnabled = true

    init(
        fetcher: F50Fetcher,
        updateManager: UpdateManager,
        screenMirroringManager: ScreenMirroringManager,
        onOpenSettings: @escaping () -> Void,
        onOpenFileShare: @escaping () -> Void,
        onOpenSMS: @escaping () -> Void,
        onOpenFeedback: @escaping () -> Void = {}
    ) {
        self.fetcher = fetcher
        self.updateManager = updateManager
        self.screenMirroringManager = screenMirroringManager
        self.onOpenSettings = onOpenSettings
        self.onOpenFileShare = onOpenFileShare
        self.onOpenSMS = onOpenSMS
        self.onOpenFeedback = onOpenFeedback
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
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "simcard.fill")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            headerView

            if !fetcher.status.isOnline {
                errorAlertBox
            }

            networkAndSignalCard

            speedMetricsRow

            trafficStatisticsCard

            hardwareMetricsGrid

            if screenMirroringManager.isEnabled,
               let msg = screenMirroringManager.statusMessage,
               !msg.isEmpty {
                mirroringStatusBanner(msg)
            }

            actionBar
        }
        .padding(14)
        .frame(width: 376)
        .fixedSize(horizontal: false, vertical: true)
        .background(F50Theme.panelBackground(for: colorScheme))
        .alert("请求下载配置授权", isPresented: $screenMirroringManager.showPermissionAlert) {
            Button("允许并下载") {
                screenMirroringManager.downloadAndInstallStandaloneDependencies()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("无线投屏功能需要依赖官方独立组件包 (scrcpy + ADB)。\n\n点击“允许并下载”将自动在线下载并配置独立组件（无需安装 Homebrew 或终端操作）。")
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(F50Theme.blue)
                Text("F50 Monitor")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            Spacer()

            // Status Badge
            HStack(spacing: 5) {
                Circle()
                    .fill(fetcher.status.isOnline ? F50Theme.green : F50Theme.red)
                    .frame(width: 6, height: 6)
                Text(fetcher.status.isOnline ? "在线" : "未在线")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(fetcher.status.isOnline ? F50Theme.green : F50Theme.red)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(
                Capsule()
                    .fill((fetcher.status.isOnline ? F50Theme.green : F50Theme.red).opacity(0.14))
            )

            if updateManager.availableVersion != nil {
                Button(action: updateManager.installAvailableUpdate) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(F50Theme.green)
                }
                .buttonStyle(.plain)
                .help(updateManager.statusText)
            }

            Button(action: {
                fetcher.fetchData()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("立即刷新")
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Error Alert Box
    private var errorAlertBox: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(F50Theme.orange)
                Text(fetcher.status.errorMessage ?? "无法连接到设备后台")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }
            Text("请在设置中检查管理密码及 IP 地址，并确认已连接 Wi-Fi")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Button {
                onOpenFeedback()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stethoscope")
                    Text("新设备无法识别？提交接口诊断")
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(F50Theme.blue)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(F50Theme.orange.opacity(0.12))
        )
    }

    // MARK: - 1. Network & 3 Signal Metrics Card
    private var networkAndSignalCard: some View {
        VStack(spacing: 10) {
            // Row 1: Carrier logo + Name + Mode capsule + Band capsule + Signal bars
            HStack(spacing: 6) {
                if !fetcher.status.carrier.isEmpty && fetcher.status.carrier != "未知" {
                    HStack(spacing: 5) {
                        carrierLogoView
                        Text(fetcher.status.carrier)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                            .layoutPriority(1)
                    }
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                }

                Text(fetcher.status.networkType)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(F50Theme.blue.opacity(0.14)))
                    .foregroundColor(F50Theme.blue)

                if !fetcher.status.currentBands.isEmpty {
                    Text(fetcher.status.currentBands)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(F50Theme.purple.opacity(0.14)))
                        .foregroundColor(F50Theme.purple)
                }

                // Cellular Signal Bars
                HStack(alignment: .bottom, spacing: 2.2) {
                    ForEach(1...5, id: \.self) { bar in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(bar <= fetcher.status.signalBar ? F50Theme.green : Color.primary.opacity(0.15))
                            .frame(width: 3.2, height: CGFloat(Double(bar) * 2.4 + 3.5))
                    }
                }
                .padding(.leading, 3)

                Spacer()
            }

            // Row 2: Inset Subscription / QCI Status Banner
            subscriptionBanner

            Divider()
                .opacity(0.5)

            // Row 3: 3 Signal Metrics Columns (RSRP, SINR/SNR, RSRQ)
            HStack(spacing: 8) {
                // Column 1: RSRP
                let rsrpQ = fetcher.status.rsrpQuality
                VStack(spacing: 4) {
                    Text("RSRP")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(fetcher.status.rsrp)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)

                    CustomProgressBar(value: rsrpQ.ratio, color: rsrpQ.color, height: 4.5)
                        .padding(.horizontal, 4)

                    Text(rsrpQ.label)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(rsrpQ.color)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 38)
                    .opacity(0.5)

                // Column 2: SINR / SNR
                let snrQ = fetcher.status.snrQuality
                VStack(spacing: 4) {
                    Text("SINR / SNR")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(fetcher.status.snr)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)

                    CustomProgressBar(value: snrQ.ratio, color: snrQ.color, height: 4.5)
                        .padding(.horizontal, 4)

                    Text(snrQ.label)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(snrQ.color)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 38)
                    .opacity(0.5)

                // Column 3: RSRQ
                let rsrqQ = fetcher.status.rsrqQuality
                VStack(spacing: 4) {
                    Text("RSRQ")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(fetcher.status.rsrq)
                        .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)

                    CustomProgressBar(value: rsrqQ.ratio, color: rsrqQ.color, height: 4.5)
                        .padding(.horizontal, 4)

                    Text(rsrqQ.label)
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(rsrqQ.color)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(cardBackgroundView)
    }

    // MARK: - Subscription Banner
    private var subscriptionBanner: some View {
        let qciVal = fetcher.status.qci.trimmingCharacters(in: .whitespaces)
        let dlVal = fetcher.status.qosDl.trimmingCharacters(in: .whitespaces)
        let ulVal = fetcher.status.qosUl.trimmingCharacters(in: .whitespaces)

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("签约状态：")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Text(qciVal.isEmpty && dlVal.isEmpty && ulVal.isEmpty ? "无数据" : "QCI: \(qciVal.isEmpty ? "-" : qciVal)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(qciVal.isEmpty && dlVal.isEmpty && ulVal.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }

            if !dlVal.isEmpty || !ulVal.isEmpty {
                HStack(spacing: 10) {
                    qosRate(dlVal, arrow: "arrow.down")
                    qosRate(ulVal, arrow: "arrow.up")
                }
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.035))
        )
    }

    @ViewBuilder
    private func qosRate(_ value: String, arrow: String) -> some View {
        if !value.isEmpty {
            HStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(F50Theme.blue)
                        .frame(width: 14, height: 14)
                    Image(systemName: arrow)
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(.white)
                }
                Text(value)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    // MARK: - 2. Speeds Card with Waveform Sparkline
    private var speedMetricsRow: some View {
        HStack(spacing: 10) {
            // Realtime Download Card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(F50Theme.green)
                            .frame(width: 26, height: 26)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时下载")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatSpeed(fetcher.status.dlSpeed))
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(F50Theme.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                SpeedWaveView(
                    samples: fetcher.status.dlHistory,
                    color: F50Theme.green,
                    currentSpeed: fetcher.status.dlSpeed
                )
                .frame(height: 30)
            }
            .frame(maxWidth: .infinity)
            .background(cardBackgroundView)

            // Realtime Upload Card
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(F50Theme.blue)
                            .frame(width: 26, height: 26)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时上传")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatSpeed(fetcher.status.ulSpeed))
                            .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(F50Theme.blue)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .allowsTightening(true)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.top, 10)

                SpeedWaveView(
                    samples: fetcher.status.ulHistory,
                    color: F50Theme.blue,
                    currentSpeed: fetcher.status.ulSpeed
                )
                .frame(height: 30)
            }
            .frame(maxWidth: .infinity)
            .background(cardBackgroundView)
        }
    }

    // MARK: - 3. Traffic Statistics Card
    private var trafficStatisticsCard: some View {
        VStack(spacing: 9) {
            // Header: Icon + 套餐流量
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(F50Theme.cyan)
                    Text("套餐流量")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                }
                Spacer()
            }

            // Remaining & Usage Line
            let packageUsed = fetcher.status.packageTotal > 0
                ? fetcher.status.packageTotal
                : fetcher.status.monthlyTotal
            let remaining = fetcher.status.trafficLimit > packageUsed
                ? fetcher.status.trafficLimit - packageUsed
                : 0

            HStack {
                Text("剩余： \(fetcher.status.trafficLimit > 0 ? F50Status.formatBytes(remaining) : "不限")")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(.primary)

                Spacer()

                if fetcher.status.trafficLimit > 0 {
                    Text(String(format: "已用：%.2f/%.2f GB", Double(packageUsed) / 1_073_741_824, Double(fetcher.status.trafficLimit) / 1_073_741_824))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                } else {
                    Text("已用： \(F50Status.formatBytes(packageUsed))/不限")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            // Progress Bar
            CustomProgressBar(
                value: fetcher.status.trafficLimit > 0 ? fetcher.status.trafficUsageRatio : 0.0,
                color: fetcher.status.trafficUsageColor,
                height: 6
            )

            // Usage percentage & Reset days
            HStack(spacing: 6) {
                if fetcher.status.trafficLimit > 0 {
                    Text(String(format: "已用：%.0f%%", fetcher.status.trafficUsageRatio * 100))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(fetcher.status.trafficUsageColor.opacity(0.15)))
                        .foregroundColor(fetcher.status.trafficUsageColor)
                }

                Spacer()

                if let days = fetcher.status.daysUntilReset {
                    Text(days == 0 ? "今天重置" : "\(days)天后重置")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .opacity(0.5)

            // 2 Metrics Columns: 当日流量 & 本月已用
            HStack(spacing: 8) {
                // Column 1: 当日流量
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
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
                        .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)

                Divider()
                    .frame(height: 28)
                    .opacity(0.5)

                // Column 2: 本月已用
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
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
                        .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(cardBackgroundView)
    }

    // MARK: - 4. Hardware Metrics Grid
    private var hardwareMetricsGrid: some View {
        VStack(spacing: 10) {
            // Row 1: CPU & Memory
            HStack(spacing: 10) {
                // CPU Usage
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("CPU 占用率")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(fetcher.status.cpuUsage > 0 ? String(format: "%.0f%%", fetcher.status.cpuUsage) : "--")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(fetcher.status.cpuColor)
                    }
                    CustomProgressBar(
                        value: min(1.0, max(0.0, fetcher.status.cpuUsage / 100.0)),
                        color: fetcher.status.cpuColor,
                        height: 4.5
                    )
                }
                .padding(9)
                .frame(maxWidth: .infinity)
                .background(cardBackgroundView)

                // Memory Usage
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("内存 占用率")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(fetcher.status.memUsage > 0 ? String(format: "%.0f%%", fetcher.status.memUsage) : "--")
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(fetcher.status.memColor)
                    }
                    CustomProgressBar(
                        value: min(1.0, max(0.0, fetcher.status.memUsage / 100.0)),
                        color: fetcher.status.memColor,
                        height: 4.5
                    )
                }
                .padding(9)
                .frame(maxWidth: .infinity)
                .background(cardBackgroundView)
            }

            // Row 2: Chip Temperature & Wi-Fi Devices
            HStack(spacing: 10) {
                // Temperature
                HStack(spacing: 10) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(fetcher.status.tempColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("芯片温度")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(fetcher.status.temperature > 0 ? String(format: "%.1f ℃", fetcher.status.temperature) : "-- ℃")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(fetcher.status.tempColor)
                    }
                    Spacer()
                }
                .padding(9)
                .frame(maxWidth: .infinity)
                .background(cardBackgroundView)

                // Connected Devices
                HStack(spacing: 10) {
                    Image(systemName: "wifi")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(F50Theme.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Wi-Fi 连接设备")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(fetcher.status.connectedDevices) 台")
                            .font(.system(size: 13.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(.primary)
                    }
                    Spacer()
                }
                .padding(9)
                .frame(maxWidth: .infinity)
                .background(cardBackgroundView)
            }
        }
    }

    // MARK: - Mirroring Status Banner
    private func mirroringStatusBanner(_ msg: String) -> some View {
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(F50Theme.purple.opacity(0.1))
        )
    }

    // MARK: - 5. Bottom Action Bar
    private var actionBar: some View {
        HStack(spacing: 8) {
            // Open Web Dashboard Menu Button
            BackendMenuButton(
                routerURLString: fetcher.routerURLString
            )

            if isFileSharingEnabled {
                PanelActionButton(action: onOpenFileShare, tooltip: "文件共享") {
                    Image(systemName: "folder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
            }

            // Screen Mirroring Button
            if screenMirroringManager.isEnabled {
                PanelActionButton(action: {
                    if screenMirroringManager.isDependenciesInstalled {
                        screenMirroringManager.startMirroring(baseURLString: fetcher.baseURLString)
                    } else {
                        screenMirroringManager.requestInstallDependencies()
                    }
                }, tooltip: screenMirroringManager.isDependenciesInstalled ? "无线 ADB 投屏" : "未检测到投屏组件，点击配置") {
                    Group {
                        if screenMirroringManager.isConnecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "tv")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                }
                .disabled(screenMirroringManager.isConnecting || !fetcher.status.isOnline)
            }

            // SMS Button
            PanelActionButton(action: onOpenSMS, tooltip: "读取短信") {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "envelope")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    if fetcher.status.smsUnreadCount > 0 {
                        Text(fetcher.status.smsUnreadCount > 99 ? "99+" : "\(fetcher.status.smsUnreadCount)")
                            .font(.system(size: 7, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(F50Theme.red))
                            .offset(x: 7, y: -6)
                    }
                }
            }

            // Settings Button
            PanelActionButton(action: onOpenSettings, tooltip: "设置") {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }

            // Quit Button
            PanelActionButton(action: {
                NSApplication.shared.terminate(nil)
            }, tooltip: "退出程序") {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(F50Theme.red)
            }
        }
    }

    // MARK: - Reusable Card Background View
    private var cardBackgroundView: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(F50Theme.cardBackground(for: colorScheme))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(F50Theme.cardBorder(for: colorScheme), lineWidth: 1)
            )
    }
}
