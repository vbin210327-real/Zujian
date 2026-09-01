import Foundation

struct AppRecordingDocument: Codable, Identifiable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let createdAt: Date
    var duration: TimeInterval
    let device: RecordingDeviceDescriptor
    let app: RecordingAppDescriptor
    var events: [RecordableEvent]

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        device: RecordingDeviceDescriptor,
        app: RecordingAppDescriptor,
        events: [RecordableEvent] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.device = device
        self.app = app
        self.events = events
    }

    var suggestedFilename: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Zujian-Recording-\(formatter.string(from: createdAt))-\(id.uuidString.prefix(6)).json"
    }

    func validated() throws -> AppRecordingDocument {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw RecordingDocumentError.unsupportedSchema(schemaVersion)
        }
        guard !events.isEmpty else {
            throw RecordingDocumentError.emptyTimeline
        }
        guard device.logicalWidth > 0,
              device.logicalHeight > 0,
              device.scale > 0,
              duration.isFinite,
              duration >= 0 else {
            throw RecordingDocumentError.invalidMetadata
        }

        var previousTimestamp: TimeInterval = -1
        for event in events {
            guard event.timestamp.isFinite,
                  event.timestamp >= 0,
                  event.timestamp >= previousTimestamp else {
                throw RecordingDocumentError.invalidTimeline
            }
            previousTimestamp = event.timestamp
        }
        return self
    }
}

struct RecordingDeviceDescriptor: Codable, Equatable, Sendable {
    let model: String
    let systemVersion: String
    let logicalWidth: Double
    let logicalHeight: Double
    let scale: Double

    var pixelWidth: Int {
        Self.evenPixelDimension(logicalWidth * scale)
    }

    var pixelHeight: Int {
        Self.evenPixelDimension(logicalHeight * scale)
    }

    private static func evenPixelDimension(_ value: Double) -> Int {
        let rounded = max(2, Int(value.rounded()))
        return rounded.isMultiple(of: 2) ? rounded : rounded + 1
    }
}

struct RecordingAppDescriptor: Codable, Equatable, Sendable {
    let bundleIdentifier: String
    let version: String
    let build: String
}

struct RecordableEvent: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: TimeInterval
    let kind: RecordableEventKind
    let name: String
    let value: RecordableEventValue?
    let startsAnimation: Bool
    let animationDuration: TimeInterval
    let snapshot: ReplaySnapshot

    init(
        id: UUID = UUID(),
        timestamp: TimeInterval,
        kind: RecordableEventKind,
        name: String,
        value: RecordableEventValue? = nil,
        startsAnimation: Bool = false,
        animationDuration: TimeInterval = 0,
        snapshot: ReplaySnapshot
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.name = name
        self.value = value
        self.startsAnimation = startsAnimation
        self.animationDuration = max(0, animationDuration)
        self.snapshot = snapshot
    }
}

enum RecordableEventKind: String, Codable, Equatable, Sendable {
    case lifecycle
    case action
    case gesture
    case screenChanged
    case stateChanged
    case timerChanged
    case textChanged
    case businessDataChanged
    case scrollChanged
}

struct RecordableEventValue: Codable, Equatable, Sendable {
    var text: String?
    var number: Double?
    var flag: Bool?

    static func text(_ value: String) -> Self {
        Self(text: value, number: nil, flag: nil)
    }

    static func number(_ value: Double) -> Self {
        Self(text: nil, number: value, flag: nil)
    }

    static func flag(_ value: Bool) -> Self {
        Self(text: nil, number: nil, flag: value)
    }
}

struct ReplaySnapshot: Codable, Equatable, Sendable {
    var screen: ReplayScreen
    var screenContext: String?
    var phase: ReplayWorkoutPhase
    var elapsedTime: TimeInterval
    var isWorkoutClockRunning: Bool
    var currentHeartRate: Double?
    var completedSetCount: Int
    var currentSetNumber: Int
    var restRemaining: TimeInterval
    var isRestClockRunning: Bool
    var defaultRestDuration: TimeInterval
    var canReturnToPreviousSet: Bool
    var isStarting: Bool
    var startProgressText: String
    var startIssue: ReplayMessage?
    var overlay: ReplayOverlay
    var summary: ReplayWorkoutSummary?
    var history: [ReplayWorkoutSummary]
    var scrollPositions: [String: Double]
}

enum ReplayScreen: String, Codable, CaseIterable, Equatable, Sendable {
    case ready
    case workout
    case finished
    case settings
    case history
    case historyDetail
    case healthAccess
    case workoutPermissionHelp
}

enum ReplayWorkoutPhase: String, Codable, Equatable, Sendable {
    case ready
    case waitingForSet
    case setActive
    case resting
    case paused
    case finished

    var title: String {
        switch self {
        case .ready: return "准备"
        case .waitingForSet: return "等待动作"
        case .setActive: return "训练中"
        case .resting: return "休息"
        case .paused: return "已暂停"
        case .finished: return "训练完成"
        }
    }
}

struct ReplayMessage: Codable, Equatable, Sendable {
    let title: String
    let message: String
}

struct ReplayOverlay: Codable, Equatable, Sendable {
    var kind: ReplayOverlayKind
    var title: String?
    var message: String?

    static let none = Self(kind: .none, title: nil, message: nil)
}

enum ReplayOverlayKind: String, Codable, Equatable, Sendable {
    case none
    case healthAccess
    case workoutPermissionHelp
    case notice
    case endConfirmation
}

struct ReplayWorkoutSummary: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval
    let sets: [ReplaySetSummary]
}

struct ReplaySetSummary: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let number: Int
    let averageHeartRate: Double?
    let maximumHeartRate: Double?
}

enum RecordingDocumentError: LocalizedError {
    case unsupportedSchema(Int)
    case emptyTimeline
    case invalidMetadata
    case invalidTimeline

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema(let version):
            return "不支持录制文件版本 \(version)。"
        case .emptyTimeline:
            return "录制文件没有事件。"
        case .invalidMetadata:
            return "录制文件的设备信息无效。"
        case .invalidTimeline:
            return "录制文件的时间轴无效。"
        }
    }
}

enum RecordingFileCodec {
    static func encode(_ document: AppRecordingDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document.validated())
    }

    static func decode(_ data: Data) throws -> AppRecordingDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppRecordingDocument.self, from: data).validated()
    }
}
