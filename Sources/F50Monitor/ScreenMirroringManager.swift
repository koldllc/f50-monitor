import Foundation
import F50Core
import AppKit
import Combine

@MainActor
public final class ScreenMirroringManager: ObservableObject {
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: F50Configuration.screenMirroringEnabledDefaultsKey)
        }
    }
    
    @Published public var adbPort: Int {
        didSet {
            UserDefaults.standard.set(adbPort, forKey: F50Configuration.screenMirroringPortDefaultsKey)
        }
    }
    
    @Published public private(set) var hasAdb: Bool = false
    @Published public private(set) var hasScrcpy: Bool = false
    @Published public private(set) var hasBrew: Bool = false
    
    @Published public private(set) var adbPath: String?
    @Published public private(set) var scrcpyPath: String?
    @Published public private(set) var brewPath: String?
    
    @Published public private(set) var isDownloadingDependencies: Bool = false
    @Published public private(set) var installStatusMessage: String?
    @Published public private(set) var isConnecting: Bool = false
    @Published public private(set) var statusMessage: String?
    
    @Published public var showPermissionAlert: Bool = false

    public var isDependenciesInstalled: Bool {
        hasAdb && hasScrcpy
    }

    private var toolsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("F50Monitor/Tools", isDirectory: true)
    }

    public init() {
        if UserDefaults.standard.object(forKey: F50Configuration.screenMirroringEnabledDefaultsKey) == nil {
            self.isEnabled = true
        } else {
            self.isEnabled = UserDefaults.standard.bool(forKey: F50Configuration.screenMirroringEnabledDefaultsKey)
        }
        
        let savedPort = UserDefaults.standard.integer(forKey: F50Configuration.screenMirroringPortDefaultsKey)
        self.adbPort = savedPort > 0 ? savedPort : F50Configuration.defaultADBPort
        
        checkDependencies()
    }
    
    public func checkDependencies() {
        // 异步检测：Process 查找/which 调用放在后台执行器，避免阻塞主线程（App 启动、设置页打开）
        let toolsDir = toolsDirectory
        Task {
            let result = await Self.detectTools(toolsDir: toolsDir)
            adbPath = result.adb
            hasAdb = result.adb != nil
            scrcpyPath = result.scrcpy
            hasScrcpy = result.scrcpy != nil
            brewPath = result.brew
            hasBrew = result.brew != nil
        }
    }

    nonisolated private static func detectTools(toolsDir: URL) async -> (adb: String?, scrcpy: String?, brew: String?) {
        let fm = FileManager.default
        let localAdb = toolsDir.appendingPathComponent("adb").path
        let localScrcpy = toolsDir.appendingPathComponent("scrcpy").path

        let adb: String?
        if fm.isExecutableFile(atPath: localAdb) {
            adb = localAdb
        } else {
            adb = findExecutable("adb", extraPaths: ["/opt/homebrew/bin/adb", "/usr/local/bin/adb"])
        }

        let scrcpy: String?
        if fm.isExecutableFile(atPath: localScrcpy) {
            scrcpy = localScrcpy
        } else {
            scrcpy = findExecutable("scrcpy", extraPaths: ["/opt/homebrew/bin/scrcpy", "/usr/local/bin/scrcpy"])
        }

        let brew = findExecutable("brew", extraPaths: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"])
        return (adb, scrcpy, brew)
    }

    nonisolated private static func findExecutable(_ name: String, extraPaths: [String]) -> String? {
        let fm = FileManager.default
        for path in extraPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        let searchDirs = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        for dir in searchDirs {
            let fullPath = (dir as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env
        
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = path, !path.isEmpty, fm.isExecutableFile(atPath: path) {
                    return path
                }
            }
        } catch {}
        
        return nil
    }
    
    public func requestInstallDependencies() {
        showPermissionAlert = true
    }
    
    public func downloadAndInstallStandaloneDependencies() {
        isDownloadingDependencies = true
        installStatusMessage = "正在准备在线获取投屏组件包..."
        
        #if arch(arm64)
        let archStr = "aarch64"
        #else
        let archStr = "x86_64"
        #endif
        
        let downloadURLString = "https://github.com/Genymobile/scrcpy/releases/download/v4.1/scrcpy-macos-\(archStr)-v4.1.tar.gz"
        guard let url = URL(string: downloadURLString) else {
            isDownloadingDependencies = false
            installStatusMessage = "下载地址无效"
            return
        }
        
        let destinationToolsDir = toolsDirectory
        
        Task.detached {
            do {
                let fm = FileManager.default
                try fm.createDirectory(at: destinationToolsDir, withIntermediateDirectories: true, attributes: nil)
                
                let tarballURL = destinationToolsDir.appendingPathComponent("scrcpy-bundle.tar.gz")
                
                await MainActor.run {
                    self.installStatusMessage = "正在自动下载 scrcpy 与 ADB 组件..."
                }
                
                let (tempURL, response) = try await URLSession.shared.download(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw NSError(domain: "DownloadError", code: 404, userInfo: [NSLocalizedDescriptionKey: "组件包下载失败 (HTTP \( (response as? HTTPURLResponse)?.statusCode ?? 0 ))"])
                }
                
                if fm.fileExists(atPath: tarballURL.path) {
                    try fm.removeItem(at: tarballURL)
                }
                try fm.moveItem(at: tempURL, to: tarballURL)
                
                await MainActor.run {
                    self.installStatusMessage = "正在自动解压并配置..."
                }
                
                let tarProcess = Process()
                tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
                tarProcess.arguments = ["-xzf", tarballURL.path, "-C", destinationToolsDir.path, "--strip-components=1"]
                try tarProcess.run()
                tarProcess.waitUntilExit()
                
                try? fm.removeItem(at: tarballURL)
                
                let chmodProcess = Process()
                chmodProcess.executableURL = URL(fileURLWithPath: "/bin/chmod")
                chmodProcess.arguments = ["+x",
                    destinationToolsDir.appendingPathComponent("adb").path,
                    destinationToolsDir.appendingPathComponent("scrcpy").path
                ]
                try? chmodProcess.run()
                chmodProcess.waitUntilExit()
                
                let xattrProcess = Process()
                xattrProcess.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
                xattrProcess.arguments = ["-dr", "com.apple.quarantine", destinationToolsDir.path]
                try? xattrProcess.run()
                xattrProcess.waitUntilExit()
                
                await MainActor.run {
                    self.isDownloadingDependencies = false
                    self.checkDependencies()
                    if self.isDependenciesInstalled {
                        self.installStatusMessage = "投屏独立组件已成功配置完成！"
                    } else {
                        self.installStatusMessage = "组件解压完成，但未找到可执行文件。"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isDownloadingDependencies = false
                    self.installStatusMessage = "下载安装失败：\(error.localizedDescription)"
                }
            }
        }
    }
    
    public func extractHost(from baseURLString: String) -> String? {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return host
        }
        let components = trimmed.components(separatedBy: "/")
        for comp in components {
            let hostPart = comp.components(separatedBy: ":").first ?? ""
            if !hostPart.isEmpty && hostPart.contains(".") {
                return hostPart
            }
        }
        return nil
    }
    
    public func startMirroring(baseURLString: String, completion: ((Bool, String) -> Void)? = nil) {
        guard isDependenciesInstalled else {
            let msg = "未检测到投屏必要依赖 (adb / scrcpy)"
            statusMessage = msg
            requestInstallDependencies()
            completion?(false, msg)
            return
        }
        
        guard let host = extractHost(from: baseURLString), !host.isEmpty else {
            let msg = "无法从后台地址提取有效设备 IP"
            statusMessage = msg
            completion?(false, msg)
            return
        }
        
        let targetAddress = "\(host):\(adbPort)"
        isConnecting = true
        statusMessage = "正在通过 ADB 连接设备 (\(targetAddress))..."
        
        let adb = adbPath ?? "/opt/homebrew/bin/adb"
        let scrcpy = scrcpyPath ?? "/opt/homebrew/bin/scrcpy"
        
        Task.detached {
            // 1. adb connect <host>:<port>
            let connectProcess = Process()
            connectProcess.executableURL = URL(fileURLWithPath: adb)
            connectProcess.arguments = ["connect", targetAddress]
            
            var environment = ProcessInfo.processInfo.environment
            let toolDirStr = (adb as NSString).deletingLastPathComponent
            environment["PATH"] = "\(toolDirStr):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            connectProcess.environment = environment
            
            let pipe = Pipe()
            connectProcess.standardOutput = pipe
            connectProcess.standardError = pipe
            
            do {
                try connectProcess.run()
                connectProcess.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
                
                let isConnected = output.contains("connected to") || output.contains("already connected")
                
                if !isConnected {
                    await MainActor.run {
                        self.isConnecting = false
                        let msg = "ADB 连接失败: \(trimmedOutput)"
                        self.statusMessage = msg
                        completion?(false, msg)
                    }
                    return
                }
                
                await MainActor.run {
                    self.statusMessage = "ADB 已连接，正在启动 scrcpy 投屏..."
                }
                
                // 2. Launch scrcpy --no-audio -s <targetAddress>
                let scrcpyProcess = Process()
                scrcpyProcess.executableURL = URL(fileURLWithPath: scrcpy)
                scrcpyProcess.arguments = ["-s", targetAddress, "--no-audio"]
                scrcpyProcess.environment = environment
                
                try scrcpyProcess.run()
                
                await MainActor.run {
                    self.isConnecting = false
                    self.statusMessage = "投屏窗口已打开！"
                    completion?(true, "投屏窗口已打开！")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                        if self?.statusMessage == "投屏窗口已打开！" {
                            self?.statusMessage = nil
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self.isConnecting = false
                    let msg = "启动投屏失败: \(error.localizedDescription)"
                    self.statusMessage = msg
                    completion?(false, msg)
                }
            }
        }
    }
    
    public func clearStatusMessage() {
        statusMessage = nil
    }
}
