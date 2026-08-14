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
        if let status, status.isOnline {
            switch family {
            case .systemSmall:
                smallView(status)
            case .systemMedium:
                mediumView(status)
            default:
                mediumView(status)
            }
        } else {
            offlineView
        }
    }

    // MARK: 离线 / 无数据

    private var offlineView: some View {
        VStack(spacing: 6) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("F50 未连接")
                .font(.subheadline.weight(.semibold))
            Text("打开 F50 Monitor 同步状态")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: 小尺寸

    private func smallView(_ status: F50Status) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text(status.networkType)
                    .font(.caption.weight(.bold))
                Spacer()
                signalDots(status)
            }
            Spacer()
            speedText("⬇", value: status.dlSpeed, color: .green)
            speedText("⬆", value: status.ulSpeed, color: .blue)
            Spacer()
            let used = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
            VStack(alignment: .leading, spacing: 3) {
                Text("\(F50Status.formatBytes(used)) / \(F50Status.formatBytes(status.trafficLimit > 0 ? status.trafficLimit : used))")
                    .font(.caption2.monospaced())
                if status.trafficLimit > 0 {
                    ProgressView(value: status.trafficUsageRatio)
                        .tint(status.trafficUsageColor)
                }
            }
        }
    }

    // MARK: 中/大尺寸

    private func mediumView(_ status: F50Status) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundColor(.blue)
                Text(status.networkType)
                    .font(.headline)
                Text(status.carrier)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if status.temperature > 0 {
                    Text("\(String(format: "%.0f", status.temperature))℃")
                        .font(.caption.monospaced())
                        .foregroundColor(status.tempColor)
                }
                Spacer()
                signalDots(status)
            }

            HStack(spacing: 12) {
                speedColumn("下载", speed: status.dlSpeed, color: .green)
                speedColumn("上传", speed: status.ulSpeed, color: .blue)
            }

            let used = status.packageTotal > 0 ? status.packageTotal : status.monthlyTotal
            HStack {
                Text("套餐 \(F50Status.formatBytes(used))")
                    .font(.caption.monospaced())
                Spacer()
                Text("本月 \(F50Status.formatBytes(status.ufiMonthlyUsage > 0 ? status.ufiMonthlyUsage : status.monthlyTotal))")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
            }
            if status.trafficLimit > 0 {
                ProgressView(value: status.trafficUsageRatio)
                    .tint(status.trafficUsageColor)
            }
        }
    }

    // MARK: 子组件

    private func signalDots(_ status: F50Status) -> some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...5, id: \.self) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(bar <= status.signalBar ? Color.green : Color.gray.opacity(0.25))
                    .frame(width: 3, height: CGFloat(bar * 2 + 1))
            }
        }
    }

    private func speedText(_ arrow: String, value: Double, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(arrow)
                .foregroundColor(color)
            Text(F50Status.formatSpeed(value))
                .font(.caption.monospaced())
        }
    }

    private func speedColumn(_ title: String, speed: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(F50Status.formatSpeed(speed))
                .font(.caption.monospaced())
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .configurationDisplayName("F50 状态")
        .description("显示 F50 随身 WiFi 的信号、速度与套餐流量状态")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
