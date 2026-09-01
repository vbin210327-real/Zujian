import Foundation
import HealthKit
import os

enum WorkoutPreparationStage {
    case checkingAccess
    case requestingAccess
    case startingSession

    var title: String {
        switch self {
        case .checkingAccess: return "正在检查权限…"
        case .requestingAccess: return "请完成系统授权…"
        case .startingSession: return "正在启动训练…"
        }
    }
}

enum WorkoutWriteAuthorizationState {
    case unavailable
    case notDetermined
    case denied
    case authorized
}

enum WorkoutSessionError: LocalizedError {
    case healthDataUnavailable
    case workoutPermissionDenied
    case workoutPermissionNotDetermined
    case authorizationInterrupted
    case authorizationTimedOut
    case startupTimedOut
    case unableToStart(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable:
            return "此设备无法使用健康数据。"
        case .workoutPermissionDenied:
            return "系统仍返回“体能训练写入：关闭”。这项权限用于启动系统训练会话；心率可以不开。"
        case .workoutPermissionNotDetermined:
            return "系统返回：“训练”权限尚未完成。请再次完成系统授权，并确认已打开“训练”；心率是可选项。"
        case .authorizationInterrupted:
            return "健康授权没有完成。你可以直接重新检查；已经允许的项目不需要再次设置。"
        case .authorizationTimedOut:
            return "系统授权页没有完成响应。请确认“训练”已允许后返回组间，再点一次重新检查。"
        case .startupTimedOut:
            return "系统训练服务响应超时。请保持手表解锁后重新检查；如果仍然出现，可重启手表后再试。"
        case .unableToStart(let reason):
            return "无法开始训练：\(reason)"
        }
    }
}

final class WorkoutSessionManager: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var currentHeartRate: Double?

    var onHeartRate: ((Date, Double) -> Void)?
    var onFailure: ((String) -> Void)?
    var onPreparationStage: ((WorkoutPreparationStage) -> Void)?

    // A HealthKit store can keep the authorization snapshot it was created
    // with while the user changes access outside the app. Replace it for every
    // start attempt so "check again" really reads the current system state.
    private var healthStore = HKHealthStore()
    private let logger = Logger(subsystem: "com.linfanbin.zujian.watchapp", category: "WorkoutSession")
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var collectionStarted = false
    private var stoppingIntentionally = false

    func workoutWriteAuthorizationState() -> WorkoutWriteAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .unavailable
        }

        // Use a fresh store so returning from Settings immediately reflects the
        // decision the person just made on Apple Watch.
        let currentHealthStore = HKHealthStore()
        switch currentHealthStore.authorizationStatus(for: HKObjectType.workoutType()) {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .denied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    func requestAuthorizationAndStart(at startDate: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw WorkoutSessionError.healthDataUnavailable
        }

        var currentHealthStore = HKHealthStore()
        healthStore = currentHealthStore

        let workoutType = HKObjectType.workoutType()
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw WorkoutSessionError.healthDataUnavailable
        }

        let shareTypes: Set<HKSampleType> = [workoutType]
        let readTypes: Set<HKObjectType> = [heartRateType]

        onPreparationStage?(.checkingAccess)
        logger.info("Checking mandatory workout write authorization")

        switch currentHealthStore.authorizationStatus(for: workoutType) {
        case .sharingAuthorized:
            // Heart rate is optional. Never reopen authorization or block the
            // workout merely because a read permission may still need attention.
            logger.info("Workout write authorization already allowed; skipping authorization UI")
        case .sharingDenied, .notDetermined:
            // Always make the real HealthKit request from the person's
            // "继续" action. HealthKit itself decides whether a system sheet is
            // still required. Only route to Settings after this call finishes
            // and workout write access remains denied.
            onPreparationStage?(.requestingAccess)
            do {
                try await requestHealthAuthorization(
                    using: currentHealthStore,
                    toShare: shareTypes,
                    read: readTypes
                )
                // The authorization sheet may finish before an existing store
                // observes the updated decision. Read it back from a new store.
                currentHealthStore = HKHealthStore()
                healthStore = currentHealthStore
            } catch {
                if let workoutError = error as? WorkoutSessionError {
                    throw workoutError
                }
                throw WorkoutSessionError.authorizationInterrupted
            }
        @unknown default:
            throw WorkoutSessionError.workoutPermissionNotDetermined
        }

        // Workout write access is the only mandatory HealthKit permission.
        // Read access (heart rate) is intentionally not checked because
        // HealthKit does not reveal whether the user denied read permission.
        switch currentHealthStore.authorizationStatus(for: workoutType) {
        case .sharingAuthorized:
            logger.info("Workout write authorization is allowed")
            break
        case .sharingDenied:
            logger.error("Workout write authorization is denied")
            throw WorkoutSessionError.workoutPermissionDenied
        case .notDetermined:
            logger.error("Workout write authorization is not determined")
            throw WorkoutSessionError.workoutPermissionNotDetermined
        @unknown default:
            throw WorkoutSessionError.workoutPermissionNotDetermined
        }

        onPreparationStage?(.startingSession)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: currentHealthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: currentHealthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            collectionStarted = false
            stoppingIntentionally = false

            session.startActivity(with: startDate)
            try await beginCollection(builder, at: startDate)
            collectionStarted = true
            try await waitUntilRunning(session)
            await MainActor.run {
                self.isRunning = true
            }
            logger.info("Workout session started")
        } catch let error as WorkoutSessionError {
            abortFailedStart()
            throw error
        } catch {
            logger.error("Workout session failed to start: \(error.localizedDescription, privacy: .public)")
            abortFailedStart()
            throw WorkoutSessionError.unableToStart(error.localizedDescription)
        }
    }

    private func beginCollection(_ builder: HKLiveWorkoutBuilder, at startDate: Date) async throws {
        let gate = ContinuationGate()
        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            builder.beginCollection(withStart: startDate) { success, error in
                if let error {
                    gate.resume(with: .failure(error))
                } else if success {
                    gate.resume(with: .success(()))
                } else {
                    gate.resume(with: .failure(
                        WorkoutSessionError.unableToStart("系统未能开始采集训练数据。")
                    ))
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 10) {
                gate.resume(with: .failure(WorkoutSessionError.startupTimedOut))
            }
        }
    }

    private func waitUntilRunning(_ session: HKWorkoutSession) async throws {
        // `startActivity` changes the session state asynchronously. The builder
        // can finish beginning collection just before `state` becomes running,
        // especially on a physical watch, so wait for the confirmed transition.
        for _ in 0..<50 {
            if session.state == .running {
                return
            }
            if session.state == .ended {
                throw WorkoutSessionError.unableToStart("系统训练会话在启动时已结束。")
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw WorkoutSessionError.startupTimedOut
    }

    private func abortFailedStart() {
        stoppingIntentionally = true
        session?.end()
        builder?.discardWorkout()
        session = nil
        builder = nil
        collectionStarted = false
        isRunning = false
        currentHeartRate = nil
    }

    private func requestHealthAuthorization(
        using healthStore: HKHealthStore,
        toShare shareTypes: Set<HKSampleType>,
        read readTypes: Set<HKObjectType>
    ) async throws {
        let gate = ContinuationGate()
        try await withCheckedThrowingContinuation { continuation in
            gate.install(continuation)
            healthStore.requestAuthorization(
                toShare: shareTypes,
                read: readTypes
            ) { success, error in
                if let error {
                    gate.resume(with: .failure(error))
                } else if success {
                    gate.resume(with: .success(()))
                } else {
                    gate.resume(with: .failure(WorkoutSessionError.authorizationInterrupted))
                }
            }
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 45) {
                gate.resume(with: .failure(WorkoutSessionError.authorizationTimedOut))
            }
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func stopAndDiscard(at endDate: Date = Date()) async {
        stoppingIntentionally = true
        session?.end()
        if let builder, collectionStarted {
            try? await builder.endCollection(at: endDate)
            builder.discardWorkout()
        } else {
            builder?.discardWorkout()
        }
        session = nil
        builder = nil
        collectionStarted = false
        await MainActor.run {
            self.isRunning = false
            self.currentHeartRate = nil
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var hasResumed = false

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func resume(with result: Result<Void, Error>) {
        lock.lock()
        guard !hasResumed, let continuation else {
            lock.unlock()
            return
        }
        hasResumed = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(with: result)
    }
}

extension WorkoutSessionManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        if toState == .ended {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isRunning = false
                if !self.stoppingIntentionally {
                    self.onFailure?("训练会话被系统中断。")
                }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRunning = false
            if !self.stoppingIntentionally {
                self.onFailure?(error.localizedDescription)
            }
        }
    }
}

extension WorkoutSessionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(heartRateType),
              let statistics = workoutBuilder.statistics(for: heartRateType),
              let quantity = statistics.mostRecentQuantity() else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        let bpm = quantity.doubleValue(for: unit)
        let date = statistics.endDate
        DispatchQueue.main.async { [weak self] in
            self?.currentHeartRate = bpm
            self?.onHeartRate?(date, bpm)
        }
    }
}
