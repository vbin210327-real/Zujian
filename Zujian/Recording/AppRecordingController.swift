#if DEBUG
import Combine
import Foundation
import WatchKit

final class AppRecordingController: ObservableObject {
    private struct ScreenEntry: Equatable {
        let screen: ReplayScreen
        let context: String?
    }

    private enum Keys {
        static let showsControl = "developer.appRecording.showsControl"
    }

    @Published var showsControl: Bool {
        didSet {
            UserDefaults.standard.set(showsControl, forKey: Keys.showsControl)
        }
    }
    @Published private(set) var isRecording = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var statusText = "尚未录制"
    @Published private(set) var lastRecordingURL: URL?

    private let fileManager: FileManager
    private let transfer: WatchRecordingTransfer
    private let directoryURL: URL
    private var subscriptions: Set<AnyCancellable> = []
    private var snapshotProvider: ((ReplayScreen, String?, [String: Double]) -> ReplaySnapshot)?
    private var activeDocument: AppRecordingDocument?
    private var recordingBeganAtUptime: TimeInterval?
    private var screenStack: [ScreenEntry] = [ScreenEntry(screen: .ready, context: nil)]
    private var scrollPositions: [String: Double] = [:]
    private var scrollBaselines: [String: Double] = [:]
    private var lastScrollCapture: [String: (value: Double, uptime: TimeInterval)] = [:]
    private var presentationOverlay = ReplayOverlay.none

    init(fileManager: FileManager = .default, transfer: WatchRecordingTransfer = .shared) {
        self.fileManager = fileManager
        self.transfer = transfer
        showsControl = UserDefaults.standard.bool(forKey: Keys.showsControl)

        directoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Zujian/AppRecordings", isDirectory: true)
        try? fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        lastRecordingURL = Self.latestRecording(in: directoryURL, fileManager: fileManager)
    }

    func bind(
        coordinator: WorkoutCoordinator,
        settings: SettingsManager,
        history: HistoryStore
    ) {
        snapshotProvider = { [weak coordinator, weak settings, weak history, weak self] screen, context, scroll in
            guard let coordinator, let settings, let history else {
                return Self.emptySnapshot(
                    screen: screen,
                    screenContext: context,
                    scrollPositions: scroll
                )
            }
            return self?.makeSnapshot(
                screen: screen,
                screenContext: context,
                scrollPositions: scroll,
                coordinator: coordinator,
                settings: settings,
                history: history
            ) ?? Self.emptySnapshot(
                screen: screen,
                screenContext: context,
                scrollPositions: scroll
            )
        }

        coordinator.$state
            .dropFirst()
            .sink { [weak self] state in
                self?.captureAfterPublishedChange(
                    kind: .stateChanged,
                    name: "workout.phase",
                    value: .text(state.rawValue),
                    startsAnimation: true,
                    animationDuration: 0.22
                )
            }
            .store(in: &subscriptions)

        coordinator.$currentHeartRate
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] heartRate in
                self?.captureAfterPublishedChange(
                    kind: .textChanged,
                    name: "heartRate",
                    value: heartRate.map(RecordableEventValue.number)
                )
            }
            .store(in: &subscriptions)

        coordinator.$lastSummary
            .dropFirst()
            .sink { [weak self] _ in
                self?.captureAfterPublishedChange(
                    kind: .businessDataChanged,
                    name: "workout.summary"
                )
            }
            .store(in: &subscriptions)

        coordinator.$isStarting
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isStarting in
                self?.captureAfterPublishedChange(
                    kind: .stateChanged,
                    name: "workout.isStarting",
                    value: .flag(isStarting)
                )
            }
            .store(in: &subscriptions)

        coordinator.$startProgressText
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] text in
                self?.captureAfterPublishedChange(
                    kind: .textChanged,
                    name: "workout.startProgress",
                    value: .text(text)
                )
            }
            .store(in: &subscriptions)

        coordinator.$notice
            .dropFirst()
            .sink { [weak self] _ in
                self?.captureAfterPublishedChange(kind: .stateChanged, name: "overlay.notice")
            }
            .store(in: &subscriptions)

        coordinator.$showsHealthAccessIntroduction
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isVisible in
                self?.captureAfterPublishedChange(
                    kind: .stateChanged,
                    name: "overlay.healthAccess",
                    value: .flag(isVisible),
                    startsAnimation: true,
                    animationDuration: 0.22
                )
            }
            .store(in: &subscriptions)

        coordinator.$startIssue
            .dropFirst()
            .sink { [weak self] _ in
                self?.captureAfterPublishedChange(kind: .stateChanged, name: "workout.startIssue")
            }
            .store(in: &subscriptions)

        coordinator.restTimer.$isRunning
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] isRunning in
                self?.captureAfterPublishedChange(
                    kind: .timerChanged,
                    name: "restTimer.isRunning",
                    value: .flag(isRunning)
                )
            }
            .store(in: &subscriptions)

        settings.$restDuration
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] duration in
                self?.captureAfterPublishedChange(
                    kind: .businessDataChanged,
                    name: "settings.restDuration",
                    value: .number(duration)
                )
            }
            .store(in: &subscriptions)

        history.$records
            .dropFirst()
            .sink { [weak self] records in
                self?.captureAfterPublishedChange(
                    kind: .businessDataChanged,
                    name: "history.records",
                    value: .number(Double(records.count))
                )
            }
            .store(in: &subscriptions)
    }

    func toggleRecording() {
        guard !isFinalizing else { return }
        WKInterfaceDevice.current().play(.click)
        isRecording ? stopRecording() : startRecording()
    }

    func startRecording() {
        guard !isRecording,
              let snapshotProvider else { return }

        let device = WKInterfaceDevice.current()
        let bundle = Bundle.main
        let document = AppRecordingDocument(
            device: RecordingDeviceDescriptor(
                model: device.model,
                systemVersion: device.systemVersion,
                logicalWidth: Double(device.screenBounds.width),
                logicalHeight: Double(device.screenBounds.height),
                scale: Double(device.screenScale)
            ),
            app: RecordingAppDescriptor(
                bundleIdentifier: bundle.bundleIdentifier ?? "com.linfanbin.zujian.watchapp",
                version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—",
                build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
            )
        )

        activeDocument = document
        recordingBeganAtUptime = ProcessInfo.processInfo.systemUptime
        isRecording = true
        statusText = "正在记录 App 状态"

        let screen = currentScreen
        append(
            kind: .lifecycle,
            name: "recording.started",
            startsAnimation: false,
            snapshot: snapshotProvider(screen, currentScreenContext, scrollPositions)
        )
    }

    func stopRecording() {
        guard isRecording,
              var document = activeDocument,
              let snapshotProvider else { return }

        isFinalizing = true

        append(
            kind: .lifecycle,
            name: "recording.stopped",
            snapshot: snapshotProvider(currentScreen, currentScreenContext, scrollPositions)
        )
        document = activeDocument ?? document
        document.duration = currentTimestamp
        isRecording = false
        activeDocument = nil
        recordingBeganAtUptime = nil
        statusText = "正在保存录制"

        do {
            let data = try RecordingFileCodec.encode(document)
            let fileURL = directoryURL.appendingPathComponent(document.suggestedFilename)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            lastRecordingURL = fileURL
            statusText = "已保存，等待发送到 iPhone"
            trimArchive(keeping: 12)
            transfer.enqueue(fileURL) { [weak self] message in
                self?.statusText = message
            }
        } catch {
            statusText = "保存失败：\(error.localizedDescription)"
        }
        isFinalizing = false
    }

    func retryLastTransfer() {
        guard let lastRecordingURL else {
            statusText = "还没有可发送的录制"
            return
        }
        statusText = "正在重新排队"
        transfer.enqueue(lastRecordingURL) { [weak self] message in
            self?.statusText = message
        }
    }

    func screenAppeared(_ screen: ReplayScreen, context: String? = nil) {
        let entry = ScreenEntry(screen: screen, context: context)
        guard screenStack.last != entry else { return }
        screenStack.append(entry)
        capture(
            kind: .screenChanged,
            name: "screen.\(screen.rawValue)",
            value: .text(screen.rawValue),
            startsAnimation: true,
            animationDuration: 0.22
        )
    }

    func screenDisappeared(_ screen: ReplayScreen) {
        guard let index = screenStack.lastIndex(where: { $0.screen == screen }) else { return }
        screenStack.remove(at: index)
        guard !screenStack.isEmpty else { return }
        let restored = currentScreen
        capture(
            kind: .screenChanged,
            name: "screen.\(restored.rawValue)",
            value: .text(restored.rawValue),
            startsAnimation: true,
            animationDuration: 0.22
        )
    }

    func recordAction(_ name: String, value: RecordableEventValue? = nil) {
        capture(kind: .action, name: name, value: value)
    }

    func recordGesture(_ name: String, value: RecordableEventValue? = nil) {
        capture(kind: .gesture, name: name, value: value)
    }

    func recordBusinessEvent(_ name: String, value: RecordableEventValue? = nil) {
        capture(kind: .businessDataChanged, name: name, value: value)
    }

    /// Keeps visible presentation state that belongs to a SwiftUI View (rather
    /// than an ObservableObject) on the same timeline as business state.
    func presentationOverlayChanged(
        _ kind: ReplayOverlayKind,
        isPresented: Bool,
        title: String? = nil,
        message: String? = nil
    ) {
        let nextOverlay: ReplayOverlay
        if isPresented {
            nextOverlay = ReplayOverlay(kind: kind, title: title, message: message)
        } else {
            guard presentationOverlay.kind == kind else { return }
            nextOverlay = .none
        }
        guard presentationOverlay != nextOverlay else { return }

        presentationOverlay = nextOverlay
        capture(
            kind: .stateChanged,
            name: "overlay.\(kind.rawValue)",
            value: .flag(isPresented),
            startsAnimation: true,
            animationDuration: 0.22
        )
    }

    func recordScrollPosition(
        identifier: String,
        rawValue: Double,
        isAbsolute: Bool = false
    ) {
        guard rawValue.isFinite else { return }
        let value: Double
        if isAbsolute {
            value = rawValue
        } else {
            let baseline = scrollBaselines[identifier] ?? rawValue
            scrollBaselines[identifier] = baseline
            value = rawValue - baseline
        }
        scrollPositions[identifier] = value

        guard isRecording else { return }
        let uptime = ProcessInfo.processInfo.systemUptime
        if let previous = lastScrollCapture[identifier],
           uptime - previous.uptime < 0.10,
           abs(value - previous.value) < 2 {
            return
        }
        lastScrollCapture[identifier] = (value, uptime)
        capture(
            kind: .scrollChanged,
            name: "scroll.\(identifier)",
            value: .number(value)
        )
    }

    private var currentScreen: ReplayScreen {
        screenStack.last?.screen ?? .ready
    }

    private var currentScreenContext: String? {
        screenStack.last?.context
    }

    private var currentTimestamp: TimeInterval {
        guard let recordingBeganAtUptime else { return 0 }
        return max(0, ProcessInfo.processInfo.systemUptime - recordingBeganAtUptime)
    }

    private func captureAfterPublishedChange(
        kind: RecordableEventKind,
        name: String,
        value: RecordableEventValue? = nil,
        startsAnimation: Bool = false,
        animationDuration: TimeInterval = 0
    ) {
        DispatchQueue.main.async { [weak self] in
            self?.capture(
                kind: kind,
                name: name,
                value: value,
                startsAnimation: startsAnimation,
                animationDuration: animationDuration
            )
        }
    }

    private func capture(
        kind: RecordableEventKind,
        name: String,
        value: RecordableEventValue? = nil,
        startsAnimation: Bool = false,
        animationDuration: TimeInterval = 0
    ) {
        guard isRecording,
              let snapshotProvider else { return }
        append(
            kind: kind,
            name: name,
            value: value,
            startsAnimation: startsAnimation,
            animationDuration: animationDuration,
            snapshot: snapshotProvider(currentScreen, currentScreenContext, scrollPositions)
        )
    }

    private func append(
        kind: RecordableEventKind,
        name: String,
        value: RecordableEventValue? = nil,
        startsAnimation: Bool = false,
        animationDuration: TimeInterval = 0,
        snapshot: ReplaySnapshot
    ) {
        guard activeDocument?.events.count ?? 0 < 25_000 else {
            statusText = "事件过多，已停止记录新事件"
            return
        }
        activeDocument?.events.append(
            RecordableEvent(
                timestamp: currentTimestamp,
                kind: kind,
                name: name,
                value: value,
                startsAnimation: startsAnimation,
                animationDuration: animationDuration,
                snapshot: snapshot
            )
        )
    }

    private func makeSnapshot(
        screen: ReplayScreen,
        screenContext: String?,
        scrollPositions: [String: Double],
        coordinator: WorkoutCoordinator,
        settings: SettingsManager,
        history: HistoryStore
    ) -> ReplaySnapshot {
        let overlay: ReplayOverlay
        if presentationOverlay.kind != .none {
            overlay = presentationOverlay
        } else if let notice = coordinator.notice {
            overlay = ReplayOverlay(
                kind: .notice,
                title: "无法继续",
                message: notice.message
            )
        } else if coordinator.showsHealthAccessIntroduction {
            overlay = ReplayOverlay(kind: .healthAccess, title: nil, message: nil)
        } else {
            overlay = .none
        }

        return ReplaySnapshot(
            screen: screen,
            screenContext: screenContext,
            phase: ReplayWorkoutPhase(coordinator.state),
            elapsedTime: coordinator.elapsedTime,
            isWorkoutClockRunning: [.waitingForSet, .setActive, .resting].contains(coordinator.state),
            currentHeartRate: coordinator.currentHeartRate,
            completedSetCount: coordinator.completedSetCount,
            currentSetNumber: coordinator.currentSetNumber,
            restRemaining: coordinator.restTimer.remaining,
            isRestClockRunning: coordinator.state == .resting && coordinator.restTimer.isRunning,
            defaultRestDuration: settings.restDuration,
            canReturnToPreviousSet: coordinator.canReturnToPreviousSet,
            isStarting: coordinator.isStarting,
            startProgressText: coordinator.startProgressText,
            startIssue: coordinator.startIssue.map {
                ReplayMessage(title: $0.title, message: $0.message)
            },
            overlay: overlay,
            summary: coordinator.lastSummary.map(ReplayWorkoutSummary.init),
            history: history.records.prefix(30).map(ReplayWorkoutSummary.init),
            scrollPositions: scrollPositions
        )
    }

    private static func emptySnapshot(
        screen: ReplayScreen,
        screenContext: String?,
        scrollPositions: [String: Double]
    ) -> ReplaySnapshot {
        ReplaySnapshot(
            screen: screen,
            screenContext: screenContext,
            phase: .ready,
            elapsedTime: 0,
            isWorkoutClockRunning: false,
            currentHeartRate: nil,
            completedSetCount: 0,
            currentSetNumber: 1,
            restRemaining: 0,
            isRestClockRunning: false,
            defaultRestDuration: 90,
            canReturnToPreviousSet: false,
            isStarting: false,
            startProgressText: "正在准备训练…",
            startIssue: nil,
            overlay: .none,
            summary: nil,
            history: [],
            scrollPositions: scrollPositions
        )
    }

    private func trimArchive(keeping limit: Int) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let recordings = files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted {
                let first = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let second = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return first > second
            }
        for fileURL in recordings.dropFirst(limit) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func latestRecording(in directoryURL: URL, fileManager: FileManager) -> URL? {
        let urls = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .max {
                let first = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let second = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return first < second
            }
    }
}

private extension ReplayWorkoutPhase {
    init(_ state: WorkoutState) {
        switch state {
        case .ready: self = .ready
        case .waitingForSet: self = .waitingForSet
        case .setActive: self = .setActive
        case .resting: self = .resting
        case .paused: self = .paused
        case .finished: self = .finished
        }
    }
}

private extension ReplayWorkoutSummary {
    init(_ record: WorkoutRecord) {
        self.init(
            id: record.id,
            startDate: record.startDate,
            duration: record.duration,
            sets: record.sets.map {
                ReplaySetSummary(
                    id: $0.id,
                    number: $0.number,
                    averageHeartRate: $0.averageHeartRate,
                    maximumHeartRate: $0.maximumHeartRate
                )
            }
        )
    }
}
#endif
