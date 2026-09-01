import Foundation
import WidgetKit

enum ZujianWidgetPhase: String, Codable, Equatable {
    case ready
    case waiting
    case active
    case resting
    case paused
    case finished
}

struct ZujianWidgetSnapshot: Codable, Equatable {
    var phase: ZujianWidgetPhase
    var setNumber: Int
    var completedSetCount: Int
    var defaultRestDuration: TimeInterval
    var workoutStartDate: Date?
    var currentSetStartDate: Date?
    var restStartedAt: Date?
    var restEndDate: Date?
    var updatedAt: Date

    static func ready(
        defaultRestDuration: TimeInterval,
        updatedAt: Date = Date()
    ) -> ZujianWidgetSnapshot {
        ZujianWidgetSnapshot(
            phase: .ready,
            setNumber: 1,
            completedSetCount: 0,
            defaultRestDuration: defaultRestDuration,
            workoutStartDate: nil,
            currentSetStartDate: nil,
            restStartedAt: nil,
            restEndDate: nil,
            updatedAt: updatedAt
        )
    }

    static let previewResting = ZujianWidgetSnapshot(
        phase: .resting,
        setNumber: 4,
        completedSetCount: 3,
        defaultRestDuration: 90,
        workoutStartDate: Date().addingTimeInterval(-18 * 60),
        currentSetStartDate: nil,
        restStartedAt: Date(),
        restEndDate: Date().addingTimeInterval(74),
        updatedAt: Date()
    )

    func resolved(at date: Date = Date()) -> ZujianWidgetSnapshot {
        if phase == .resting,
           let restEndDate,
           restEndDate <= date {
            var value = self
            value.phase = .waiting
            value.restStartedAt = nil
            value.restEndDate = nil
            value.updatedAt = restEndDate
            return value
        }

        let staleAfter: TimeInterval
        switch phase {
        case .ready:
            return self
        case .finished:
            staleAfter = 2 * 60 * 60
        case .waiting, .active, .resting, .paused:
            staleAfter = 4 * 60 * 60
        }

        guard date.timeIntervalSince(updatedAt) > staleAfter else { return self }
        return .ready(defaultRestDuration: defaultRestDuration, updatedAt: date)
    }

    var automaticRefreshDate: Date? {
        switch phase {
        case .ready:
            return nil
        case .finished:
            return updatedAt.addingTimeInterval(2 * 60 * 60)
        case .waiting, .active, .resting, .paused:
            return updatedAt.addingTimeInterval(4 * 60 * 60)
        }
    }

    var petImageName: String {
        switch phase {
        case .ready: return "PetWaiting"
        case .waiting: return completedSetCount == 0 ? "PetWaiting" : "PetNext"
        case .active: return "PetActive"
        case .resting: return "PetResting"
        case .paused: return "PetAOD"
        case .finished: return "PetFinished"
        }
    }
}

enum ZujianWidgetStore {
    static let suiteName = "group.com.linfanbin.zujian"
    static let widgetKind = "ZujianStatusWidget"

    private static let snapshotKey = "widgetSnapshot"

    static func save(_ snapshot: ZujianWidgetSnapshot) {
        guard
            let defaults = UserDefaults(suiteName: suiteName),
            let data = try? JSONEncoder().encode(snapshot)
        else { return }

        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func load(
        defaultRestDuration: TimeInterval = 90,
        at date: Date = Date()
    ) -> ZujianWidgetSnapshot {
        guard
            let defaults = UserDefaults(suiteName: suiteName),
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(ZujianWidgetSnapshot.self, from: data)
        else {
            return .ready(defaultRestDuration: defaultRestDuration, updatedAt: date)
        }

        return snapshot.resolved(at: date)
    }

    static func updateDefaultRestDuration(_ duration: TimeInterval) {
        let bounded = min(max(duration, 15), 600)
        var snapshot = load(defaultRestDuration: bounded)
        snapshot.defaultRestDuration = bounded
        if snapshot.phase == .ready {
            snapshot.updatedAt = Date()
        }
        save(snapshot)
    }
}
