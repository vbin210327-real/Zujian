import Foundation

enum WorkoutState: String, Codable, Equatable {
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

    var acceptsSetDetectionMotion: Bool {
        self == .waitingForSet || self == .setActive
    }
}

struct SetRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let number: Int
    let startDate: Date
    let endDate: Date
    let averageHeartRate: Double?
    let maximumHeartRate: Double?

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate))
    }
}

struct WorkoutRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let pausedDuration: TimeInterval
    let sets: [SetRecord]

    var duration: TimeInterval {
        max(0, endDate.timeIntervalSince(startDate) - pausedDuration)
    }
}

struct ActiveSetDraft {
    let id: UUID
    let number: Int
    let startDate: Date
    var endDate: Date?
    var heartRateSamples: [(date: Date, bpm: Double)]

    func record(endingAt date: Date) -> SetRecord {
        let included = heartRateSamples
            .filter { $0.date >= startDate && $0.date <= date }
            .map(\.bpm)

        let average = included.isEmpty ? nil : included.reduce(0, +) / Double(included.count)
        let maximum = included.max()

        return SetRecord(
            id: id,
            number: number,
            startDate: startDate,
            endDate: date,
            averageHeartRate: average,
            maximumHeartRate: maximum
        )
    }
}

enum DurationText {
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func concise(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainingSeconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
