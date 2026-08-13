import AppKit
import Combine
import CryptoKit
import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(version: String)
        case downloading(version: String)
        case installing(version: String)
        case failed(message: String)
    }

    private struct Release: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }
    }

    private struct Asset: Decodable {
        let name: String
        let downloadURL: URL
        let digest: String?

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case digest
        }
    }

    private struct AvailableUpdate {
        let version: String
        let asset: Asset
    }

    private enum UpdateError: LocalizedError {
        case invalidResponse
        case missingAsset
        case missingDigest
        case digestMismatch
        case invalidArchive
        case invalidApplication
        case unsupportedLaunchLocation
        case helperLaunchFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "无法读取版本信息"
            case .missingAsset: return "新版本缺少 F50.Monitor.zip"
            case .missingDigest: return "新版本缺少 SHA-256 校验值"
            case .digestMismatch: return "更新包完整性校验失败"
            case .invalidArchive: return "无法解压更新包"
            case .invalidApplication: return "更新包中的应用无效"
            case .unsupportedLaunchLocation: return "请从 F50 Monitor.app 启动后再更新"
            case .helperLaunchFailed: return "无法启动更新程序"
            }
        }
    }

    private static let releaseAPI = URL(string: "https://api.github.com/repos/kelvinsze/f50-monitor/releases/latest")!
    private static let expectedAssetName = "F50.Monitor.zip"
    private static let automaticUpdatesKey = "F50_AutomaticUpdates"

    @Published private(set) var state: State = .idle
    @Published var automaticallyInstallsUpdates: Bool {
        didSet {
            UserDefaults.standard.set(automaticallyInstallsUpdates, forKey: Self.automaticUpdatesKey)
        }
    }

    private var availableUpdate: AvailableUpdate?

    init() {
        if UserDefaults.standard.object(forKey: Self.automaticUpdatesKey) == nil {
            automaticallyInstallsUpdates = true
        } else {
            automaticallyInstallsUpdates = UserDefaults.standard.bool(forKey: Self.automaticUpdatesKey)
        }
    }

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    }

    var isBusy: Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var availableVersion: String? {
        guard case let .available(version) = state else { return nil }
        return version
    }

    var statusText: String {
        switch state {
        case .idle: return "自动检测 GitHub Releases"
        case .checking: return "正在检查新版本…"
        case .upToDate: return "当前已是最新版本"
        case let .available(version): return "发现新版本 v\(version)"
        case let .downloading(version): return "正在下载 v\(version)…"
        case let .installing(version): return "正在安装 v\(version)…"
        case let .failed(message): return message
        }
    }

    func checkForUpdates(installAutomatically: Bool? = nil) {
        guard !isBusy else { return }
        state = .checking

        Task {
            do {
                var request = URLRequest(url: Self.releaseAPI)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("F50-Monitor/\(currentVersion)", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    throw UpdateError.invalidResponse
                }

                let release = try JSONDecoder().decode(Release.self, from: data)
                let version = Self.normalizedVersion(release.tagName)
                guard Self.isVersion(version, newerThan: currentVersion) else {
                    availableUpdate = nil
                    state = .upToDate
                    return
                }

                guard let asset = release.assets.first(where: { $0.name == Self.expectedAssetName }) else {
                    throw UpdateError.missingAsset
                }

                availableUpdate = AvailableUpdate(version: version, asset: asset)
                state = .available(version: version)

                if installAutomatically ?? automaticallyInstallsUpdates {
                    installAvailableUpdate()
                }
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    func installAvailableUpdate() {
        guard let update = availableUpdate, !isBusy else { return }
        state = .downloading(version: update.version)

        Task {
            do {
                let stagedApplication = try await downloadAndPrepare(update)
                state = .installing(version: update.version)
                try launchInstaller(for: stagedApplication)
                NSApplication.shared.terminate(nil)
            } catch {
                state = .failed(message: error.localizedDescription)
            }
        }
    }

    private func downloadAndPrepare(_ update: AvailableUpdate) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: update.asset.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.invalidResponse
        }

        guard let expectedDigest = update.asset.digest?.lowercased(),
              expectedDigest.hasPrefix("sha256:") else {
            throw UpdateError.missingDigest
        }

        let archiveData = try Data(contentsOf: temporaryURL)
        let actualDigest = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard "sha256:\(actualDigest)" == expectedDigest else {
            throw UpdateError.digestMismatch
        }

        let stagingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("F50MonitorUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let archiveURL = stagingDirectory.appendingPathComponent(Self.expectedAssetName)
        try FileManager.default.copyItem(at: temporaryURL, to: archiveURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, stagingDirectory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.invalidArchive }

        let applicationURL = stagingDirectory.appendingPathComponent("F50 Monitor.app", isDirectory: true)
        guard let bundle = Bundle(url: applicationURL),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let stagedVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              Self.normalizedVersion(stagedVersion) == update.version else {
            throw UpdateError.invalidApplication
        }

        return applicationURL
    }

    private func launchInstaller(for stagedApplication: URL) throws {
        let installedApplication = Bundle.main.bundleURL
        guard installedApplication.pathExtension == "app" else {
            throw UpdateError.unsupportedLaunchLocation
        }

        let helperDirectory = stagedApplication.deletingLastPathComponent()
        let helperURL = helperDirectory.appendingPathComponent("install-update.sh")
        let script = """
        #!/bin/zsh
        set -eu
        pid="$1"
        source_app="$2"
        target_app="$3"
        backup_app="${target_app}.previous"

        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$backup_app"
        /bin/mv "$target_app" "$backup_app"
        if /usr/bin/ditto "$source_app" "$target_app"; then
            /bin/rm -rf "$backup_app"
            /usr/bin/open "$target_app"
        else
            /bin/rm -rf "$target_app"
            /bin/mv "$backup_app" "$target_app"
            /usr/bin/open "$target_app"
            exit 1
        fi
        /bin/rm -rf "$(/usr/bin/dirname "$source_app")"
        """
        try script.write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)

        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/zsh")
        helper.arguments = [helperURL.path, String(ProcessInfo.processInfo.processIdentifier), stagedApplication.path, installedApplication.path]
        do {
            try helper.run()
        } catch {
            throw UpdateError.helperLaunchFailed
        }
    }

    private static func normalizedVersion(_ version: String) -> String {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        normalizedVersion(current).compare(normalizedVersion(candidate), options: .numeric) == .orderedAscending
    }
}
