import AVFoundation
import XCTest
@testable import ZujianStudio

final class ReplayEngineTests: XCTestCase {
    func testRunningClocksAdvanceFromLatestSnapshot() throws {
        var initial = makeSnapshot()
        initial.elapsedTime = 12
        initial.restRemaining = 30
        initial.isWorkoutClockRunning = true
        initial.isRestClockRunning = true

        let recording = makeRecording(
            duration: 5,
            events: [
                RecordableEvent(
                    timestamp: 0,
                    kind: .lifecycle,
                    name: "recording.started",
                    snapshot: initial
                )
            ]
        )
        let frame = try ReplayEngine(recording: recording).frame(at: 2.5)

        XCTAssertEqual(frame.snapshot.elapsedTime, 14.5, accuracy: 0.001)
        XCTAssertEqual(frame.snapshot.restRemaining, 27.5, accuracy: 0.001)
    }

    func testPausedClockRemainsFrozen() throws {
        var paused = makeSnapshot()
        paused.elapsedTime = 42
        paused.restRemaining = 18
        paused.isWorkoutClockRunning = false
        paused.isRestClockRunning = false

        let recording = makeRecording(
            duration: 4,
            events: [
                RecordableEvent(
                    timestamp: 0,
                    kind: .lifecycle,
                    name: "recording.started",
                    snapshot: paused
                )
            ]
        )
        let frame = try ReplayEngine(recording: recording).frame(at: 3)

        XCTAssertEqual(frame.snapshot.elapsedTime, 42, accuracy: 0.001)
        XCTAssertEqual(frame.snapshot.restRemaining, 18, accuracy: 0.001)
    }

    func testLegacyEndActionRestoresMissingConfirmationOverlay() throws {
        var resting = makeSnapshot()
        resting.phase = .resting
        resting.completedSetCount = 1
        resting.currentSetNumber = 2

        let recording = makeRecording(
            duration: 3,
            events: [
                RecordableEvent(
                    timestamp: 0,
                    kind: .lifecycle,
                    name: "recording.started",
                    snapshot: resting
                ),
                RecordableEvent(
                    timestamp: 1,
                    kind: .action,
                    name: "workout.showEndConfirmation",
                    snapshot: resting
                ),
                RecordableEvent(
                    timestamp: 1.5,
                    kind: .timerChanged,
                    name: "restTimer.isRunning",
                    snapshot: resting
                ),
                RecordableEvent(
                    timestamp: 2,
                    kind: .action,
                    name: "workout.end",
                    value: .flag(true),
                    snapshot: resting
                )
            ]
        )
        let engine = try ReplayEngine(recording: recording)

        XCTAssertEqual(engine.frame(at: 0.9).snapshot.overlay.kind, .none)
        XCTAssertEqual(engine.frame(at: 1.6).snapshot.overlay.kind, .endConfirmation)
        XCTAssertEqual(
            engine.frame(at: 1.6).snapshot.overlay.message,
            "训练记录将保存在组间。"
        )
        XCTAssertEqual(engine.frame(at: 2.1).snapshot.overlay.kind, .none)
    }

    func testExplicitOverlayDismissalClearsConfirmation() throws {
        var waiting = makeSnapshot()
        waiting.overlay = ReplayOverlay(
            kind: .endConfirmation,
            title: "未检测到训练组",
            message: "你可以保存这次记录，也可以直接丢弃。"
        )
        var dismissed = waiting
        dismissed.overlay = .none

        let recording = makeRecording(
            duration: 2,
            events: [
                RecordableEvent(
                    timestamp: 0,
                    kind: .lifecycle,
                    name: "recording.started",
                    snapshot: makeSnapshot()
                ),
                RecordableEvent(
                    timestamp: 0.5,
                    kind: .stateChanged,
                    name: "overlay.endConfirmation",
                    value: .flag(true),
                    snapshot: waiting
                ),
                RecordableEvent(
                    timestamp: 1.25,
                    kind: .stateChanged,
                    name: "overlay.endConfirmation",
                    value: .flag(false),
                    snapshot: dismissed
                )
            ]
        )
        let engine = try ReplayEngine(recording: recording)

        XCTAssertEqual(engine.frame(at: 1).snapshot.overlay.kind, .endConfirmation)
        XCTAssertEqual(engine.frame(at: 1.5).snapshot.overlay.kind, .none)
    }

    func testStateTransitionUsesDeterministicProgress() throws {
        let waiting = makeSnapshot()
        var active = waiting
        active.phase = .setActive
        let recording = makeRecording(
            duration: 2,
            events: [
                RecordableEvent(
                    timestamp: 0,
                    kind: .lifecycle,
                    name: "recording.started",
                    snapshot: waiting
                ),
                RecordableEvent(
                    timestamp: 1,
                    kind: .stateChanged,
                    name: "workout.phase",
                    startsAnimation: true,
                    animationDuration: 0.22,
                    snapshot: active
                )
            ]
        )
        let frame = try ReplayEngine(recording: recording).frame(at: 1.11)

        XCTAssertEqual(frame.snapshot.phase, .setActive)
        XCTAssertNotNil(frame.previousSnapshot)
        XCTAssertEqual(frame.transitionProgress, 0.5, accuracy: 0.02)
    }

    func testRecordingJSONRoundTrip() throws {
        let recording = makeRecording(
            duration: 1,
            events: [
                RecordableEvent(
                    timestamp: 0,
                    kind: .lifecycle,
                    name: "recording.started",
                    snapshot: makeSnapshot()
                )
            ]
        )

        let decoded = try RecordingFileCodec.decode(RecordingFileCodec.encode(recording))
        XCTAssertEqual(decoded, recording)
    }

    @MainActor
    func testH264ExportCreatesPlayableMP4() async throws {
        var activeSnapshot = makeSnapshot()
        activeSnapshot.phase = .setActive
        activeSnapshot.elapsedTime = 4
        let recording = makeRecording(
            duration: 0.1,
            events: [
                RecordableEvent(
                    timestamp: 0,
                    kind: .lifecycle,
                    name: "recording.started",
                    snapshot: activeSnapshot
                )
            ]
        )
        let outputURL = try await ReplayVideoRenderer().export(
            recording: recording,
            options: VideoExportOptions(framesPerSecond: 30, codec: .h264),
            progress: { _ in }
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let values = try outputURL.resourceValues(forKeys: [.fileSizeKey])
        XCTAssertGreaterThan(values.fileSize ?? 0, 0)

        let asset = AVURLAsset(url: outputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(videoTracks.count, 1)
        let duration = try await asset.load(.duration)
        XCTAssertGreaterThan(duration.seconds, 0)
    }

    private func makeRecording(
        duration: TimeInterval,
        events: [RecordableEvent]
    ) -> AppRecordingDocument {
        AppRecordingDocument(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: duration,
            device: RecordingDeviceDescriptor(
                model: "Test Watch",
                systemVersion: "10.0",
                logicalWidth: 205,
                logicalHeight: 251,
                scale: 2
            ),
            app: RecordingAppDescriptor(
                bundleIdentifier: "com.example.zujian",
                version: "1.0",
                build: "1"
            ),
            events: events
        )
    }

    private func makeSnapshot() -> ReplaySnapshot {
        ReplaySnapshot(
            screen: .workout,
            screenContext: nil,
            phase: .waitingForSet,
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
            scrollPositions: [:]
        )
    }
}
