#if DEBUG
import Foundation

final class DetectionDiagnosticRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var message: String?

    private struct Vector: Codable, Sendable {
        let x: Double
        let y: Double
        let z: Double

        init(_ value: MotionVector3) {
            x = value.x
            y = value.y
            z = value.z
        }
    }

    private struct Quaternion: Codable, Sendable {
        let x: Double
        let y: Double
        let z: Double
        let w: Double

        init(_ value: MotionQuaternion) {
            x = value.x
            y = value.y
            z = value.z
            w = value.w
        }
    }

    private struct RecordedSample: Codable, Sendable {
        let date: Date
        let uptime: TimeInterval
        let userAcceleration: Vector
        let rotationRate: Vector
        let gravity: Vector
        let attitude: Quaternion?
        let heartRate: Double?
        let workoutState: String
        let detector: SetDetectionDiagnosticSnapshot
    }

    private struct ActiveCapture {
        let sequence: Int
        let startedAt: Date
        let markerUptime: TimeInterval
        var estimatedSetStart: Date?
        var setStartDetectedAt: Date?
        var samples: [RecordedSample]
    }

    private struct CaptureFile: Codable, Sendable {
        let schemaVersion: Int
        let sequence: Int
        let label: String
        let outcome: String
        let appVersion: String
        let buildNumber: String
        let startedAt: Date
        let endedAt: Date
        let markerUptime: TimeInterval
        let estimatedSetStart: Date?
        let setStartDetectedAt: Date?
        let estimatedSetEnd: Date?
        let setEndDetectedAt: Date?
        let startDetectionDelaySeconds: TimeInterval?
        let endDetectionDelaySeconds: TimeInterval?
        let samples: [RecordedSample]
    }

    private enum Outcome: String {
        case missed = "missed"
        case detected = "detected"
        case timedOut = "timed_out"
    }

    private let preRollDuration: TimeInterval = 8
    private let maximumCaptureDuration: TimeInterval = 120
    private let maximumSavedFiles = 3
    private let sequenceKey = "detectionDiagnosticSequence"
    private let persistenceQueue = DispatchQueue(
        label: "com.linfanbin.zujian.detection-diagnostics",
        qos: .utility
    )

    private var preRoll: [RecordedSample] = []
    private var capture: ActiveCapture?

    func resetForWorkout() {
        preRoll.removeAll(keepingCapacity: true)
        capture = nil
        isRecording = false
        message = nil
    }

    func beginCapture(
        at date: Date = Date(),
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard capture == nil else { return }
        let sequence = nextSequence()
        capture = ActiveCapture(
            sequence: sequence,
            startedAt: date,
            markerUptime: uptime,
            estimatedSetStart: nil,
            setStartDetectedAt: nil,
            samples: preRoll
        )
        isRecording = true
        message = "正在记录下一组"
    }

    func observe(
        _ sample: MotionSample,
        state: WorkoutState,
        heartRate: Double?,
        detector: SetDetectionDiagnosticSnapshot
    ) {
        let recorded = RecordedSample(
            date: sample.date,
            uptime: sample.uptime,
            userAcceleration: Vector(sample.userAcceleration),
            rotationRate: Vector(sample.rotationRate),
            gravity: Vector(sample.gravity),
            attitude: sample.attitude.map(Quaternion.init),
            heartRate: heartRate,
            workoutState: state.rawValue,
            detector: detector
        )

        if state == .waitingForSet {
            preRoll.append(recorded)
            let cutoff = sample.uptime - preRollDuration
            preRoll.removeAll { $0.uptime < cutoff }
        }

        guard var capture else { return }
        if capture.samples.last?.uptime != recorded.uptime {
            capture.samples.append(recorded)
        }
        self.capture = capture

        if sample.uptime - capture.markerUptime >= maximumCaptureDuration {
            finish(
                outcome: .timedOut,
                estimatedSetEnd: nil,
                setEndDetectedAt: nil,
                endedAt: sample.date
            )
        }
    }

    func markMissed(at date: Date = Date()) {
        guard capture != nil else { return }
        finish(
            outcome: .missed,
            estimatedSetEnd: nil,
            setEndDetectedAt: nil,
            endedAt: date
        )
    }

    func markSetStarted(
        estimatedStart: Date,
        detectedAt date: Date = Date()
    ) {
        guard var capture else { return }
        capture.estimatedSetStart = estimatedStart
        capture.setStartDetectedAt = date
        self.capture = capture
        message = "已识别开始，继续记录结束"
    }

    func markSetEnded(
        estimatedEnd: Date,
        detectedAt date: Date = Date()
    ) {
        guard capture?.estimatedSetStart != nil else { return }
        finish(
            outcome: .detected,
            estimatedSetEnd: estimatedEnd,
            setEndDetectedAt: date,
            endedAt: date
        )
    }

    func cancelCapture() {
        capture = nil
        isRecording = false
        message = nil
    }

    private func finish(
        outcome: Outcome,
        estimatedSetEnd: Date?,
        setEndDetectedAt: Date?,
        endedAt: Date
    ) {
        guard let capture else { return }
        self.capture = nil
        isRecording = false

        let prefix: String
        switch outcome {
        case .missed: prefix = "失败组"
        case .detected: prefix = "已识别组"
        case .timedOut: prefix = "超时组"
        }
        let label = "\(prefix) \(String(format: "%03d", capture.sequence))"
        message = "正在保存 \(label)…"

        let file = CaptureFile(
            schemaVersion: 2,
            sequence: capture.sequence,
            label: label,
            outcome: outcome.rawValue,
            appVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "unknown",
            buildNumber: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleVersion"
            ) as? String ?? "unknown",
            startedAt: capture.startedAt,
            endedAt: endedAt,
            markerUptime: capture.markerUptime,
            estimatedSetStart: capture.estimatedSetStart,
            setStartDetectedAt: capture.setStartDetectedAt,
            estimatedSetEnd: estimatedSetEnd,
            setEndDetectedAt: setEndDetectedAt,
            startDetectionDelaySeconds: capture.setStartDetectedAt.map {
                max(0, $0.timeIntervalSince(capture.estimatedSetStart ?? $0))
            },
            endDetectionDelaySeconds: setEndDetectedAt.map {
                max(0, $0.timeIntervalSince(estimatedSetEnd ?? $0))
            },
            samples: capture.samples
        )

        let maximumSavedFiles = maximumSavedFiles
        persistenceQueue.async { [weak self] in
            do {
                try Self.persist(file, keeping: maximumSavedFiles)
                DispatchQueue.main.async {
                    self?.message = "已保存：\(label)"
                }
            } catch {
                DispatchQueue.main.async {
                    self?.message = "诊断记录保存失败"
                }
            }
        }
    }

    private func nextSequence() -> Int {
        let defaults = UserDefaults.standard
        let next = defaults.integer(forKey: sequenceKey) + 1
        defaults.set(next, forKey: sequenceKey)
        return next
    }

    private static func persist(
        _ capture: CaptureFile,
        keeping maximumSavedFiles: Int
    ) throws {
        let fileManager = FileManager.default
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = applicationSupport
            .appendingPathComponent("DetectionDiagnostics", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: capture.endedAt)
            .replacingOccurrences(of: ":", with: "-")
        let filename = String(
            format: "%@-%03d-%@.json",
            capture.outcome,
            capture.sequence,
            timestamp
        )
        let destination = directory.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(capture)
        try data.write(to: destination, options: .atomic)

        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }
        .sorted {
            let lhs = try? $0.resourceValues(forKeys: keys).contentModificationDate
            let rhs = try? $1.resourceValues(forKeys: keys).contentModificationDate
            return (lhs ?? .distantPast) > (rhs ?? .distantPast)
        }
        for staleFile in files.dropFirst(maximumSavedFiles) {
            try? fileManager.removeItem(at: staleFile)
        }
    }
}
#endif
