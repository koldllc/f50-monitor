import SwiftUI

public struct F50PanelView: View {
    @ObservedObject var fetcher: F50Fetcher
    var onOpenSettings: () -> Void
    
    public init(fetcher: F50Fetcher, onOpenSettings: @escaping () -> Void) {
        self.fetcher = fetcher
        self.onOpenSettings = onOpenSettings
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
    
    public var body: some View {
        VStack(spacing: 10) {
            // Header: Model & Connection Status
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                    Text("ZTE F50 5G MiFi")
                        .font(.system(size: 15, weight: .bold))
                }
                
                Spacer()
                
                // Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(fetcher.status.isOnline ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(fetcher.status.isOnline ? "在线" : "未在线")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.15)))
                
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
                            .foregroundColor(.orange)
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
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.12)))
            }
            
            // 1. Network & 3 Signal Metrics Card
            VStack(spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("蜂窝网络")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            Text(fetcher.status.networkType)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                            
                            if !fetcher.status.carrier.isEmpty && fetcher.status.carrier != "未知" {
                                Text(fetcher.status.carrier)
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.blue.opacity(0.15)))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Signal Bar Indicators (Bottom-aligned)
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(1...5, id: \.self) { bar in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(bar <= fetcher.status.signalBar ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 4, height: CGFloat(bar * 3 + 4))
                        }
                    }
                }
                
                // Subscription Status / QCI Line
                HStack(spacing: 6) {
                    Text("签约状态:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(subscriptionText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(subscriptionText == "无数据" ? .secondary : .primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.06)))
                
                Divider()
                
                // 3 Signal Values & Status Bars (Ordered: RSRP, SINR/SNR, RSRQ)
                HStack(spacing: 8) {
                    // Column 1: RSRP
                    VStack(spacing: 4) {
                        Text("RSRP")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(fetcher.status.rsrp)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        
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
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        
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
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                        
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
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时下载")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatSpeed(fetcher.status.dlSpeed))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.08)))
                
                // Upload Speed
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("实时上传")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(F50Status.formatSpeed(fetcher.status.ulSpeed))
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                    }
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.blue.opacity(0.08)))
            }
            
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
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
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
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(fetcher.status.tempColor)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(fetcher.status.tempColor.opacity(0.08)))
                    
                    // Connected Devices
                    HStack(spacing: 8) {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.purple)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("连接设备数")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("\(fetcher.status.connectedDevices) 台")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        Spacer()
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.purple.opacity(0.08)))
                }
            }
            
            Divider()
            
            // 4. Actions
            HStack(spacing: 10) {
                    // Open Web Dashboard Button
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
                    .tint(.blue)
                    
                    // Settings Button
                    Button(action: {
                        onOpenSettings()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                            Text("设置")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                    }
                    .buttonStyle(.bordered)
                    
                    // Quit Button
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                    }) {
                        Image(systemName: "power")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .padding(6)
                    }
                    .buttonStyle(.bordered)
                    .help("退出程序")
            }
        }
        .padding(16)
        .frame(width: 340, height: 450)
    }
}
