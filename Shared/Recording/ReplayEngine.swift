import Foundation

struct ReplayFrame: Equatable, Sendable {
    var snapshot: ReplaySnapshot
    var previousSnapshot: ReplaySnapshot?
    var transitionProgress: Double
    var animationElapsed: TimeInterval
    var time: TimeInterval
}

struct ReplayEngine: Sendable {
    let recording: AppRecordingDocument
    private let events: [RecordableEvent]
    private let resolvedSnapshots: [ReplaySnapshot]

    init(recording: AppRecordingDocument) throws {
        let validatedRecording = try recording.validated()
        self.recording = validatedRecording
        events = validatedRecording.events
        resolvedSnapshots = Self.resolveSnapshots(for: validatedRecording.events)
    }

    var duration: TimeInterval {
        max(recording.duration, events.last?.timestamp ?? 0)
    }

    func frame(at requestedTime: TimeInterval) -> ReplayFrame {
        let time = min(max(0, requestedTime), duration)
        let eventIndex = indexOfLastEvent(atOrBefore: time)
        let event = events[eventIndex]
        var snapshot = advanced(
            resolvedSnapshots[eventIndex],
            by: time - event.timestamp
        )

        let animationIndex = indexOfLastAnimation(atOrBefore: eventIndex)
        let animationEvent = events[animationIndex]
        let animationElapsed = max(0, time - animationEvent.timestamp)

        var previousSnapshot: ReplaySnapshot?
        var transitionProgress = 1.0
        if animationEvent.animationDuration > 0,
           animationElapsed < animationEvent.animationDuration,
           animationIndex > 0 {
            previousSnapshot = advanced(
                resolvedSnapshots[animationIndex - 1],
                by: max(0, time - events[animationIndex - 1].timestamp)
            )
            let linearProgress = animationElapsed / animationEvent.animationDuration
            transitionProgress = ReplayEasing.easeInOut(linearProgress)
        }

        snapshot.elapsedTime = max(0, snapshot.elapsedTime)
        snapshot.restRemaining = max(0, snapshot.restRemaining)
        return ReplayFrame(
            snapshot: snapshot,
            previousSnapshot: previousSnapshot,
            transitionProgress: transitionProgress,
            animationElapsed: animationElapsed,
            time: time
        )
    }

    private func indexOfLastEvent(atOrBefore time: TimeInterval) -> Int {
        var lower = 0
        var upper = events.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if events[middle].timestamp <= time {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(0, lower - 1)
    }

    private func indexOfLastAnimation(atOrBefore eventIndex: Int) -> Int {
        var index = eventIndex
        while index > 0, !events[index].startsAnimation {
            index -= 1
        }
        return index
    }

    /// Schema 1 recordings already contain action names, but older recorders
    /// did not copy View-local alert state into each snapshot. Resolve those
    /// actions once up front so both old and new recordings replay identically.
    private static func resolveSnapshots(
        for events: [RecordableEvent]
    ) -> [ReplaySnapshot] {
        var activeEndConfirmation: ReplayOverlay?

        return events.map { event in
            var snapshot = event.snapshot

            switch snapshot.overlay.kind {
            case .endConfirmation:
                activeEndConfirmation = snapshot.overlay
            case .notice, .healthAccess, .workoutPermissionHelp:
                activeEndConfirmation = nil
            case .none:
                break
            }

            if event.name == "workout.showEndConfirmation" {
                activeEndConfirmation = endConfirmationOverlay(for: snapshot)
            }

            if event.name == "overlay.endConfirmation",
               let isPresented = event.value?.flag {
                activeEndConfirmation = isPresented
                    ? endConfirmationOverlay(for: snapshot)
                    : nil
            }

            if event.name == "workout.end"
                || snapshot.phase == .finished
                || snapshot.phase == .ready {
                activeEndConfirmation = nil
            }

            if let activeEndConfirmation,
               snapshot.overlay.kind == .none
                    || snapshot.overlay.kind == .endConfirmation {
                snapshot.overlay = activeEndConfirmation
            }
            return snapshot
        }
    }

    private static func endConfirmationOverlay(
        for snapshot: ReplaySnapshot
    ) -> ReplayOverlay {
        if snapshot.phase == .paused {
            return ReplayOverlay(
                kind: .endConfirmation,
                title: "结束本次训练？",
                message: nil
            )
        }

        let hasDetectedSet = snapshot.completedSetCount > 0
            || snapshot.phase == .setActive
            || snapshot.phase == .resting
        return ReplayOverlay(
            kind: .endConfirmation,
            title: hasDetectedSet ? "结束本次训练？" : "未检测到训练组",
            message: hasDetectedSet
                ? "训练记录将保存在组间。"
                : "你可以保存这次记录，也可以直接丢弃。"
        )
    }

    private func advanced(_ source: ReplaySnapshot, by delta: TimeInterval) -> ReplaySnapshot {
        var snapshot = source
        if snapshot.isWorkoutClockRunning {
            snapshot.elapsedTime += max(0, delta)
        }
        if snapshot.isRestClockRunning {
            snapshot.restRemaining -= max(0, delta)
        }
        return snapshot
    }
}

enum ReplayEasing {
    static func easeInOut(_ value: Double) -> Double {
        cubicBezier(value, x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    }

    static func easeOut(_ value: Double) -> Double {
        cubicBezier(value, x1: 0, y1: 0, x2: 0.58, y2: 1)
    }

    private static func cubicBezier(
        _ value: Double,
        x1: Double,
        y1: Double,
        x2: Double,
        y2: Double
    ) -> Double {
        let target = min(max(0, value), 1)
        var parameter = target

        for _ in 0..<6 {
            let x = bezier(parameter, first: x1, second: x2)
            let derivative = bezierDerivative(parameter, first: x1, second: x2)
            guard abs(derivative) > 0.000_001 else { break }
            parameter = min(max(0, parameter - (x - target) / derivative), 1)
        }
        return bezier(parameter, first: y1, second: y2)
    }

    private static func bezier(_ t: Double, first: Double, second: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * t * first
            + 3 * inverse * t * t * second
            + t * t * t
    }

    private static func bezierDerivative(_ t: Double, first: Double, second: Double) -> Double {
        let inverse = 1 - t
        return 3 * inverse * inverse * first
            + 6 * inverse * t * (second - first)
            + 3 * t * t * (1 - second)
    }
}
