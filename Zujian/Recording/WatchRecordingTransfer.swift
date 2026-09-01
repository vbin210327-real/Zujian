#if DEBUG
import Foundation
import WatchConnectivity

final class WatchRecordingTransfer: NSObject, ObservableObject {
    static let shared = WatchRecordingTransfer()

    private let session: WCSession?
    private var pending: [(url: URL, completion: (String) -> Void)] = []
    private var completions: [URL: (String) -> Void] = [:]

    override private init() {
        if WCSession.isSupported() {
            session = .default
        } else {
            session = nil
        }
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func enqueue(_ fileURL: URL, completion: @escaping (String) -> Void) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            completion("录制文件已不存在")
            return
        }
        guard let session else {
            completion("已保存在手表；此设备不支持传输")
            return
        }
        pending.append((fileURL, completion))
        if session.activationState == .activated {
            flushPending()
        } else {
            session.activate()
            completion("已保存，正在启动手机传输")
        }
    }

    private func flushPending() {
        guard let session,
              session.activationState == .activated else { return }
        guard session.isCompanionAppInstalled else {
            pending.last?.completion("已保存在手表；请先安装 iPhone 素材台")
            return
        }

        let queued = pending
        pending.removeAll()
        for item in queued {
            completions[item.url] = item.completion
            session.transferFile(
                item.url,
                metadata: [
                    "kind": "zujian-app-recording",
                    "filename": item.url.lastPathComponent
                ]
            )
            item.completion("已排队发送到 iPhone")
        }
    }
}

extension WatchRecordingTransfer: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.pending.last?.completion("传输启动失败：\(error.localizedDescription)")
            } else if activationState == .activated {
                self?.flushPending()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.flushPending()
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let fileURL = fileTransfer.file.fileURL
        Task { @MainActor [weak self] in
            guard let completion = self?.completions.removeValue(forKey: fileURL) else { return }
            if let error {
                completion("发送失败，文件仍保存在手表：\(error.localizedDescription)")
            } else {
                completion("已发送到 iPhone 素材台")
            }
        }
    }
}
#endif
