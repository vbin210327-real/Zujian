import Foundation

struct AppNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

struct StartIssue: Identifiable, Equatable {
    enum Kind: Equatable {
        case workoutPermissionDenied
        case general
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String

    init(kind: Kind = .general, title: String, message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }
}

enum HealthAccessIntroductionMode: Equatable {
    case requestAuthorization
    case changeInSettings
}

final class WorkoutCoordinator: ObservableObject {
    @Published private(set) var state: WorkoutState = .ready {
        didSet {
            publishWidgetSnapshot()
        }
    }
    @Published private(set) var workoutStartDate: Date?
    @Published private(set) var currentHeartRate: Double?
    @Published private(set) var lastSummary: WorkoutRecord?
    @Published private(set) var isStarting = false
    @Published private(set) var startProgressText = "正在准备训练…"
    @Published var notice: AppNotice?
    @Published var showsHealthAccessIntroduction = false
    @Published private(set) var healthAccessIntroductionMode: HealthAccessIntroductionMode = .requestAuthorization
    @Published private(set) var healthAccessStatusMessage: String?
    @Published private(set) var startIssue: StartIssue?

    let restTimer = RestTimerManager()

    private let settings: SettingsManager
    private let history: HistoryStore
    private let motionManager = MotionManager()
    private let workoutSession = WorkoutSessionManager()
    private let detectionEngine = SetDetectionEngine()
    private let haptics = HapticManager()
#if DEBUG
    let diagnosticRecorder = DetectionDiagnosticRecorder()
    weak var appRecordingController: AppRecordingController?
#endif

    private var activeSet: ActiveSetDraft?
    private var completedDrafts: [ActiveSetDraft] = []
    private var recentHeartRates: [(date: Date, bpm: Double)] = []
    private var stateBeforePause: WorkoutState?
    private var pauseStartedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0
    private var draftBeforeRest: ActiveSetDraft?
    private var startupFailureMessage: String?
    private var startsWorkoutAfterHealthAccessDismissal = false
#if DEBUG
    private var nativeReplaySnapshot: ReplaySnapshot?
#endif

    init(settings: SettingsManager, history: HistoryStore) {
        self.settings = settings
        self.history = history

        restTimer.onFinished = { [weak self] in
            self?.restDidFinish()
        }
        workoutSession.onHeartRate = { [weak self] date, bpm in
            self?.receiveHeartRate(date: date, bpm: bpm)
        }
        workoutSession.onFailure = { [weak self] message in
            self?.handleWorkoutFailure(message)
        }
        workoutSession.onPreparationStage = { [weak self] stage in
            DispatchQueue.main.async {
                self?.startProgressText = stage.title
            }
        }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-paused") {
            workoutStartDate = Date().addingTimeInterval(-125)
            stateBeforePause = .waitingForSet
            pauseStartedAt = Date()
            state = .paused
        } else if ProcessInfo.processInfo.arguments.contains("-ui-testing-waiting") {
            workoutStartDate = Date().addingTimeInterval(-18)
            detectionEngine.resetForNewWorkout()
            diagnosticRecorder.resetForWorkout()
            state = .waitingForSet
        }
#endif
        publishWidgetSnapshot()
    }

    var completedSetCount: Int {
#if DEBUG
        if let nativeReplaySnapshot {
            return nativeReplaySnapshot.completedSetCount
        }
#endif
        return completedDrafts.count
    }

    var hasDetectedSet: Bool {
#if DEBUG
        if let nativeReplaySnapshot {
            return nativeReplaySnapshot.completedSetCount > 0
                || nativeReplaySnapshot.phase == .setActive
                || nativeReplaySnapshot.phase == .resting
        }
#endif
        return activeSet != nil || !completedDrafts.isEmpty
    }

    var currentSetNumber: Int {
#if DEBUG
        if let nativeReplaySnapshot {
            return nativeReplaySnapshot.currentSetNumber
        }
#endif
        if let activeSet { return activeSet.number }
        return completedDrafts.count + 1
    }

    var canReturnToPreviousSet: Bool {
#if DEBUG
        if let nativeReplaySnapshot {
            return nativeReplaySnapshot.canReturnToPreviousSet
        }
#endif
        return state == .resting && draftBeforeRest != nil
    }

    var elapsedTime: TimeInterval {
#if DEBUG
        if let nativeReplaySnapshot {
            return nativeReplaySnapshot.elapsedTime
        }
#endif
        guard let workoutStartDate else { return 0 }
        let currentPause = pauseStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        return max(0, Date().timeIntervalSince(workoutStartDate) - accumulatedPausedDuration - currentPause)
    }

#if DEBUG
    /// Feeds a recorded presentation snapshot into the existing Watch views.
    /// This is enabled only by the native replay launch argument and never starts
    /// HealthKit, Core Motion, haptics, persistence, or the normal recorder.
    func applyNativeReplaySnapshot(_ snapshot: ReplaySnapshot) {
        nativeReplaySnapshot = snapshot

        let replayState = WorkoutState(replayPhase: snapshot.phase)
        if state != replayState {
            state = replayState
        }
        if currentHeartRate != snapshot.currentHeartRate {
            currentHeartRate = snapshot.currentHeartRate
        }

        let summary = snapshot.summary.map(WorkoutRecord.init(replaySummary:))
        if lastSummary != summary {
            lastSummary = summary
        }
        if isStarting != snapshot.isStarting {
            isStarting = snapshot.isStarting
        }
        if startProgressText != snapshot.startProgressText {
            startProgressText = snapshot.startProgressText
        }

        if let message = snapshot.startIssue {
            if startIssue?.title != message.title || startIssue?.message != message.message {
                startIssue = StartIssue(title: message.title, message: message.message)
            }
        } else if startIssue != nil {
            startIssue = nil
        }

        let showsHealthSheet = snapshot.screen == .healthAccess
            || snapshot.overlay.kind == .healthAccess
        if showsHealthAccessIntroduction != showsHealthSheet {
            showsHealthAccessIntroduction = showsHealthSheet
        }

        if snapshot.overlay.kind == .notice,
           let message = snapshot.overlay.message {
            if notice?.message != message {
                notice = AppNotice(message: message)
            }
        } else if notice != nil {
            notice = nil
        }

        restTimer.applyNativeReplay(
            remaining: snapshot.restRemaining,
            isRunning: snapshot.isRestClockRunning
        )

        // Computed presentation values above are backed by nativeReplaySnapshot,
        // so publish even when no stored @Published property changed this frame.
        objectWillChange.send()
    }
#endif

    func startWorkout() {
        guard state == .ready, !isStarting else { return }
        recordAction("workout.start")
        healthAccessStatusMessage = nil

        switch workoutSession.workoutWriteAuthorizationState() {
        case .notDetermined:
            healthAccessIntroductionMode = .requestAuthorization
            showsHealthAccessIntroduction = true
        case .denied:
            // HealthKit only returns `.denied` after the person has already
            // made a choice. The system authorization sheet cannot be forced
            // to appear again, so take them straight to the recheck flow.
            healthAccessIntroductionMode = .changeInSettings
            showsHealthAccessIntroduction = true
        case .authorized, .unavailable:
            beginStartingWorkout()
        }
    }

    func continueAfterHealthAccessIntroduction() {
        recordAction("healthAccess.continue")

        switch healthAccessIntroductionMode {
        case .requestAuthorization:
            dismissHealthAccessAndStartWorkout()
        case .changeInSettings:
            switch workoutSession.workoutWriteAuthorizationState() {
            case .authorized:
                dismissHealthAccessAndStartWorkout()
            case .notDetermined:
                healthAccessIntroductionMode = .requestAuthorization
                dismissHealthAccessAndStartWorkout()
            case .denied:
                healthAccessStatusMessage = "系统仍显示“体能训练”未打开。"
            case .unavailable:
                healthAccessStatusMessage = "此设备当前无法使用健康数据。"
            }
        }
    }

    func cancelHealthAccessIntroduction() {
        recordAction("healthAccess.cancel")
        startsWorkoutAfterHealthAccessDismissal = false
        healthAccessStatusMessage = nil
        showsHealthAccessIntroduction = false
    }

    func healthAccessIntroductionDidDismiss() {
        guard startsWorkoutAfterHealthAccessDismissal else { return }
        startsWorkoutAfterHealthAccessDismissal = false
        beginStartingWorkout()
    }

    func retryStartingWorkout() {
        recordAction("workout.retryStart")
        beginStartingWorkout()
    }

    func dismissStartIssue() {
        recordAction("workout.dismissStartIssue")
        startIssue = nil
    }

    private func beginStartingWorkout() {
        guard state == .ready, !isStarting else { return }
        guard motionManager.isAvailable else {
            notice = AppNotice(message: MotionManagerError.unavailable.localizedDescription)
            return
        }

        startIssue = nil
        startupFailureMessage = nil
        startProgressText = "正在准备训练…"
        isStarting = true
        let startDate = Date()
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.workoutSession.requestAuthorizationAndStart(at: startDate)
                if let startupFailureMessage = self.startupFailureMessage {
                    throw WorkoutSessionError.unableToStart(startupFailureMessage)
                }
                try self.startMotionUpdates()
                if let startupFailureMessage = self.startupFailureMessage {
                    throw WorkoutSessionError.unableToStart(startupFailureMessage)
                }
                self.resetSessionData(startDate: startDate)
                self.state = .waitingForSet
            } catch {
                if let workoutError = error as? WorkoutSessionError,
                   case .workoutPermissionDenied = workoutError {
                    self.startIssue = nil
                    self.healthAccessIntroductionMode = .changeInSettings
                    self.healthAccessStatusMessage = nil
                    self.showsHealthAccessIntroduction = true
                } else {
                    self.startIssue = StartIssue(
                        title: "训练还没开始",
                        message: error.localizedDescription
                    )
                }
                await self.workoutSession.stopAndDiscard()
            }
            self.isStarting = false
        }
    }

    private func dismissHealthAccessAndStartWorkout() {
        startsWorkoutAfterHealthAccessDismissal = true
        healthAccessStatusMessage = nil
        showsHealthAccessIntroduction = false
    }

    func manualStartRest() {
        guard state.acceptsSetDetectionMotion else { return }
        recordAction("workout.manualStartRest")
        if state == .setActive {
            finalizeActiveSet(at: Date())
            draftBeforeRest = completedDrafts.last
        } else {
            draftBeforeRest = nil
        }
        beginRest()
    }

#if DEBUG
    func beginDiagnosticCapture() {
        guard state == .waitingForSet else { return }
        diagnosticRecorder.beginCapture()
    }

    func markDiagnosticSetMissed() {
        guard state == .waitingForSet else { return }
        diagnosticRecorder.markMissed()
    }
#endif

    func continueTraining() {
        guard state == .resting else { return }
        recordAction("workout.continueTraining")
        restTimer.cancel()
        draftBeforeRest = nil
        activeSet = nil
        detectionEngine.armStartDetection(
            at: ProcessInfo.processInfo.systemUptime
        )
        state = .waitingForSet
    }

    func returnToPreviousSet() {
        guard state == .resting, let draft = draftBeforeRest else { return }
        recordAction("workout.returnToPreviousSet")
        let correctedPause = max(
            0,
            Date().timeIntervalSince(draft.endDate ?? draft.startDate)
        )
        restTimer.cancel()
        completedDrafts.removeAll { $0.id == draft.id }
        var reopened = draft
        reopened.endDate = nil
        reopened.heartRateSamples.append(contentsOf: recentHeartRates.filter {
            $0.date > (draft.endDate ?? draft.startDate)
        })
        activeSet = reopened
        currentHeartRate = reopened.heartRateSamples.last?.bpm
        draftBeforeRest = nil
        state = .setActive
        detectionEngine.forceActive(correctedPause: correctedPause)
    }

    func pauseWorkout() {
        guard [.waitingForSet, .setActive, .resting].contains(state) else { return }
        recordAction("workout.pause")
#if DEBUG
        diagnosticRecorder.cancelCapture()
#endif
        stateBeforePause = state
        if state == .resting {
            restTimer.pause()
        }
        motionManager.stop()
        detectionEngine.prepareAfterInterruption()
        workoutSession.pause()
        pauseStartedAt = Date()
        state = .paused
    }

    func resumeWorkout() {
        guard state == .paused, let previous = stateBeforePause else { return }
        recordAction("workout.resume")
        do {
            try startMotionUpdates()
        } catch {
            notice = AppNotice(message: error.localizedDescription)
            return
        }
        workoutSession.resume()
        if let pauseStartedAt {
            accumulatedPausedDuration += Date().timeIntervalSince(pauseStartedAt)
        }
        pauseStartedAt = nil
        if previous == .resting {
            restTimer.resume()
        } else if previous == .waitingForSet {
            detectionEngine.armStartDetection(
                at: ProcessInfo.processInfo.systemUptime
            )
        }
        state = previous
        stateBeforePause = nil
    }

    func endWorkout(saveLocally: Bool) {
        guard state != .ready && state != .finished else { return }
        recordAction(
            "workout.end",
            value: .flag(saveLocally)
        )
#if DEBUG
        diagnosticRecorder.cancelCapture()
#endif
        let endDate = Date()
        if let pauseStartedAt {
            accumulatedPausedDuration += endDate.timeIntervalSince(pauseStartedAt)
            self.pauseStartedAt = nil
        }
        if activeSet != nil {
            finalizeActiveSet(at: endDate)
        }

        motionManager.stop()
        restTimer.cancel()
        let record = WorkoutRecord(
            id: UUID(),
            startDate: workoutStartDate ?? endDate,
            endDate: endDate,
            pausedDuration: accumulatedPausedDuration,
            sets: completedDrafts.map { $0.record(endingAt: $0.endDate ?? endDate) }
        )
        if saveLocally {
            history.add(record)
        }
        lastSummary = record
        state = .finished

        Task { [workoutSession] in
            await workoutSession.stopAndDiscard(at: endDate)
        }
    }

    func dismissSummary() {
        guard state == .finished else { return }
        recordAction("workout.dismissSummary")
        state = .ready
        workoutStartDate = nil
        currentHeartRate = nil
        lastSummary = nil
        activeSet = nil
        completedDrafts = []
        recentHeartRates = []
        stateBeforePause = nil
        pauseStartedAt = nil
        accumulatedPausedDuration = 0
        draftBeforeRest = nil
        detectionEngine.resetToIdle()
    }

    private func resetSessionData(startDate: Date) {
        workoutStartDate = startDate
        currentHeartRate = nil
        lastSummary = nil
        activeSet = nil
        completedDrafts = []
        recentHeartRates = []
        stateBeforePause = nil
        pauseStartedAt = nil
        accumulatedPausedDuration = 0
        draftBeforeRest = nil
#if DEBUG
        diagnosticRecorder.resetForWorkout()
#endif
        detectionEngine.resetForNewWorkout(
            armedAtUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    private func receiveMotion(_ sample: MotionSample) {
        // Resting is deliberately motion-locked. Only the countdown finishing
        // or an explicit "continue training" action can arm the next set.
        if state == .resting {
            detectionEngine.observeResting(sample)
            return
        }
        guard state == .waitingForSet || state == .setActive else { return }
        let stateAtSample = state
        let event = detectionEngine.process(sample)
#if DEBUG
        diagnosticRecorder.observe(
            sample,
            state: stateAtSample,
            heartRate: recentHeartRates.last?.bpm,
            detector: detectionEngine.diagnosticSnapshot
        )
#endif
        guard let event else { return }
        switch event {
        case .setStarted(let estimatedStart):
#if DEBUG
            diagnosticRecorder.markSetStarted(
                estimatedStart: estimatedStart,
                detectedAt: sample.date
            )
#endif
            handleDetectedSetStart(at: estimatedStart)
        case .setEnded(let estimatedEnd):
#if DEBUG
            diagnosticRecorder.markSetEnded(
                estimatedEnd: estimatedEnd,
                detectedAt: sample.date
            )
#endif
            handleDetectedSetEnd(at: estimatedEnd)
        }
    }

    private func handleDetectedSetStart(at date: Date) {
        guard state == .waitingForSet else { return }
        recordBusinessEvent("detection.setStarted")

        let number = completedDrafts.count + 1
        activeSet = ActiveSetDraft(
            id: UUID(),
            number: number,
            startDate: date,
            endDate: nil,
            heartRateSamples: recentHeartRates.filter { $0.date >= date }
        )
        currentHeartRate = activeSet?.heartRateSamples.last?.bpm
        state = .setActive
    }

    private func handleDetectedSetEnd(at date: Date) {
        guard state == .setActive, activeSet != nil else { return }
        recordBusinessEvent("detection.setEnded")
        finalizeActiveSet(at: date)
        draftBeforeRest = completedDrafts.last
        haptics.setEnded()
        beginRest(startedAt: date)
    }

    private func finalizeActiveSet(at date: Date) {
        guard var draft = activeSet else { return }
        draft.endDate = max(date, draft.startDate)
        draft.heartRateSamples.removeAll { $0.date > date }
        completedDrafts.append(draft)
        activeSet = nil
        currentHeartRate = nil
    }

    private func beginRest(startedAt: Date = Date()) {
        state = .resting
        detectionEngine.beginRestObservation()
        let detectionDelay = max(0, Date().timeIntervalSince(startedAt))
        restTimer.start(duration: max(0, settings.restDuration - detectionDelay))
        publishWidgetSnapshot()
    }

    private func restDidFinish() {
        guard state == .resting else { return }
        recordBusinessEvent("restTimer.finished")
        draftBeforeRest = nil
        detectionEngine.armStartDetection(
            at: ProcessInfo.processInfo.systemUptime,
            contaminationGuard: 0.42
        )
        state = .waitingForSet
        haptics.restEnded()
    }

    private func receiveHeartRate(date: Date, bpm: Double) {
        guard bpm.isFinite, bpm > 0 else { return }
        detectionEngine.observeHeartRate(date: date, bpm: bpm)
        recentHeartRates.append((date, bpm))
        if state == .setActive {
            activeSet?.heartRateSamples.append((date, bpm))
            currentHeartRate = bpm
        }
    }

    private func handleWorkoutFailure(_ message: String) {
        if isStarting {
            startupFailureMessage = message
            startIssue = StartIssue(
                title: "训练还没开始",
                message: "系统训练会话启动失败：\(message)"
            )
            return
        }
        guard state != .ready && state != .finished else { return }
        notice = AppNotice(message: message)
        endWorkout(saveLocally: hasDetectedSet)
    }

    private func startMotionUpdates() throws {
        try motionManager.start(
            handler: { [weak self] sample in
                self?.receiveMotion(sample)
            },
            onFailure: { [weak self] error in
                self?.handleMotionFailure(error)
            }
        )
    }

    private func handleMotionFailure(_ error: MotionManagerError) {
        if isStarting {
            startupFailureMessage = error.localizedDescription
            startIssue = StartIssue(
                title: "训练还没开始",
                message: error.localizedDescription
            )
            return
        }
        guard state != .ready && state != .finished else { return }
        notice = AppNotice(message: error.localizedDescription)
        endWorkout(saveLocally: hasDetectedSet)
    }

    private func publishWidgetSnapshot() {
        let phase: ZujianWidgetPhase
        switch state {
        case .ready: phase = .ready
        case .waitingForSet: phase = .waiting
        case .setActive: phase = .active
        case .resting: phase = .resting
        case .paused: phase = .paused
        case .finished: phase = .finished
        }

        let finishedCount = lastSummary?.sets.count ?? completedDrafts.count
        ZujianWidgetStore.save(
            ZujianWidgetSnapshot(
                phase: phase,
                setNumber: currentSetNumber,
                completedSetCount: state == .finished ? finishedCount : completedSetCount,
                defaultRestDuration: settings.restDuration,
                workoutStartDate: workoutStartDate,
                currentSetStartDate: activeSet?.startDate,
                restStartedAt: state == .resting ? restTimer.expectedStartDate : nil,
                restEndDate: state == .resting ? restTimer.expectedEndDate : nil,
                updatedAt: Date()
            )
        )
    }

    private func recordAction(_ name: String, value: RecordableEventValue? = nil) {
#if DEBUG
        appRecordingController?.recordAction(name, value: value)
#endif
    }

    private func recordBusinessEvent(_ name: String, value: RecordableEventValue? = nil) {
#if DEBUG
        appRecordingController?.recordBusinessEvent(name, value: value)
#endif
    }
}
