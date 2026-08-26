import AppKit
import F50Core
import Foundation
import NetFS
import SwiftUI
import UniformTypeIdentifiers

enum FileSharingPreferences {
    static let enabledDefaultsKey = "F50_FileSharingEnabled"
}

private struct FileShareEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    let size: Int64?
    let modifiedAt: Date?

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

@MainActor
private final class FileShareManager: ObservableObject {
    @Published private(set) var currentDirectory: URL?
    @Published private(set) var entries: [FileShareEntry] = []
    @Published private(set) var isConnecting = false
    @Published private(set) var isTransferring = false
    @Published var errorMessage: String?

    private var rootDirectory: URL?
    private var shareURL: URL?

    var canGoBack: Bool {
        guard let rootDirectory, let currentDirectory else { return false }
        return currentDirectory.standardizedFileURL != rootDirectory.standardizedFileURL
    }

    func connect(to url: URL) {
        if shareURL == url, currentDirectory != nil {
            refresh()
            return
        }

        shareURL = url
        rootDirectory = nil
        currentDirectory = nil
        entries = []
        errorMessage = nil
        isConnecting = true

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.mount(url)
            }.value

            isConnecting = false
            guard shareURL == url else { return }

            switch result {
            case let .success(mountURL):
                rootDirectory = mountURL
                currentDirectory = mountURL
                refresh()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func open(_ entry: FileShareEntry) {
        guard entry.isDirectory else {
            NSWorkspace.shared.open(entry.url)
            return
        }
        currentDirectory = entry.url
        refresh()
    }

    func goBack() {
        guard canGoBack, let currentDirectory else { return }
        self.currentDirectory = currentDirectory.deletingLastPathComponent()
        refresh()
    }

    func refresh() {
        guard let directory = currentDirectory else { return }
        errorMessage = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.loadEntries(in: directory)
            }.value

            guard currentDirectory == directory else { return }
            switch result {
            case let .success(entries):
                self.entries = entries
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func chooseFilesToUpload() {
        let panel = NSOpenPanel()
        panel.title = "选择要上传到 F50 的文件"
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        upload(panel.urls)
    }

    func upload(_ sourceURLs: [URL]) {
        guard let directory = currentDirectory, !sourceURLs.isEmpty else { return }
        isTransferring = true
        errorMessage = nil

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Self.copy(sourceURLs, to: directory)
            }.value

            isTransferring = false
            switch result {
            case .success:
                refresh()
            case let .failure(error):
                errorMessage = error.localizedDescription
            }
        }
    }

    func revealInFinder() {
        guard let currentDirectory else { return }
        NSWorkspace.shared.open(currentDirectory)
    }

    nonisolated private static func mount(_ shareURL: URL) -> Result<URL, Error> {
        if let mounted = mountedVolume(for: shareURL) {
            return .success(mounted)
        }

        var mountpoints: Unmanaged<CFArray>?
        let status = NetFSMountURLSync(
            shareURL as CFURL,
            nil,
            nil,
            nil,
            nil,
            nil,
            &mountpoints
        )

        guard status == 0 else {
            return .failure(NSError(
                domain: "F50FileShare",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "连接 F50 文件共享失败（错误 \(status)）"]
            ))
        }

        let paths = mountpoints?.takeRetainedValue() as? [String] ?? []
        guard let path = paths.first else {
            return .failure(NSError(
                domain: "F50FileShare",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "已连接共享，但没有找到可访问的目录。"]
            ))
        }
        return .success(URL(fileURLWithPath: path, isDirectory: true))
    }

    nonisolated private static func mountedVolume(for shareURL: URL) -> URL? {
        let keys: Set<URLResourceKey> = [.volumeURLForRemountingKey]
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []

        return volumes.first { volume in
            guard let remountURL = try? volume.resourceValues(forKeys: keys).volumeURLForRemounting else {
                return false
            }
            return remountURL.host?.caseInsensitiveCompare(shareURL.host ?? "") == .orderedSame
        }
    }

    nonisolated private static func loadEntries(in directory: URL) -> Result<[FileShareEntry], Error> {
        do {
            let keys: Set<URLResourceKey> = [
                .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey
            ]
            let urls = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            let entries = try urls.map { url -> FileShareEntry in
                let values = try url.resourceValues(forKeys: keys)
                return FileShareEntry(
                    url: url,
                    isDirectory: values.isDirectory == true,
                    size: values.fileSize.map(Int64.init),
                    modifiedAt: values.contentModificationDate
                )
            }
            .sorted {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return .success(entries)
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func copy(_ sources: [URL], to directory: URL) -> Result<Void, Error> {
        do {
            for source in sources {
                let accessed = source.startAccessingSecurityScopedResource()
                defer { if accessed { source.stopAccessingSecurityScopedResource() } }

                let destination = availableDestination(for: source, in: directory)
                try FileManager.default.copyItem(at: source, to: destination)
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func availableDestination(for source: URL, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var destination = directory.appendingPathComponent(source.lastPathComponent)
        guard fileManager.fileExists(atPath: destination.path) else { return destination }

        let extensionName = source.pathExtension
        let baseName = source.deletingPathExtension().lastPathComponent
        var suffix = 2
        repeat {
            let candidateName = extensionName.isEmpty
                ? "\(baseName) \(suffix)"
                : "\(baseName) \(suffix).\(extensionName)"
            destination = directory.appendingPathComponent(candidateName)
            suffix += 1
        } while fileManager.fileExists(atPath: destination.path)
        return destination
    }
}

private struct FileShareView: View {
    @ObservedObject var manager: FileShareManager
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button(action: manager.goBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!manager.canGoBack)

            Image(systemName: "externaldrive.connected.to.line.below")
                .foregroundColor(F50Theme.blue)
            Text(manager.currentDirectory?.lastPathComponent ?? "F50 文件共享")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Button(action: manager.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(manager.currentDirectory == nil)

            Button(action: manager.chooseFilesToUpload) {
                Label("上传", systemImage: "square.and.arrow.up")
            }
            .disabled(manager.currentDirectory == nil || manager.isTransferring)

        }
        .buttonStyle(.bordered)
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if manager.isConnecting {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在连接 F50 文件共享…")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if manager.currentDirectory == nil {
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.xmark")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text(manager.errorMessage ?? "无法打开文件共享")
                    .foregroundColor(.secondary)
                Button("在 Finder 中尝试打开") {
                    manager.openInFinderFallback()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(manager.entries) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                        .foregroundColor(entry.isDirectory ? F50Theme.blue : .secondary)
                        .frame(width: 20)
                    Text(entry.name)
                        .lineLimit(1)
                    Spacer()
                    if !entry.isDirectory, let size = entry.size {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    if let modifiedAt = entry.modifiedAt {
                        Text(modifiedAt, style: .date)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    manager.open(entry)
                }
                .onDrag {
                    NSItemProvider(contentsOf: entry.url)
                        ?? NSItemProvider(object: entry.url as NSURL)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(F50Theme.blue, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(8)
                    .opacity(isDropTargeted ? 1 : 0)
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                loadDroppedFiles(providers)
                return true
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if manager.isTransferring {
                ProgressView().controlSize(.small)
                Text("正在上传…")
            } else {
                Image(systemName: "arrow.left.arrow.right")
                Text("从 Finder 拖入以上传；将文件拖到 Finder 即可下载")
            }
            Spacer()
            if let errorMessage = manager.errorMessage, manager.currentDirectory != nil {
                Text(errorMessage)
                    .foregroundColor(F50Theme.red)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private func loadDroppedFiles(_ providers: [NSItemProvider]) {
        Task {
            var urls: [URL] = []
            for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await loadFileURL(provider) {
                    urls.append(url)
                }
            }
            manager.upload(urls)
        }
    }

    private func loadFileURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                continuation.resume(returning: data.flatMap { URL(dataRepresentation: $0, relativeTo: nil) })
            }
        }
    }
}

private extension FileShareManager {
    func openInFinderFallback() {
        guard let shareURL else { return }
        NSWorkspace.shared.open(shareURL)
    }
}

@MainActor
final class FileShareWindowController: NSObject, NSWindowDelegate {
    private let manager = FileShareManager()
    private var window: NSWindow?

    func show(baseURLString: String) {
        guard let shareURL = F50Configuration.fileShareURL(from: baseURLString) else { return }

        if window == nil {
            let controller = NSHostingController(rootView: FileShareView(manager: manager))
            let window = NSWindow(contentViewController: controller)
            window.title = "F50 文件共享"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 520))
            window.minSize = NSSize(width: 640, height: 420)
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }

        manager.connect(to: shareURL)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
