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

// MARK: - Widget View

struct F50StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: F50StatusEntry

    private var status: F50Status? { entry.status }

    var body: some View {
        widgetContent
            .widgetContainerBackground()
    }

    @ViewBuilder
    private var widgetContent: some View {
        if let status, status.isOnline {
            switch family {
            case .systemSmall:
                smallView(status)
            case .systemMedium:
                mediumView(status)
            case .systemLarge, .systemExtraLarge:
                largeView(status)
            case .accessoryRectangular:
                accessoryRectangularView(status)
            case .accessoryCircular:
                accessoryCircularView(status)
            case .accessoryInline:
                accessoryInlineView(status)
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
        VStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 26))
                .foregroundColor(F50Theme.orange)
            Text("F50 未连接")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text("打开 App 同步状态")
                .font(.caption2)
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

    // MARK: 小尺寸小组件 (systemSmall)

    @ViewBuilder
    private func smallView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        let daily = status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal
        let monthly = status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal

        VStack(alignment: .leading, spacing: 6) {
            // 头部：运营商 Logo / 网络制式 + 频段 + 信号格
            HStack(spacing: 4) {
                if let logo = carrierLogoAssetName(for: status) {
                    Image(logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                }
                Text(status.networkType)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if !status.currentBands.isEmpty {
                    Text(status.currentBands)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(F50Theme.purple)
                }
                Spacer(minLength: 2)
                signalDots(status)
            }

            // 套餐流量核心信息
            VStack(alignment: .leading, spacing: 2) {
                Text("套餐已用")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(F50Status.formatBytes(packageUsed))
                        .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 2)

                    if status.trafficLimit > 0 {
                        Text("/ " + F50Status.formatBytes(status.trafficLimit))
                            .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                if status.trafficLimit > 0 {
                    ProgressView(value: status.trafficUsageRatio)
                        .tint(status.trafficUsageColor)
                        .frame(height: 3)
                        .padding(.vertical, 1)

                    HStack {
                        Text(String(format: "%.0f%% 已用", status.trafficUsageRatio * 100))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(status.trafficUsageColor)
                        Spacer(minLength: 2)
                        if let days = status.daysUntilReset {
                            Text(days == 0 ? "今天重置" : "\(days)天后重置")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                } else if let days = status.daysUntilReset {
                    HStack {
                        Spacer()
                        Text(days == 0 ? "今天重置" : "\(days)天后重置")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            // 当日流量 & 本月已用（底部双指标卡片）
            HStack(spacing: 5) {
                trafficMiniBox(title: "当日流量", value: daily, iconColor: F50Theme.orange, icon: "sun.max.fill")
                trafficMiniBox(title: "本月已用", value: monthly, iconColor: F50Theme.purple, icon: "calendar")
            }
        }
    }

    // MARK: 中尺寸小组件 (systemMedium)

    @ViewBuilder
    private func mediumView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        let daily = status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal
        let monthly = status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal

        VStack(alignment: .leading, spacing: 8) {
            // 头部：运营商 Logo / 名称 + 制式 + 频段 + 重置天数 + 信号
            HStack(spacing: 5) {
                if let logo = carrierLogoAssetName(for: status) {
                    Image(logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                }
                if !status.carrier.isEmpty && status.carrier != "未知" {
                    Text(status.carrier)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }

                Text(status.networkType)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(F50Theme.blue.opacity(0.1)))
                    .foregroundColor(F50Theme.blue)

                if !status.currentBands.isEmpty {
                    Text(status.currentBands)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundColor(.primary)
                }

                Spacer(minLength: 4)

                if let days = status.daysUntilReset {
                    Text(days == 0 ? "今天重置" : "\(days)天后重置")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                signalDots(status)
            }

            // 套餐用量核心进度条区域
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 4) {
                        Text("已用流量")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatBytes(packageUsed))
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    if status.trafficLimit > 0 {
                        let remaining = status.trafficLimit > packageUsed ? status.trafficLimit - packageUsed : 0
                        Text("剩余 \(F50Status.formatBytes(remaining))  /  共 \(F50Status.formatBytes(status.trafficLimit))")
                            .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }

                if status.trafficLimit > 0 {
                    ProgressView(value: status.trafficUsageRatio)
                        .tint(status.trafficUsageColor)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))

            // 底部 4 个累计与设备指标卡片（当日流量, 本月已用, 签约等级/使用率, Wi-Fi 连接设备）
            HStack(spacing: 6) {
                trafficMetricCard(
                    title: "当日流量",
                    value: F50Status.formatBytes(daily),
                    subtext: "今日累计",
                    iconColor: F50Theme.orange,
                    icon: "sun.max.fill"
                )

                trafficMetricCard(
                    title: "本月已用",
                    value: F50Status.formatBytes(monthly),
                    subtext: "本月累计",
                    iconColor: F50Theme.purple,
                    icon: "calendar"
                )

                trafficMetricCard(
                    title: status.trafficLimit > 0 ? "套餐使用率" : "签约状态",
                    value: status.trafficLimit > 0 ? String(format: "%.0f%%", status.trafficUsageRatio * 100) : (!status.qci.isEmpty ? "QCI \(status.qci)" : "正常"),
                    subtext: status.trafficLimit > 0 ? "已用占比" : "网络 QoS",
                    iconColor: status.trafficLimit > 0 ? status.trafficUsageColor : F50Theme.cyan,
                    icon: status.trafficLimit > 0 ? "chart.pie.fill" : "antenna.radiowaves.left.and.right"
                )

                trafficMetricCard(
                    title: "连接设备",
                    value: "\(status.connectedDevices) 台",
                    subtext: "Wi-Fi 接入",
                    iconColor: F50Theme.blue,
                    icon: "wifi"
                )
            }
        }
    }

    // MARK: 大尺寸小组件 (systemLarge)

    @ViewBuilder
    private func largeView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        let daily = status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal
        let monthly = status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal

        VStack(alignment: .leading, spacing: 10) {
            // 1. 头部：运营商 Logo / 名称 + 制式 + 频段 + 信号 + 重置天数
            HStack(spacing: 6) {
                if let logo = carrierLogoAssetName(for: status) {
                    Image(logo)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                }
                if !status.carrier.isEmpty && status.carrier != "未知" {
                    Text(status.carrier)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .lineLimit(1)
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

                Spacer(minLength: 4)

                if let days = status.daysUntilReset {
                    Text(days == 0 ? "今天重置" : "\(days)天后重置")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundColor(.secondary)
                }

                signalDots(status)
            }

            // 2. 套餐流量卡片
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("已用流量：\(F50Status.formatBytes(packageUsed))")
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                    Spacer()
                    if status.trafficLimit > 0 {
                        Text("总流量：\(F50Status.formatBytes(status.trafficLimit))")
                            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }

                if status.trafficLimit > 0 {
                    ProgressView(value: status.trafficUsageRatio)
                        .tint(status.trafficUsageColor)
                        .frame(height: 4)

                    HStack {
                        Text(String(format: "%.0f%% 已使用", status.trafficUsageRatio * 100))
                            .font(.caption2.weight(.bold))
                            .foregroundColor(status.trafficUsageColor)
                        Spacer()
                        let remaining = status.trafficLimit > packageUsed ? status.trafficLimit - packageUsed : 0
                        Text("剩余 \(F50Status.formatBytes(remaining))")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))

            // 3. 蜂窝信号指标 (RSRP, SINR, RSRQ)
            HStack(spacing: 6) {
                widgetSignalCell(title: "RSRP", value: status.rsrp, quality: status.rsrpQuality)
                widgetSignalCell(title: "SINR / SNR", value: status.snr, quality: status.snrQuality)
                widgetSignalCell(title: "RSRQ", value: status.rsrq, quality: status.rsrqQuality)
            }

            // 4. 4 个统计指标
            HStack(spacing: 6) {
                trafficMetricCard(title: "当日流量", value: F50Status.formatBytes(daily), subtext: "今日累计", iconColor: F50Theme.orange, icon: "sun.max.fill")
                trafficMetricCard(title: "本月已用", value: F50Status.formatBytes(monthly), subtext: "本月累计", iconColor: F50Theme.purple, icon: "calendar")
                trafficMetricCard(title: "连接设备", value: "\(status.connectedDevices) 台", subtext: "Wi-Fi 接入", iconColor: F50Theme.blue, icon: "wifi")
                trafficMetricCard(title: "签约 QCI", value: !status.qci.isEmpty ? "QCI \(status.qci)" : "标准", subtext: "QoS 等级", iconColor: F50Theme.cyan, icon: "antenna.radiowaves.left.and.right")
            }
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

    // MARK: 子组件

    @ViewBuilder
    private func signalDots(_ status: F50Status) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...5, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= status.signalBar ? F50Theme.green : Color.primary.opacity(0.12))
                    .frame(width: 3, height: CGFloat(Double(bar) * 2.2 + 2))
            }
        }
    }

    @ViewBuilder
    private func trafficMiniBox(title: String, value: UInt64, iconColor: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(F50Status.formatBytes(value))
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    @ViewBuilder
    private func trafficMetricCard(title: String, value: String, subtext: String?, iconColor: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtext = subtext {
                Text(subtext)
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    @ViewBuilder
    private func widgetSignalCell(title: String, value: String, quality: (label: String, color: Color, ratio: Double)) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
            ProgressView(value: quality.ratio)
                .tint(quality.color)
                .frame(height: 2.5)
            Text(quality.label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(quality.color)
        }
        .frame(maxWidth: .infinity)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }
}

// MARK: - Widget

@main
struct F50MonitorWidget: Widget {
    let kind = "F50MonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: F50StatusProvider()) { entry in
            F50StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("F50 流量")
        .description("显示 F50 随身 WiFi 的套餐已用、总量、当日与本月流量")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryRectangular,
            .accessoryCircular,
            .accessoryInline
        ])
        .widgetContentMarginsDisabled()
    }
}

// MARK: - iOS 17+ 适配

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
    func widgetContainerBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                Color(.secondarySystemGroupedBackground)
            }
            .padding(12)
        } else {
            self.padding(12)
                .background(Color(.secondarySystemGroupedBackground))
        }
    }
}
