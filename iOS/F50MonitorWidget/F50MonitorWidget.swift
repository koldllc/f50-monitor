import WidgetKit
import SwiftUI
import F50Core

// MARK: - Timeline Entry

struct F50StatusEntry: TimelineEntry {
    let date: Date
    let status: F50Status?
}

// MARK: - Provider

struct F50StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> F50StatusEntry {
        F50StatusEntry(date: Date(), status: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (F50StatusEntry) -> Void) {
        completion(F50StatusEntry(date: Date(), status: F50WidgetDataStore.loadStatus()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<F50StatusEntry>) -> Void) {
        let entry = F50StatusEntry(date: Date(), status: F50WidgetDataStore.loadStatus())
        // 小组件刷新受系统调度，15 分钟为一个周期
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Circular Progress Ring Component

private struct CircularProgressRing: View {
    var ratio: Double // 0.0 ... 1.0
    var percentText: String
    var subtext: String = "剩余"
    var color: Color = F50Theme.green
    var lineWidth: CGFloat = 4.5
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(color.opacity(0.18), lineWidth: lineWidth)

            // Progress stroke (clockwise from top)
            Circle()
                .trim(from: 0, to: CGFloat(min(1.0, max(0.0, ratio))))
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Center texts
            VStack(spacing: 0) {
                Text(percentText)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(subtext)
                    .font(.system(size: size * 0.17, weight: .medium))
                    .foregroundColor(color.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Widget Main View

struct F50StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: F50StatusEntry

    private var status: F50Status? { entry.status }

    private var subcardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.038)
    }

    var body: some View {
        widgetContent
            .widgetContainerBackground(colorScheme: colorScheme)
    }

    @ViewBuilder
    private var widgetContent: some View {
        if let status, status.isOnline {
            switch family {
            case .systemSmall:
                smallView(status)
            case .systemMedium:
                mediumView(status)
            case .accessoryRectangular:
                accessoryRectangularView(status)
            case .accessoryCircular:
                accessoryCircularView(status)
            case .accessoryInline:
                accessoryInlineView(status)
            case .systemLarge, .systemExtraLarge:
                mediumView(status)
            @unknown default:
                mediumView(status)
            }
        } else {
            offlineView
        }
    }

    // MARK: 离线 / 无数据

    @ViewBuilder
    private var offlineView: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 22))
                .foregroundColor(F50Theme.orange)
            Text("F50 未连接")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text("打开 App 同步状态")
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 运营商图标
    private func carrierLogoAssetName(for status: F50Status) -> String? {
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

    // MARK: 拆分数值与单位
    private func splitBytes(_ bytes: UInt64) -> (value: String, unit: String) {
        let formatted = F50Status.formatBytes(bytes)
        let parts = formatted.split(separator: " ")
        if parts.count >= 2 {
            return (String(parts[0]), String(parts[1]))
        }
        return (formatted, "")
    }

    // MARK: - 1. 小尺寸小组件 (systemSmall - 精密适配 158pt)

    @ViewBuilder
    func smallView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        let daily = status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal
        let monthly = status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal

        let limit = status.trafficLimit
        let remainingBytes: UInt64 = limit > packageUsed ? limit - packageUsed : 0
        let remainingRatio: Double = limit > 0 ? Double(remainingBytes) / Double(limit) : 1.0
        let remainingPercentText: String = limit > 0 ? String(format: "%.0f%%", remainingRatio * 100) : "100%"

        let ringColor: Color = {
            if limit == 0 { return F50Theme.green }
            if remainingRatio <= 0.10 { return F50Theme.red }
            if remainingRatio <= 0.25 { return F50Theme.orange }
            return F50Theme.green
        }()

        VStack(alignment: .leading, spacing: 0) {
            // 1. 顶部：运营商 Logo + 制式 + 频段 + 在线状态原点
            HStack(alignment: .center, spacing: 4.5) {
                if let logo = carrierLogoAssetName(for: status) {
                    Image(logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } else if !status.carrier.isEmpty && status.carrier != "未知" {
                    Text(status.carrier)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                }

                Text(status.networkType)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(F50Theme.blue.opacity(0.15)))
                    .foregroundColor(F50Theme.blue)
                    .fixedSize()

                if !status.currentBands.isEmpty {
                    Text(status.currentBands)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(F50Theme.purple.opacity(0.15)))
                        .foregroundColor(F50Theme.purple)
                        .fixedSize()
                }

                Spacer(minLength: 2)

                Circle()
                    .fill(status.isOnline ? F50Theme.green : F50Theme.red)
                    .frame(width: 6, height: 6)
            }

            Spacer(minLength: 2)

            // 2. 中部核心流量区：剩余流量 + 圆环图
            HStack(alignment: .center, spacing: 3) {
                VStack(alignment: .leading, spacing: 1.5) {
                    Text("剩余流量")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    // 大字剩余流量 (16.5pt 粗体)
                    let split = splitBytes(limit > 0 ? remainingBytes : packageUsed)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(split.value)
                            .font(.system(size: 16.5, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(split.unit)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .fixedSize()
                    }

                    if limit > 0 {
                        Text("共 \(F50Status.formatBytes(limit))")
                            .font(.system(size: 8, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    if let days = status.daysUntilReset {
                        Text(days == 0 ? "今天重置" : "\(days)天后重置")
                            .font(.system(size: 8, weight: .medium))
                            .padding(.horizontal, 5.5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(subcardFill))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.top, 0.5)
                    }
                }

                Spacer(minLength: 2)

                // 右侧仅保留环形进度
                CircularProgressRing(
                    ratio: remainingRatio,
                    percentText: remainingPercentText,
                    subtext: "剩余",
                    color: ringColor,
                    lineWidth: 4.5,
                    size: 48
                )
            }

            Spacer(minLength: 2)

            // 3. 底部双指标卡片：今日流量 & 本月已用
            HStack(spacing: 6) {
                // 当日流量
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 2.5) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 7.5))
                            .foregroundColor(F50Theme.orange)
                        Text("今日流量")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(F50Status.formatBytes(daily))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(subcardFill)
                )

                // 本月已用
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 2.5) {
                        Image(systemName: "calendar")
                            .font(.system(size: 7.5))
                            .foregroundColor(F50Theme.purple)
                        Text("本月已用")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(F50Status.formatBytes(monthly))
                        .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(subcardFill)
                )
            }
        }
    }

    // MARK: - 2. 中尺寸小组件 (systemMedium)

    @ViewBuilder
    func mediumView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        let daily = status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal
        let monthly = status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal

        let limit = status.trafficLimit
        let remainingBytes: UInt64 = limit > packageUsed ? limit - packageUsed : 0
        let remainingRatio: Double = limit > 0 ? Double(remainingBytes) / Double(limit) : 1.0
        let remainingPercentText: String = limit > 0 ? String(format: "%.0f%%", remainingRatio * 100) : "100%"

        let ringColor: Color = {
            if limit == 0 { return F50Theme.green }
            if remainingRatio <= 0.10 { return F50Theme.red }
            if remainingRatio <= 0.25 { return F50Theme.orange }
            return F50Theme.green
        }()

        VStack(alignment: .leading, spacing: 0) {
            // 1. 顶部：运营商 Logo + 名称 + 制式 + 频段 + 在线状态原点
            HStack(alignment: .center, spacing: 5.5) {
                if let logo = carrierLogoAssetName(for: status) {
                    Image(logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 17, height: 17)
                }
                if !status.carrier.isEmpty && status.carrier != "未知" {
                    Text(status.carrier)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(status.networkType)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(F50Theme.blue.opacity(0.15)))
                    .foregroundColor(F50Theme.blue)
                    .fixedSize()

                if !status.currentBands.isEmpty {
                    Text(status.currentBands)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(F50Theme.purple.opacity(0.15)))
                        .foregroundColor(F50Theme.purple)
                        .fixedSize()
                }

                Spacer(minLength: 4)

                Circle()
                    .fill(status.isOnline ? F50Theme.green : F50Theme.red)
                    .frame(width: 7, height: 7)
            }

            Spacer(minLength: 5)

            // 2. 主体三栏：[左: 环形图] + Spacer + [中: 居中剩余流量] + Spacer + [右: 窄版 3 个指标卡]
            HStack(alignment: .center, spacing: 0) {
                // 左：大号环形进度 (76pt 饱满强视觉)
                CircularProgressRing(
                    ratio: remainingRatio,
                    percentText: remainingPercentText,
                    subtext: "剩余",
                    color: ringColor,
                    lineWidth: 6.5,
                    size: 76
                )
                .fixedSize()

                Spacer(minLength: 12)

                // 中：居中排布的剩余流量核心数据
                VStack(alignment: .leading, spacing: 2) {
                    Text("剩余流量")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    let split = splitBytes(limit > 0 ? remainingBytes : packageUsed)
                    HStack(alignment: .lastTextBaseline, spacing: 2.5) {
                        Text(split.value)
                            .font(.system(size: 25, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(split.unit)
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .fixedSize()
                    }

                    if limit > 0 {
                        Text("共 \(F50Status.formatBytes(limit))")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    if let days = status.daysUntilReset {
                        Text(days == 0 ? "今天重置" : "\(days)天后重置")
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(subcardFill))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.top, 0.5)
                    }
                }
                .fixedSize()

                Spacer(minLength: 12)

                // 右：收窄至 80pt 的单列两行指标卡片
                VStack(spacing: 4) {
                    metricBox(
                        title: "今日流量",
                        value: F50Status.formatBytes(daily),
                        icon: "sun.max.fill",
                        iconColor: F50Theme.orange
                    )
                    metricBox(
                        title: "本月已用",
                        value: F50Status.formatBytes(monthly),
                        icon: "calendar",
                        iconColor: F50Theme.purple
                    )
                    metricBox(
                        title: "连接设备",
                        value: "\(status.connectedDevices) 台",
                        icon: "wifi",
                        iconColor: F50Theme.blue
                    )
                }
                .frame(width: 80)
            }

            Spacer(minLength: 2)
        }
    }

    // MARK: 锁屏矩形小组件

    @ViewBuilder
    private func accessoryRectangularView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        let daily = status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal
        let monthly = status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                Text("已用 \(F50Status.formatBytes(packageUsed))")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if status.trafficLimit > 0 {
                    Text("/ \(F50Status.formatBytes(status.trafficLimit))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if status.trafficLimit > 0 {
                Gauge(value: status.trafficUsageRatio) {}
                    .gaugeStyle(.accessoryLinear)
            }
            Text("当日 \(F50Status.formatBytes(daily))  本月 \(F50Status.formatBytes(monthly))")
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: 锁屏圆形小组件

    @ViewBuilder
    private func accessoryCircularView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        Gauge(value: status.trafficLimit > 0 ? status.trafficUsageRatio : 0.5) {
            Image(systemName: "chart.bar.fill")
        } currentValueLabel: {
            Text(F50Status.formatBytes(packageUsed))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
    }

    // MARK: 锁屏单行小组件

    @ViewBuilder
    private func accessoryInlineView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        ViewThatFits {
            Text("F50流量: \(F50Status.formatBytes(packageUsed)) / \(F50Status.formatBytes(status.trafficLimit > 0 ? status.trafficLimit : packageUsed))")
            Text("F50: \(F50Status.formatBytes(packageUsed))")
        }
    }

    // MARK: - 辅助子视图

    @ViewBuilder
    private func metricBox(title: String, value: String, icon: String, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2.5) {
                Image(systemName: icon)
                    .font(.system(size: 8.5))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(subcardFill)
        )
    }

    @ViewBuilder
    private func metricRowCard(title: String, value: String, icon: String, iconColor: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 8.5))
                .foregroundColor(iconColor)
                .frame(width: 10)
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(subcardFill)
        )
    }
}

// MARK: - Widget Definition

@main
struct F50MonitorWidget: Widget {
    let kind = "F50MonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: F50StatusProvider()) { entry in
            F50StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("F50 流量")
        .description("显示 F50 随身 WiFi 的套餐剩余、已用、当日与本月流量")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
        .widgetContentMarginsDisabled()
    }
}

// MARK: - iOS 17+ Widget 背景适配

private extension WidgetConfiguration {
    func widgetContentMarginsDisabled() -> some WidgetConfiguration {
        if #available(iOSApplicationExtension 17.0, iOS 17.0, *) {
            return self.contentMarginsDisabled()
        } else {
            return self
        }
    }
}

private extension View {
    @ViewBuilder
    func widgetContainerBackground(colorScheme: ColorScheme) -> some View {
        let bg = colorScheme == .dark
            ? Color(red: 0.08, green: 0.10, blue: 0.13)
            : Color.white

        if #available(iOSApplicationExtension 17.0, iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                bg
            }
            .padding(.horizontal, 14.5)
            .padding(.vertical, 13.5)
        } else {
            self.padding(.horizontal, 14.5)
                .padding(.vertical, 13.5)
                .background(bg)
        }
    }
}

// MARK: - Xcode Canvas 所见即所得实时预览 (SwiftUI Previews)

#if DEBUG
extension F50Status {
    static var previewSample: F50Status {
        var s = F50Status()
        s.isOnline = true
        s.carrier = "中国移动"
        s.networkType = "5G SA"
        s.currentBands = "n41"
        s.signalBar = 4
        s.trafficLimit = 350 * 1024 * 1024 * 1024 // 350 GB
        s.packageRx = UInt64(Double(350 - 176.78) * 1024 * 1024 * 1024) // 剩余 176.78 GB (51%)
        s.dailyRx = UInt64(20.87 * 1024 * 1024 * 1024) // 20.87 GB
        s.monthlyRx = UInt64(40.98 * 1024 * 1024 * 1024) // 40.98 GB
        s.trafficResetDay = Calendar.current.component(.day, from: Date()) + 2
        s.connectedDevices = 0
        s.rsrp = "-88 dBm"
        s.snr = "21 dB"
        s.rsrq = "-10 dB"
        s.temperature = 42.5
        return s
    }
}

struct F50WidgetCanvasInspector_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // 1. 小尺寸 (深色)
            F50StatusWidgetView(entry: F50StatusEntry(date: Date(), status: .previewSample))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("小尺寸 - 深色")
                .environment(\.colorScheme, .dark)

            // 2. 小尺寸 (浅色)
            F50StatusWidgetView(entry: F50StatusEntry(date: Date(), status: .previewSample))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("小尺寸 - 浅色")
                .environment(\.colorScheme, .light)

            // 3. 中尺寸 (深色)
            F50StatusWidgetView(entry: F50StatusEntry(date: Date(), status: .previewSample))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("中尺寸 - 深色")
                .environment(\.colorScheme, .dark)

            // 4. 中尺寸 (浅色)
            F50StatusWidgetView(entry: F50StatusEntry(date: Date(), status: .previewSample))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("中尺寸 - 浅色")
                .environment(\.colorScheme, .light)
        }
    }
}
#endif
