#if DEBUG
import Foundation

enum NativeReplayRuntime {
    static let launchArgument = "--native-replay"
    static let framesPerSecondArgument = "--native-replay-fps"
    static let recordingFilename = "ZujianNativeReplay.json"
    static let readyMarkerFilename = "ZujianNativeReplay.ready"
    static let startMarkerFilename = "ZujianNativeReplay.start"
    static let finishedMarkerFilename = "ZujianNativeReplay.finished"
    static let errorMarkerFilename = "ZujianNativeReplay.error.txt"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func value(after argument: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: argument),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

@MainActor
final class NativeReplayController: ObservableObject {
    @Published private(set) var frame: ReplayFrame?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isPlaying = false

    let isEnabled: Bool

    private let coordinator: WorkoutCoordinator
    private let settings: SettingsManager
    private let history: HistoryStore
    private let fileManager: FileManager
    private let documentsURL: URL
    private let framesPerSecond: Int
    private var engine: ReplayEngine?
    private var triggerTimer: Timer?
    private var playbackTimer: Timer?
    private var playbackStartedAt: TimeInterval?

    init(
        coordinator: WorkoutCoordinator,
        settings: SettingsManager,
        history: HistoryStore,
        fileManager: FileManager = .default,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.coordinator = coordinator
        self.settings = settings
        self.history = history
        self.fileManager = fileManager
        documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let arguments = processInfo.arguments
        isEnabled = arguments.contains(NativeReplayRuntime.launchArgument)
        let requestedFPS = NativeReplayRuntime.value(
            after: NativeReplayRuntime.framesPerSecondArgument,
            in: arguments
        ).flatMap(Int.init)
        framesPerSecond = requestedFPS == 30 ? 30 : 60

        guard isEnabled else { return }

        removeMarker(named: NativeReplayRuntime.readyMarkerFilename)
        removeMarker(named: NativeReplayRuntime.startMarkerFilename)
        removeMarker(named: NativeReplayRuntime.finishedMarkerFilename)
        removeMarker(named: NativeReplayRuntime.errorMarkerFilename)

        let suppliedPath = NativeReplayRuntime.value(
            after: NativeReplayRuntime.launchArgument,
            in: arguments
        ) ?? NativeReplayRuntime.recordingFilename
        let recordingURL: URL
        if suppliedPath.hasPrefix("/") {
            recordingURL = URL(fileURLWithPath: suppliedPath)
        } else {
            recordingURL = documentsURL.appendingPathComponent(suppliedPath)
        }

        do {
            let data = try Data(contentsOf: recordingURL)
            let recording = try RecordingFileCodec.decode(data)
            let replayEngine = try ReplayEngine(recording: recording)
            engine = replayEngine
            apply(replayEngine.frame(at: 0))

            // Let SwiftUI mount the first native Watch frame before signalling
            // the Mac renderer that display capture may begin.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.markReadyAndWaitForStart()
            }
        } catch {
            errorMessage = "原生回放无法读取录制：\(error.localizedDescription)"
            writeTextMarker(
                named: NativeReplayRuntime.errorMarkerFilename,
                text: errorMessage ?? "原生回放无法读取录制"
            )
            writeMarker(named: NativeReplayRuntime.readyMarkerFilename)
        }
    }

    deinit {
        triggerTimer?.invalidate()
        playbackTimer?.invalidate()
    }

    private func markReadyAndWaitForStart() {
        writeMarker(named: NativeReplayRuntime.readyMarkerFilename)
        triggerTimer?.invalidate()
        triggerTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.startIfTriggered()
            }
        }
    }

    private func startIfTriggered() {
        let triggerURL = markerURL(named: NativeReplayRuntime.startMarkerFilename)
        guard fileManager.fileExists(atPath: triggerURL.path) else { return }
        triggerTimer?.invalidate()
        triggerTimer = nil
        removeMarker(named: NativeReplayRuntime.startMarkerFilename)
        startPlayback()
    }

    private func startPlayback() {
        guard let engine else { return }
        playbackStartedAt = ProcessInfo.processInfo.systemUptime
        isPlaying = true
        apply(engine.frame(at: 0))

        guard engine.duration > 0 else {
            finishPlayback()
            return
        }

        let interval = 1.0 / Double(framesPerSecond)
        playbackTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.advancePlayback()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func advancePlayback() {
        guard let engine, let playbackStartedAt else { return }
        let playhead = ProcessInfo.processInfo.systemUptime - playbackStartedAt
        if playhead >= engine.duration {
            apply(engine.frame(at: engine.duration))
            finishPlayback()
        } else {
            apply(engine.frame(at: playhead))
        }
    }

    private func finishPlayback() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        playbackStartedAt = nil
        isPlaying = false
        writeMarker(named: NativeReplayRuntime.finishedMarkerFilename)
    }

    private func apply(_ frame: ReplayFrame) {
        let snapshot = frame.snapshot
        if settings.restDuration != snapshot.defaultRestDuration {
            settings.restDuration = snapshot.defaultRestDuration
        }
        history.applyNativeReplay(snapshot.history)
        coordinator.applyNativeReplaySnapshot(snapshot)
        self.frame = frame
    }

    private func markerURL(named filename: String) -> URL {
        documentsURL.appendingPathComponent(filename)
    }

    private func removeMarker(named filename: String) {
        try? fileManager.removeItem(at: markerURL(named: filename))
    }

    private func writeMarker(named filename: String) {
        let url = markerURL(named: filename)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: Data())
        }
    }

    private func writeTextMarker(named filename: String, text: String) {
        try? Data(text.utf8).write(
            to: markerURL(named: filename),
            options: .atomic
        )
    }
}

extension WorkoutState {
    init(replayPhase: ReplayWorkoutPhase) {
        switch replayPhase {
        case .ready: self = .ready
        case .waitingForSet: self = .waitingForSet
        case .setActive: self = .setActive
        case .resting: self = .resting
        case .paused: self = .paused
        case .finished: self = .finished
        }
    }
}

extension WorkoutRecord {
    init(replaySummary: ReplayWorkoutSummary) {
        let endDate = replaySummary.startDate.addingTimeInterval(replaySummary.duration)
        let sets = replaySummary.sets.map { set in
            SetRecord(
                id: set.id,
                number: set.number,
                startDate: replaySummary.startDate,
                endDate: replaySummary.startDate,
                averageHeartRate: set.averageHeartRate,
                maximumHeartRate: set.maximumHeartRate
            )
        }
        self.init(
            id: replaySummary.id,
            startDate: replaySummary.startDate,
            endDate: endDate,
            pausedDuration: 0,
            sets: sets
        )
    }
}
#endif
