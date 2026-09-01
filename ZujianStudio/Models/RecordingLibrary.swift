import Foundation
import WatchConnectivity

struct StoredRecording: Identifiable, Equatable {
    let document: AppRecordingDocument
    let fileURL: URL

    var id: UUID { document.id }
}

@MainActor
final class RecordingLibrary: NSObject, ObservableObject {
    @Published private(set) var recordings: [StoredRecording] = []
    @Published private(set) var connectionText = "正在连接 Apple Watch…"
    @Published var errorMessage: String?

    private let fileManager: FileManager
    private let directoryURL: URL
    private let session: WCSession?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZujianStudio/Recordings", isDirectory: true)
        if WCSession.isSupported() {
            session = .default
        } else {
            session = nil
        }
        super.init()

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }

        session?.delegate = self
        session?.activate()
        updateConnectionText()
    }

    func recording(id: UUID) -> StoredRecording? {
        recordings.first { $0.id == id }
    }

    func delete(_ recording: StoredRecording) {
        do {
            if fileManager.fileExists(atPath: recording.fileURL.path) {
                try fileManager.removeItem(at: recording.fileURL)
            }
            try reload()
        } catch {
            errorMessage = "删除录制失败：\(error.localizedDescription)"
        }
    }

    func importFile(at sourceURL: URL) {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: sourceURL)
            try store(data: data, preferredFilename: sourceURL.lastPathComponent)
            try reload()
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
        }
    }

    private func receive(data: Data, preferredFilename: String?) {
        do {
            try store(data: data, preferredFilename: preferredFilename)
            try reload()
            connectionText = "已收到 Apple Watch 录制"
        } catch {
            errorMessage = "接收录制失败：\(error.localizedDescription)"
        }
    }

    private func store(data: Data, preferredFilename: String?) throws {
        let document = try RecordingFileCodec.decode(data)
        let filename: String
        if let preferredFilename,
           preferredFilename.lowercased().hasSuffix(".json") {
            filename = preferredFilename
        } else {
            filename = document.suggestedFilename
        }
        var destination = directoryURL.appendingPathComponent(filename)
        if let existing = recordings.first(where: { $0.id == document.id }) {
            destination = existing.fileURL
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    private func reload() throws {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        recordings = urls.compactMap { url in
            guard url.pathExtension.lowercased() == "json",
                  let data = try? Data(contentsOf: url),
                  let document = try? RecordingFileCodec.decode(data) else {
                return nil
            }
            return StoredRecording(document: document, fileURL: url)
        }
        .sorted { $0.document.createdAt > $1.document.createdAt }
    }

    private func updateConnectionText() {
        guard let session else {
            connectionText = "此设备不支持 WatchConnectivity，可手动导入 JSON"
            return
        }
        guard session.activationState == .activated else {
            connectionText = "正在连接 Apple Watch…"
            return
        }
        guard session.isPaired else {
            connectionText = "未配对 Apple Watch，也可以手动导入 JSON"
            return
        }
        guard session.isWatchAppInstalled else {
            connectionText = "请先在配对的 Apple Watch 安装组间"
            return
        }
        connectionText = session.isReachable
            ? "Apple Watch 已连接"
            : "等待 Apple Watch 后台传输"
    }
}

extension RecordingLibrary: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.connectionText = "连接失败：\(error.localizedDescription)"
            } else {
                self?.updateConnectionText()
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.updateConnectionText()
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let filename = file.metadata?["filename"] as? String ?? file.fileURL.lastPathComponent
        do {
            let data = try Data(contentsOf: file.fileURL)
            Task { @MainActor [weak self] in
                self?.receive(data: data, preferredFilename: filename)
            }
        } catch {
            Task { @MainActor [weak self] in
                self?.errorMessage = "读取 Watch 录制失败：\(error.localizedDescription)"
            }
        }
    }
}
