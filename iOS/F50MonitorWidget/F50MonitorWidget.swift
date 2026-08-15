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
            case .systemMedium, .systemLarge, .systemExtraLarge:
                mediumView(status)
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
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("F50 未连接")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text("打开 App 同步状态")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: 小尺寸小组件

    @ViewBuilder
    private func smallView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        let daily = status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal
        let monthly = status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal

        VStack(alignment: .leading, spacing: 6) {
            // 头部：网络制式 + 信号格
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10))
                    .foregroundColor(F50Theme.blue)
                Text(status.networkType)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 4)
                signalDots(status)
            }

            // 套餐已用核心数据（单行紧凑自适应，绝不换行）
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(F50Status.formatBytes(packageUsed))
                        .font(.system(size: 19, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 2)

                    if status.trafficLimit > 0 {
                        Text("/ " + F50Status.formatBytes(status.trafficLimit))
                            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                if status.trafficLimit > 0 {
                    ProgressView(value: status.trafficUsageRatio)
                        .tint(status.trafficUsageColor)
                        .frame(height: 3)

                    HStack {
                        Text(String(format: "%.1f%% 已用", status.trafficUsageRatio * 100))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(status.trafficUsageColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Spacer(minLength: 2)

                        if let days = status.daysUntilReset {
                            Text(days == 0 ? "今天重置" : "\(days)天后重置")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            // 当日流量 & 本月已用（底部双指标卡片，单行缩放不截断）
            HStack(spacing: 5) {
                trafficMiniBox(title: "当日", value: daily, color: F50Theme.orange, icon: "sun.max.fill")
                trafficMiniBox(title: "本月", value: monthly, color: F50Theme.purple, icon: "calendar")
            }
        }
    }

    // MARK: 中/大尺寸小组件

    @ViewBuilder
    private func mediumView(_ status: F50Status) -> some View {
        let packageUsed = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
        let daily = status.ufiDailyUsage > 0 ? status.ufiDailyUsage : status.dailyTotal
        let monthly = status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal

        VStack(alignment: .leading, spacing: 8) {
            // 头部：设备网络状态 + 重置天数 + 信号
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(F50Theme.blue)
                Text(status.networkType)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(status.carrier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let days = status.daysUntilReset {
                    Text(days == 0 ? "今天重置" : "\(days) 天后重置")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                signalDots(status)
            }

            // 套餐流量进度条
            if status.trafficLimit > 0 {
                ProgressView(value: status.trafficUsageRatio)
                    .tint(status.trafficUsageColor)
                    .frame(height: 3)
            }

            // 4个流量数据整合网格 (4列平铺，单行自适应缩放)
            HStack(spacing: 6) {
                trafficMetricCell(
                    title: "套餐已用",
                    value: F50Status.formatBytes(packageUsed),
                    subtext: status.trafficLimit > 0 ? String(format: "%.1f%%", status.trafficUsageRatio * 100) : nil,
                    color: F50Theme.cyan,
                    icon: "chart.bar.fill"
                )

                trafficMetricCell(
                    title: "套餐总量",
                    value: status.trafficLimit > 0 ? F50Status.formatBytes(status.trafficLimit) : "不限",
                    subtext: status.trafficLimit > 0 ? "总额度" : nil,
                    color: F50Theme.blue,
                    icon: "externaldrive.fill"
                )

                trafficMetricCell(
                    title: "当日已用",
                    value: F50Status.formatBytes(daily),
                    subtext: "今日累计",
                    color: F50Theme.orange,
                    icon: "sun.max.fill"
                )

                trafficMetricCell(
                    title: "本月已用",
                    value: F50Status.formatBytes(monthly),
                    subtext: "本月累计",
                    color: F50Theme.purple,
                    icon: "calendar"
                )
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
    private func trafficMiniBox(title: String, value: UInt64, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(F50Status.formatBytes(value))
                .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
    }

    @ViewBuilder
    private func trafficMetricCell(title: String, value: String, subtext: String?, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let subtext = subtext {
                Text(subtext)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(.tertiarySystemGroupedBackground)))
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
