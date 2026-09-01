import XCTest
#if canImport(Zujian)
@testable import Zujian
#else
@testable import DetectionCore
#endif

private struct MotionTraceFixture: Decodable {
    let markerUptime: TimeInterval
    let samples: [MotionTraceSample]
}

private struct MotionTraceSample: Decodable {
    let uptime: TimeInterval
    let userAcceleration: TraceVector
    let rotationRate: TraceVector
    let gravity: TraceVector
    let attitude: TraceQuaternion?
}

private struct TraceVector: Decodable {
    let x: Double
    let y: Double
    let z: Double

    var motionVector: MotionVector3 {
        MotionVector3(x: x, y: y, z: z)
    }
}

private struct TraceQuaternion: Decodable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double

    var motionQuaternion: MotionQuaternion {
        MotionQuaternion(x: x, y: y, z: z, w: w)
    }
}

final class SetDetectionEngineTests: XCTestCase {
    func testSingleShakeDoesNotStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        var events: [SetDetectionEvent] = []

        for index in 0..<100 {
            let active = index == 20
            let event = engine.process(sample(
                index: index,
                start: start,
                acceleration: active ? 1.2 : 0.01,
                rotation: active ? 3.0 : 0.02
            ))
            if let event { events.append(event) }
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testSustainedMotionThenQuietProducesOneSetCycle() {
        let engine = SetDetectionEngine()
        let start = Date()
        var events: [SetDetectionEvent] = []

        for index in 0..<300 {
            let time = Double(index) / 25.0
            let isActive = time >= 1.0 && time < 6.0
            let wave = isActive ? abs(sin(time * 8.0)) : 0
            let event = engine.process(sample(
                index: index,
                start: start,
                acceleration: isActive ? 0.35 + wave * 0.45 : 0.01,
                rotation: isActive ? 0.9 + wave * 1.8 : 0.02
            ))
            if let event { events.append(event) }
        }

        XCTAssertEqual(events.count, 2)
        guard events.count == 2 else { return }
        if case .setStarted = events[0] {} else { XCTFail("第一个事件应为组开始") }
        if case .setEnded = events[1] {} else { XCTFail("第二个事件应为组结束") }
    }

    func testShortPauseInsideSetDoesNotEndSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        var endCount = 0

        for index in 0..<350 {
            let time = Double(index) / 25.0
            let active = (time >= 0.5 && time < 5.0) || (time >= 6.5 && time < 9.0)
            let wave = active ? abs(sin(time * 7.0)) : 0
            if case .setEnded? = engine.process(sample(
                index: index,
                start: start,
                acceleration: active ? 0.4 + wave * 0.4 : 0.01,
                rotation: active ? 1.0 + wave * 1.5 : 0.02
            )) {
                endCount += 1
            }
        }

        XCTAssertEqual(endCount, 1)
    }

    func testSetEndIsConfirmedAroundTwoSeconds() {
        let engine = SetDetectionEngine()
        let start = Date()
        var detectedAt: TimeInterval?
        var estimatedEnd: Date?

        for index in 0..<250 {
            let time = Double(index) / 25.0
            let active = time >= 0.5 && time < 5.0
            let wave = active ? abs(sin(time * 7.0)) : 0
            if case .setEnded(let end)? = engine.process(sample(
                index: index,
                start: start,
                acceleration: active ? 0.4 + wave * 0.4 : 0.01,
                rotation: active ? 1.0 + wave * 1.5 : 0.02
            )), detectedAt == nil {
                detectedAt = time
                estimatedEnd = end
            }
        }

        XCTAssertNotNil(detectedAt)
        XCTAssertGreaterThanOrEqual(detectedAt ?? 0, 5.0)
        XCTAssertLessThanOrEqual(detectedAt ?? .infinity, 7.25)
        XCTAssertLessThanOrEqual(
            estimatedEnd?.timeIntervalSince(start) ?? .infinity,
            5.6
        )
    }

    func testWristRaiseAfterLastRepDoesNotDelaySetEnd() {
        let engine = SetDetectionEngine()
        let start = Date()
        var detectedAt: TimeInterval?

        for index in 0..<225 {
            let time = Double(index) / 25.0
            let exercise = time >= 0.5 && time < 5.0
            let wristRaise = time >= 5.04 && time < 5.48
            let exerciseWave = exercise ? abs(sin(time * 7.0)) : 0
            let raiseProgress = wristRaise ? (time - 5.04) / 0.44 : 0
            let raiseWave = wristRaise ? sin(raiseProgress * .pi) : 0

            let acceleration: Double
            let rotation: Double
            if exercise {
                acceleration = 0.4 + exerciseWave * 0.4
                rotation = 1.0 + exerciseWave * 1.5
            } else if wristRaise {
                // Even when its overall intensity resembles a repetition, a
                // glance is still one isolated movement rather than a renewed
                // repeated pattern.
                acceleration = 0.30 + raiseWave * 0.25
                rotation = 0.8 + raiseWave * 1.0
            } else {
                acceleration = 0.01
                rotation = 0.02
            }

            if case .setEnded? = engine.process(sample(
                index: index,
                start: start,
                acceleration: acceleration,
                rotation: rotation
            )), detectedAt == nil {
                detectedAt = time
            }
        }

        XCTAssertNotNil(detectedAt)
        XCTAssertGreaterThanOrEqual(detectedAt ?? 0, 5.0)
        XCTAssertLessThanOrEqual(detectedAt ?? .infinity, 7.30)
    }

    func testWalkingImmediatelyAfterLastRepDoesNotDelaySetEnd() {
        let engine = SetDetectionEngine()
        let start = Date()
        var detectedAt: TimeInterval?

        for index in 0..<225 {
            let time = Double(index) / 25.0
            let exercise = time >= 0.5 && time < 5.0
            let walking = time >= 5.0
            let exerciseWave = exercise ? abs(sin(time * 7.0)) : 0
            let walkingWave = walking ? abs(sin(time * 10.5)) : 0

            let acceleration = exercise
                ? 0.4 + exerciseWave * 0.4
                : walking ? 0.08 + walkingWave * 0.12 : 0.01
            let rotation = exercise
                ? 1.0 + exerciseWave * 1.5
                : walking ? 0.45 + walkingWave * 0.65 : 0.02

            if case .setEnded? = engine.process(sample(
                index: index,
                start: start,
                acceleration: acceleration,
                rotation: rotation
            )), detectedAt == nil {
                detectedAt = time
            }
        }

        XCTAssertNotNil(detectedAt)
        XCTAssertGreaterThanOrEqual(detectedAt ?? 0, 5.0)
        XCTAssertLessThanOrEqual(detectedAt ?? .infinity, 7.30)
    }

    func testBriefMotionDuringQuietDoesNotRestartEndConfirmation() {
        let engine = SetDetectionEngine()
        let start = Date()
        var detectedAt: TimeInterval?

        for index in 0..<275 {
            let time = Double(index) / 25.0
            let exercise = time >= 0.5 && time < 5.0
            let incidentalMotion = time >= 6.0 && time < 6.12
            let moving = exercise || incidentalMotion
            let wave = exercise ? abs(sin(time * 7.0)) : 0.8
            if case .setEnded? = engine.process(sample(
                index: index,
                start: start,
                acceleration: moving ? 0.4 + wave * 0.4 : 0.01,
                rotation: moving ? 1.0 + wave * 1.5 : 0.02
            )), detectedAt == nil {
                detectedAt = time
            }
        }

        XCTAssertNotNil(detectedAt)
        XCTAssertLessThanOrEqual(detectedAt ?? .infinity, 8.0)
    }

    func testUnstructuredMotionAfterTwoSecondGapStillEndsSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        var endTimes: [TimeInterval] = []

        for index in 0..<350 {
            let time = Double(index) / 25.0
            let active = (time >= 0.5 && time < 5.0) || (time >= 7.08 && time < 9.0)
            let wave = active ? abs(sin(time * 7.0)) : 0
            if case .setEnded? = engine.process(sample(
                index: index,
                start: start,
                acceleration: active ? 0.4 + wave * 0.4 : 0.01,
                rotation: active ? 1.0 + wave * 1.5 : 0.02
            )) {
                endTimes.append(time)
            }
        }

        XCTAssertFalse(endTimes.isEmpty)
        XCTAssertLessThanOrEqual(endTimes.first ?? .infinity, 7.60)
    }

    func testPuttingDownPhoneDoesNotStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        var events: [SetDetectionEvent] = []

        for index in 0..<175 {
            let time = Double(index) / 25.0
            let moving = time >= 1.0 && time < 2.25
            let progress = moving ? (time - 1.0) / 1.25 : 0
            let envelope = moving ? sin(progress * .pi) : 0
            let sample = vectorSample(
                index: index,
                start: start,
                acceleration: MotionVector3(
                    x: 0.58 * envelope,
                    y: -0.24 * envelope * progress,
                    z: 0.16 * sin(progress * .pi * 0.7)
                ),
                rotation: MotionVector3(
                    x: 0.35 * envelope,
                    y: 2.2 * envelope * (1 - progress * 0.35),
                    z: -0.55 * envelope * progress
                ),
                gravity: MotionVector3(
                    x: 0.22 * progress,
                    y: 0.08 * progress,
                    z: -1
                )
            )
            if let event = engine.process(sample) { events.append(event) }
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testDumbbellPickupAndGripAdjustmentDoNotStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        var events: [SetDetectionEvent] = []

        for index in 0..<225 {
            let time = Double(index) / 25.0
            let acceleration: MotionVector3
            let rotation: MotionVector3
            let gravity: MotionVector3

            switch time {
            case 0.8..<1.55:
                let p = (time - 0.8) / 0.75
                let e = sin(p * .pi)
                acceleration = MotionVector3(x: 0.48 * e, y: 0.16 * p, z: -0.12 * e)
                rotation = MotionVector3(x: 0.3 * e, y: 1.9 * e, z: 0.45 * p)
                gravity = MotionVector3(x: 0.12 * p, y: 0.03, z: -1)
            case 1.55..<2.05:
                let p = (time - 1.55) / 0.5
                let e = sin(p * .pi * 1.5)
                acceleration = MotionVector3(x: 0.10 * e, y: -0.35 * e, z: 0.20 * p)
                rotation = MotionVector3(x: 1.4 * e, y: -0.4 * p, z: 0.7 * e)
                gravity = MotionVector3(x: 0.12, y: 0.10 * p, z: -1)
            case 2.05..<3.10:
                let p = (time - 2.05) / 1.05
                let e = sin(p * .pi)
                acceleration = MotionVector3(x: -0.18 * e, y: 0.22 * e, z: 0.65 * e)
                rotation = MotionVector3(x: -0.7 * p, y: 0.35 * e, z: 2.1 * e)
                gravity = MotionVector3(x: 0.12 - 0.20 * p, y: 0.10, z: -1)
            case 3.10..<3.75:
                let p = (time - 3.10) / 0.65
                let e = sin(p * .pi * 2.2)
                acceleration = MotionVector3(x: 0.13 * e, y: 0.25 * e, z: -0.10 * e)
                rotation = MotionVector3(x: 0.8 * e, y: -1.1 * e, z: 0.25 * p)
                gravity = MotionVector3(x: -0.08, y: 0.10 - 0.08 * p, z: -1)
            default:
                acceleration = .zero
                rotation = .zero
                gravity = .restingGravity
            }

            if let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: acceleration,
                rotation: rotation,
                gravity: gravity
            )) {
                events.append(event)
            }
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testSeparatedAdjustmentsCannotAccumulateIntoSetStart() {
        let engine = SetDetectionEngine()
        let start = Date()
        var events: [SetDetectionEvent] = []

        for index in 0..<225 {
            let time = Double(index) / 25.0
            let burstStarts = [0.8, 2.35, 3.9]
            let progress = burstStarts.compactMap { burstStart -> Double? in
                let value = (time - burstStart) / 0.52
                return (0..<1).contains(value) ? value : nil
            }.first
            let envelope = progress.map { sin($0 * .pi) } ?? 0
            let sign = burstStarts.enumerated().first(where: {
                time >= $0.element && time < $0.element + 0.52
            }).map { $0.offset.isMultiple(of: 2) ? 1.0 : -1.0 } ?? 1

            if let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: MotionVector3(
                    x: sign * 0.55 * envelope,
                    y: 0.22 * envelope,
                    z: 0.10 * envelope
                ),
                rotation: MotionVector3(
                    x: 0.3 * envelope,
                    y: sign * 2.0 * envelope,
                    z: -0.4 * envelope
                )
            )) {
                events.append(event)
            }
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testRepeatedMotionStartsSetAndExcludesPickupFromEstimatedStart() {
        let engine = SetDetectionEngine()
        let start = Date()
        var detectedAt: TimeInterval?
        var estimatedStart: TimeInterval?

        for index in 0..<225 {
            let time = Double(index) / 25.0
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if time >= 0.7 && time < 1.65 {
                let p = (time - 0.7) / 0.95
                let e = sin(p * .pi)
                motion = (
                    MotionVector3(x: 0.62 * e, y: -0.17 * p, z: 0.22 * e),
                    MotionVector3(x: 0.4 * e, y: 2.2 * e, z: 0.6 * p),
                    MotionVector3(x: 0.16 * p, y: 0.04, z: -1)
                )
            } else if time >= 1.65 && time < 7.0 {
                motion = trainingMotion(time: time - 1.65, period: 1.18)
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted(let date)? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedAt == nil {
                detectedAt = time
                estimatedStart = date.timeIntervalSince(start)
            }
        }

        XCTAssertNotNil(detectedAt)
        XCTAssertLessThanOrEqual(detectedAt ?? .infinity, 5.7)
        XCTAssertGreaterThanOrEqual(estimatedStart ?? 0, 1.40)
        XCTAssertLessThanOrEqual(estimatedStart ?? .infinity, 2.15)
    }

    func testSamplesBeforeArmAndRestEndedHapticCannotSeedSetStart() {
        let engine = SetDetectionEngine()
        let start = Date()
        engine.resetForNewWorkout(armedAtUptime: 2.0)
        engine.armStartDetection(at: 2.0, contaminationGuard: 0.42)
        var events: [SetDetectionEvent] = []

        for index in 40..<150 {
            let time = Double(index) / 25.0
            let haptic = time < 2.40
            let pickup = time >= 2.46 && time < 3.42
            let progress = pickup ? (time - 2.46) / 0.96 : 0
            let pickupEnvelope = pickup ? sin(progress * .pi) : 0
            let hapticWave = haptic ? sin(time * .pi * 24) : 0
            let acceleration = MotionVector3(
                x: haptic ? 0.8 * hapticWave : 0.60 * pickupEnvelope,
                y: pickup ? -0.18 * progress : 0,
                z: haptic ? 0.45 * hapticWave : 0.12 * pickupEnvelope
            )
            let rotation = MotionVector3(
                x: haptic ? 2.5 * hapticWave : 0.35 * pickupEnvelope,
                y: pickup ? 2.1 * pickupEnvelope : 0,
                z: pickup ? 0.5 * progress : 0
            )
            if let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: acceleration,
                rotation: rotation
            )) {
                events.append(event)
            }
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testMotionAlreadyRepeatingDuringRestStaysSuppressedAfterArm() {
        let engine = SetDetectionEngine()
        let start = Date()

        engine.beginRestObservation()
        for index in 0..<150 {
            let time = Double(index) / 25.0
            let motion = ambientRepetitiveMotion(time: time)
            engine.observeResting(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            ))
        }

        engine.armStartDetection(at: 6.0)
        var events: [SetDetectionEvent] = []
        for index in 150..<275 {
            let time = Double(index) / 25.0
            let motion = ambientRepetitiveMotion(time: time)
            if let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                events.append(event)
            }
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testWalkingThatBeginsAfterArmDoesNotStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        engine.resetForNewWorkout(armedAtUptime: 0)
        var events: [SetDetectionEvent] = []

        for index in 0..<225 {
            let time = Double(index) / 25.0
            let motion = time < 0.8
                ? (MotionVector3.zero, MotionVector3.zero, MotionVector3.restingGravity)
                : walkingMotion(time: time - 0.8)
            if let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                events.append(event)
            }
        }

        XCTAssertTrue(events.isEmpty)
    }

    func testNewRepeatedPatternAfterRestCanStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()

        engine.beginRestObservation()
        for index in 0..<125 {
            let time = Double(index) / 25.0
            let motion = walkingMotion(time: time)
            engine.observeResting(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            ))
        }

        engine.armStartDetection(at: 5.0)
        var didStart = false
        for index in 125..<275 {
            let time = Double(index) / 25.0
            let relative = time - 5.0
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if relative < 0.72 {
                motion = (.zero, .zero, .restingGravity)
            } else {
                motion = trainingMotion(time: relative - 0.72, period: 1.12)
            }
            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                didStart = true
            }
        }

        XCTAssertTrue(didStart)
    }

    func testPreviousSetPatternLetsTheSameMovementConfirmSooner() {
        let engine = SetDetectionEngine()
        let start = Date()
        var firstSetEndedAtIndex: Int?

        for index in 0..<250 {
            let time = Double(index) / 25.0
            let motion = (time >= 0.6 && time < 5.5)
                ? trainingMotion(time: time - 0.6, period: 1.18)
                : (.zero, .zero, .restingGravity)
            if case .setEnded? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                firstSetEndedAtIndex = index
                break
            }
        }

        guard let firstSetEndedAtIndex else {
            XCTFail("第一组应完成并留下动作签名")
            return
        }

        engine.beginRestObservation()
        let armIndex = firstSetEndedAtIndex + 30
        for index in (firstSetEndedAtIndex + 1)..<armIndex {
            engine.observeResting(vectorSample(
                index: index,
                start: start,
                acceleration: .zero,
                rotation: .zero
            ))
        }
        let armUptime = Double(armIndex) / 25.0
        engine.armStartDetection(at: armUptime)

        let movementStartIndex = armIndex + 10
        var detectedDelay: TimeInterval?
        for index in armIndex..<(armIndex + 110) {
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if index < movementStartIndex {
                motion = (.zero, .zero, .restingGravity)
            } else {
                motion = trainingMotion(
                    time: Double(index - movementStartIndex) / 25.0,
                    period: 1.18
                )
            }
            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                detectedDelay = Double(index - movementStartIndex) / 25.0
                break
            }
        }

        XCTAssertNotNil(detectedDelay)
        XCTAssertLessThanOrEqual(detectedDelay ?? .infinity, 3.2)
    }

    func testClearRepeatedMotionStartsByEarlyThirdRep() {
        let engine = SetDetectionEngine()
        let start = Date()
        let movementStart = 0.8
        let period = 1.18
        var detectedDelay: TimeInterval?
        var estimatedStart: TimeInterval?

        for index in 0..<115 {
            let time = Double(index) / 25.0
            let motion = time < movementStart
                ? (MotionVector3.zero, MotionVector3.zero, MotionVector3.restingGravity)
                : trainingMotion(time: time - movementStart, period: period)
            if case .setStarted(let date)? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                detectedDelay = time - movementStart
                estimatedStart = date.timeIntervalSince(start)
                break
            }
        }

        XCTAssertNotNil(detectedDelay)
        XCTAssertLessThanOrEqual(detectedDelay ?? .infinity, period * 2.35)
        XCTAssertGreaterThanOrEqual(estimatedStart ?? 0, movementStart - 0.12)
        XCTAssertLessThanOrEqual(estimatedStart ?? .infinity, movementStart + 0.35)
    }

    func testShortPauseBetweenRepetitionsDoesNotClearCandidate() {
        let engine = SetDetectionEngine()
        let start = Date()
        let movementStart = 0.6
        let activeDuration = 1.0
        let pauseDuration = 0.76
        let cycleDuration = activeDuration + pauseDuration
        var detectedDelay: TimeInterval?

        for index in 0..<170 {
            let time = Double(index) / 25.0
            let relative = time - movementStart
            let phaseTime = relative >= 0
                ? relative.truncatingRemainder(dividingBy: cycleDuration)
                : -1
            let motion = phaseTime >= 0 && phaseTime < activeDuration
                ? trainingMotion(time: phaseTime, period: activeDuration)
                : (MotionVector3.zero, MotionVector3.zero, MotionVector3.restingGravity)
            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                detectedDelay = relative
                break
            }
        }

        XCTAssertNotNil(detectedDelay)
        XCTAssertLessThanOrEqual(detectedDelay ?? .infinity, cycleDuration * 3.15)
    }

    func testModeratelyVariableRepetitionsStartByThirdRep() {
        let engine = SetDetectionEngine()
        let start = Date()
        let movementStart = 0.7
        let nominalPeriod = 1.16
        var detectedDelay: TimeInterval?

        for index in 0..<125 {
            let time = Double(index) / 25.0
            let relative = time - movementStart
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if relative < 0 {
                motion = (.zero, .zero, .restingGravity)
            } else {
                let warpedTime = relative
                    + 0.045 * sin(relative * 1.7)
                let base = trainingMotion(
                    time: warpedTime,
                    period: nominalPeriod
                )
                let amplitude = 0.88 + 0.12 * sin(relative * 1.1 + 0.3)
                motion = (
                    MotionVector3(
                        x: base.0.x * amplitude,
                        y: base.0.y * (1.04 - amplitude * 0.05),
                        z: base.0.z * (0.96 + amplitude * 0.05)
                    ),
                    MotionVector3(
                        x: base.1.x * (1.03 - amplitude * 0.04),
                        y: base.1.y * amplitude,
                        z: base.1.z * (0.97 + amplitude * 0.04)
                    ),
                    base.2
                )
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                detectedDelay = relative
                break
            }
        }

        XCTAssertNotNil(detectedDelay)
        XCTAssertLessThanOrEqual(detectedDelay ?? .infinity, nominalPeriod * 3.05)
    }

    func testThreeRepetitionsSeparatedByTwoSecondHoldsStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        let movementStart = 0.60
        let activeDuration = 0.92
        let holdDuration = 2.0
        let cycleDuration = activeDuration + holdDuration
        let repetitionCount = 3
        let expectedConfirmationDeadline = activeDuration * Double(repetitionCount)
            + holdDuration * Double(repetitionCount - 1) + 0.40
        var detectedDelay: TimeInterval?

        let totalDuration = movementStart + expectedConfirmationDeadline + 0.30
        for index in 0...Int((totalDuration * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let relative = time - movementStart
            let repetition = relative >= 0 ? Int(relative / cycleDuration) : -1
            let phaseTime = relative >= 0
                ? relative - Double(repetition) * cycleDuration
                : -1
            let motion = repetition >= 0
                && repetition < repetitionCount
                && phaseTime < activeDuration
                ? trainingMotion(time: phaseTime, period: activeDuration)
                : (MotionVector3.zero, MotionVector3.zero, MotionVector3.restingGravity)

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedDelay == nil {
                detectedDelay = relative
            }
        }

        guard let detectedDelay else {
            XCTFail("三次带 2 秒停顿的重复动作应识别为训练开始")
            return
        }
        XCTAssertLessThanOrEqual(detectedDelay, expectedConfirmationDeadline)
    }

    func testVariableTwoSecondHoldsStillAllowSetStart() {
        let engine = SetDetectionEngine()
        let start = Date()
        let movementStart = 0.60
        let activeDuration = 0.90
        let holdDurations = [2.0, 2.4, 1.8]
        var repetitionStarts = [movementStart]
        for hold in holdDurations {
            let nextStart = (repetitionStarts.last ?? movementStart)
                + activeDuration + hold
            repetitionStarts.append(nextStart)
        }
        let expectedConfirmationDeadline = (repetitionStarts.last ?? movementStart)
            + activeDuration + 0.40
        var detectedAt: TimeInterval?

        let totalDuration = expectedConfirmationDeadline + 0.30
        for index in 0...Int((totalDuration * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let repetition = repetitionStarts.firstIndex {
                time >= $0 && time < $0 + activeDuration
            }
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if let repetition {
                let phaseTime = time - repetitionStarts[repetition]
                motion = trainingMotion(time: phaseTime, period: activeDuration)
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedAt == nil {
                detectedAt = time
            }
        }

        guard let detectedAt else {
            XCTFail("停顿在 1.8–2.4 秒间变化时仍应识别重复训练")
            return
        }
        XCTAssertLessThanOrEqual(detectedAt, expectedConfirmationDeadline)
    }

    func testDifferentHandlingGesturesAcrossLongPausesDoNotStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        let gestures: [(start: TimeInterval, duration: TimeInterval)] = [
            (0.70, 0.88),
            (3.65, 0.96),
            (7.05, 0.84)
        ]
        var didStart = false

        for index in 0...Int((10.0 * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let activeGesture = gestures.indices.first {
                time >= gestures[$0].start
                    && time < gestures[$0].start + gestures[$0].duration
            }
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if let gesture = activeGesture {
                let item = gestures[gesture]
                let progress = (time - item.start) / item.duration
                let envelope = sin(progress * .pi)
                switch gesture {
                case 0: // Put the phone down: mostly a wrist rotation and reach.
                    motion = (
                        MotionVector3(
                            x: 0.58 * envelope,
                            y: -0.20 * progress,
                            z: 0.13 * sin(progress * .pi * 0.72)
                        ),
                        MotionVector3(
                            x: 0.28 * envelope,
                            y: 2.15 * envelope * (1 - progress * 0.30),
                            z: -0.52 * progress
                        ),
                        MotionVector3(x: 0.18 * progress, y: 0.04, z: -1)
                    )
                case 1: // Pick up a dumbbell: a different, more vertical path.
                    motion = (
                        MotionVector3(
                            x: -0.16 * envelope,
                            y: 0.24 * envelope,
                            z: 0.68 * envelope * (0.72 + progress * 0.28)
                        ),
                        MotionVector3(
                            x: -0.82 * progress,
                            y: 0.32 * envelope,
                            z: 2.05 * envelope
                        ),
                        MotionVector3(x: -0.12 * progress, y: 0.10, z: -1)
                    )
                default: // Adjust the grip: short, multi-axis oscillation.
                    let adjustment = sin(progress * .pi * 2.35)
                    motion = (
                        MotionVector3(
                            x: 0.12 * adjustment,
                            y: -0.38 * adjustment * (0.6 + progress * 0.4),
                            z: 0.18 * envelope
                        ),
                        MotionVector3(
                            x: 1.55 * adjustment,
                            y: -0.46 * progress,
                            z: 0.72 * envelope
                        ),
                        MotionVector3(x: -0.05, y: 0.12 * progress, z: -1)
                    )
                }
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                didStart = true
            }
        }

        XCTAssertFalse(didStart)
    }

    func testRepeatedLowInertiaWristRaisesDoNotStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        let gestureStarts: [TimeInterval] = [
            0.70, 3.50, 6.30, 9.10, 11.90, 14.70
        ]
        let gestureDuration = 0.84
        var didStart = false

        for index in 0...Int((17.0 * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let gestureStart = gestureStarts.first {
                time >= $0 && time < $0 + gestureDuration
            }
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if let gestureStart {
                let progress = (time - gestureStart) / gestureDuration
                let envelope = sin(progress * .pi)
                let tilt = 0.20 * envelope
                motion = (
                    MotionVector3(
                        x: 0.035 * sin(progress * .pi * 2),
                        y: 0.01 * envelope,
                        z: 0
                    ),
                    MotionVector3(
                        x: 0,
                        y: 0.48 * sin(progress * .pi * 2),
                        z: 0
                    ),
                    MotionVector3(
                        x: tilt,
                        y: 0,
                        z: -sqrt(max(0.80, 1 - tilt * tilt))
                    )
                )
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                didStart = true
            }
        }

        XCTAssertFalse(didStart)
    }

    func testFastVariableCadenceStartsByFourthRepetition() {
        let engine = SetDetectionEngine()
        let start = Date()
        let movementStart = 0.60
        let repetitionDurations = [0.44, 0.58, 0.47, 0.55]
        let concentricShares = [0.43, 0.57, 0.46, 0.55]
        let amplitudeScales = [0.40, 0.49, 0.43, 0.47]
        var repetitionStarts = [movementStart]
        for duration in repetitionDurations.dropLast() {
            repetitionStarts.append((repetitionStarts.last ?? movementStart) + duration)
        }
        let fourthRepetitionEnd = movementStart
            + repetitionDurations.reduce(0, +)
        var detectedAt: TimeInterval?

        let totalDuration = fourthRepetitionEnd + 0.35
        for index in 0...Int((totalDuration * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let repetition = repetitionStarts.indices.first {
                time >= repetitionStarts[$0]
                    && time < repetitionStarts[$0] + repetitionDurations[$0]
            }
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if let repetition {
                let duration = repetitionDurations[repetition]
                let progress = (time - repetitionStarts[repetition]) / duration
                let concentricShare = concentricShares[repetition]
                let phaseProgress: Double
                if progress < concentricShare {
                    phaseProgress = 0.5 * progress / concentricShare
                } else {
                    phaseProgress = 0.5
                        + 0.5 * (progress - concentricShare)
                            / (1 - concentricShare)
                }
                let base = trainingMotion(time: phaseProgress, period: 1.0)
                let scale = amplitudeScales[repetition]
                motion = (
                    MotionVector3(
                        x: base.0.x * scale,
                        y: base.0.y * (2 - scale),
                        z: base.0.z * scale
                    ),
                    MotionVector3(
                        x: base.1.x * (2 - scale),
                        y: base.1.y * scale,
                        z: base.1.z * (0.96 + scale * 0.04)
                    ),
                    base.2
                )
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedAt == nil {
                detectedAt = time
            }
        }

        guard let detectedAt else {
            XCTFail("快速且节奏有变化的重复动作应在第四次前确认")
            return
        }
        XCTAssertLessThanOrEqual(detectedAt, fourthRepetitionEnd + 0.20)
    }

    func testEightSlowUnevenHeavyRepetitionsReachConsensus() {
        var configuration = SetDetectionConfiguration.standard
        // This trace deliberately disables the strict two/three-repetition
        // routes. It must be recovered by the multi-repetition consensus path.
        configuration.minimumStartCycleSimilarity = 0.99
        configuration.minimumFastStartCycleSimilarity = 0.99
        configuration.minimumStartPatternQuality = 0.99
        configuration.minimumFastStartPatternQuality = 0.99
        configuration.minimumAdjacentMotifSimilarity = 0.98
        configuration.minimumAlternatingMotifSimilarity = 0.98
        let engine = SetDetectionEngine(configuration: configuration)
        let start = Date()
        let movementStart = 0.72
        let durations: [TimeInterval] = [
            2.65, 3.35, 2.90, 3.80, 3.10, 3.55, 2.78, 3.92
        ]
        let quietGaps: [TimeInterval] = [
            0.42, 0.70, 0.34, 0.78, 0.50, 0.64, 0.38
        ]
        let effortScales = [0.84, 1.06, 0.91, 1.16, 0.96, 1.11, 0.88, 1.20]
        let concentricShares = [0.58, 0.69, 0.54, 0.73, 0.61, 0.67, 0.56, 0.75]
        let axisDrifts = [-0.16, 0.11, -0.08, 0.18, -0.03, 0.14, -0.12, 0.20]
        var repetitionStarts = [movementStart]
        for index in 0..<(durations.count - 1) {
            repetitionStarts.append(
                repetitionStarts[index] + durations[index] + quietGaps[index]
            )
        }
        let lastEnd = (repetitionStarts.last ?? movementStart)
            + (durations.last ?? 0)
        var detectedAt: TimeInterval?
        var detectedPath: String?

        for index in 0...Int(((lastEnd + 0.50) * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let repetition = repetitionStarts.indices.first {
                time >= repetitionStarts[$0]
                    && time < repetitionStarts[$0] + durations[$0]
            }
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if let repetition {
                let duration = durations[repetition]
                let progress = (time - repetitionStarts[repetition]) / duration
                let concentricShare = concentricShares[repetition]
                let phaseProgress: Double
                if progress < concentricShare {
                    let normalized = progress / concentricShare
                    phaseProgress = 0.5 * pow(normalized, 1.08 + Double(repetition % 3) * 0.10)
                } else {
                    let normalized = (progress - concentricShare) / (1 - concentricShare)
                    phaseProgress = 0.5 + 0.5 * pow(normalized, 0.86 + Double(repetition % 2) * 0.12)
                }
                let phase = phaseProgress * 2 * Double.pi
                let scale = effortScales[repetition]
                let drift = axisDrifts[repetition]
                let instability = 0.10 * sin(phase * 2.7 + Double(repetition) * 0.83)
                let acceleration = MotionVector3(
                    x: scale * (0.38 * sin(phase) + instability),
                    y: scale * (0.20 * cos(phase + 0.24) + drift * sin(phase)),
                    z: scale * (0.16 * sin(phase * 2 - 0.31) - drift * 0.16 * cos(phase))
                )
                let rotation = MotionVector3(
                    x: scale * (0.58 * sin(phase + 0.18) + drift * cos(phase)),
                    y: scale * (1.48 * cos(phase) + instability * 1.8),
                    z: scale * (0.46 * sin(phase * 2 + 0.16) - drift * sin(phase))
                )
                let tilt = 0.050 * sin(phase) + drift * 0.018 * sin(phase * 0.5)
                let sideTilt = 0.025 * cos(phase + 0.2)
                motion = (
                    acceleration,
                    rotation,
                    MotionVector3(
                        x: tilt,
                        y: sideTilt,
                        z: -sqrt(max(0.80, 1 - tilt * tilt - sideTilt * sideTilt))
                    )
                )
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedAt == nil {
                detectedAt = time
                detectedPath = engine.diagnosticSnapshot.consensusStatus
            }
        }

        guard let detectedAt else {
            XCTFail("八次慢速、吃力且轨迹不完全稳定的重复应形成开始共识")
            return
        }
        let seventhEnd = repetitionStarts[6] + durations[6]
        XCTAssertLessThanOrEqual(detectedAt, seventhEnd + 0.45)
        XCTAssertEqual(detectedPath, "多次重复共识已通过")
    }

    func testContinuousSlowHeavyRepetitionsReachConsensusWithoutQuietGaps() {
        var configuration = SetDetectionConfiguration.standard
        configuration.minimumStartCycleSimilarity = 0.99
        configuration.minimumFastStartCycleSimilarity = 0.99
        configuration.minimumStartPatternQuality = 0.99
        configuration.minimumFastStartPatternQuality = 0.99
        configuration.minimumAdjacentMotifSimilarity = 0.98
        configuration.minimumAlternatingMotifSimilarity = 0.98
        let engine = SetDetectionEngine(configuration: configuration)
        let start = Date()
        let movementStart = 0.72
        let durations: [TimeInterval] = [
            2.40, 3.10, 2.68, 3.48, 2.82, 3.30, 2.56, 3.62
        ]
        let effortScales = [0.84, 1.05, 0.90, 1.14, 0.95, 1.09, 0.87, 1.17]
        let concentricShares = [0.55, 0.68, 0.52, 0.72, 0.60, 0.66, 0.54, 0.74]
        let axisDrifts = [-0.13, 0.09, -0.07, 0.15, -0.02, 0.12, -0.10, 0.17]
        var repetitionStarts = [movementStart]
        for duration in durations.dropLast() {
            repetitionStarts.append((repetitionStarts.last ?? movementStart) + duration)
        }
        let lastEnd = (repetitionStarts.last ?? movementStart)
            + (durations.last ?? 0)
        var detectedAt: TimeInterval?
        var detectedPath: String?

        for index in 0...Int(((lastEnd + 0.45) * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let repetition = repetitionStarts.indices.first {
                time >= repetitionStarts[$0]
                    && time < repetitionStarts[$0] + durations[$0]
            }
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if let repetition {
                let duration = durations[repetition]
                let progress = (time - repetitionStarts[repetition]) / duration
                let share = concentricShares[repetition]
                let phaseProgress: Double
                if progress < share {
                    phaseProgress = 0.5 * pow(progress / share, 1.08)
                } else {
                    phaseProgress = 0.5
                        + 0.5 * pow((progress - share) / (1 - share), 0.90)
                }
                let phase = phaseProgress * 2 * Double.pi
                let primary = sin(phase)
                let secondary = sin(phase * 2 + 0.08 * Double(repetition % 3))
                let scale = effortScales[repetition]
                let drift = axisDrifts[repetition]
                let instability = sin(phase * 3 + Double(repetition) * 0.71)
                    * sin(phase * 0.5) * 0.07
                let acceleration = MotionVector3(
                    x: scale * (0.44 * primary + instability),
                    y: scale * (0.18 * secondary + drift * primary),
                    z: scale * (0.13 * primary - drift * 0.18 * secondary)
                )
                let rotation = MotionVector3(
                    x: scale * (0.52 * secondary + drift * primary),
                    y: scale * (1.52 * primary + instability * 2.0),
                    z: scale * (0.40 * secondary - drift * primary)
                )
                let poseExcursion = 0.060 * (1 - cos(phase)) * 0.5
                let sideExcursion = 0.022 * sin(phase)
                motion = (
                    acceleration,
                    rotation,
                    MotionVector3(
                        x: poseExcursion,
                        y: sideExcursion,
                        z: -sqrt(max(
                            0.80,
                            1 - poseExcursion * poseExcursion
                                - sideExcursion * sideExcursion
                        ))
                    )
                )
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedAt == nil {
                detectedAt = time
                detectedPath = engine.diagnosticSnapshot.consensusStatus
            }
        }

        guard let detectedAt else {
            XCTFail("连续衔接、没有明显静止缝隙的慢速大重量重复也应形成共识")
            return
        }
        let seventhEnd = repetitionStarts[6] + durations[6]
        XCTAssertLessThanOrEqual(detectedAt, seventhEnd + 0.50)
        XCTAssertEqual(detectedPath, "多次重复共识已通过")
    }

    func testEightEnergeticButDifferentHandlingLoopsDoNotReachConsensus() {
        var configuration = SetDetectionConfiguration.standard
        configuration.minimumStartCycleSimilarity = 0.99
        configuration.minimumFastStartCycleSimilarity = 0.99
        configuration.minimumStartPatternQuality = 0.99
        configuration.minimumFastStartPatternQuality = 0.99
        configuration.minimumAdjacentMotifSimilarity = 0.98
        configuration.minimumAlternatingMotifSimilarity = 0.98
        let engine = SetDetectionEngine(configuration: configuration)
        let start = Date()
        let durations: [TimeInterval] = [
            1.18, 1.72, 1.34, 2.08, 1.46, 1.88, 1.26, 2.20
        ]
        let gaps: [TimeInterval] = [0.38, 0.66, 0.44, 0.74, 0.50, 0.62, 0.42]
        let accelerationAxes: [MotionVector3] = [
            .init(x: 1.00, y: 0.08, z: 0.03),
            .init(x: 0.05, y: 1.00, z: 0.08),
            .init(x: 0.04, y: 0.10, z: 1.00),
            .init(x: 0.72, y: -0.68, z: 0.05),
            .init(x: 0.70, y: 0.04, z: 0.71),
            .init(x: 0.04, y: 0.72, z: -0.69),
            .init(x: -0.78, y: 0.24, z: 0.58),
            .init(x: 0.26, y: -0.82, z: 0.51)
        ]
        let rotationAxes: [MotionVector3] = [
            .init(x: 0.06, y: 1.00, z: 0.10),
            .init(x: 0.08, y: 0.05, z: 1.00),
            .init(x: 1.00, y: 0.08, z: 0.04),
            .init(x: 0.68, y: 0.71, z: 0.06),
            .init(x: 0.05, y: -0.70, z: 0.71),
            .init(x: 0.72, y: 0.04, z: -0.69),
            .init(x: 0.20, y: 0.58, z: 0.79),
            .init(x: -0.83, y: 0.49, z: 0.26)
        ]
        var gestureStarts = [0.72]
        for index in 0..<(durations.count - 1) {
            gestureStarts.append(
                gestureStarts[index] + durations[index] + gaps[index]
            )
        }
        let finalEnd = (gestureStarts.last ?? 0) + (durations.last ?? 0)
        var detectedAt: TimeInterval?
        var detectedSnapshot: SetDetectionDiagnosticSnapshot?

        for index in 0...Int(((finalEnd + 0.50) * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let gesture = gestureStarts.indices.first {
                time >= gestureStarts[$0]
                    && time < gestureStarts[$0] + durations[$0]
            }
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if let gesture {
                let progress = (time - gestureStarts[gesture]) / durations[gesture]
                let fundamental = sin(progress * 2 * .pi)
                let harmonic = sin(progress * Double(gesture % 3 + 2) * .pi)
                let accelerationAxis = accelerationAxes[gesture]
                let rotationAxis = rotationAxes[gesture]
                let amplitude = 0.48 + Double(gesture % 4) * 0.07
                let acceleration = MotionVector3(
                    x: accelerationAxis.x * amplitude * fundamental
                        + 0.10 * harmonic,
                    y: accelerationAxis.y * amplitude * fundamental
                        - 0.08 * harmonic,
                    z: accelerationAxis.z * amplitude * fundamental
                        + 0.06 * harmonic
                )
                let rotation = MotionVector3(
                    x: rotationAxis.x * 1.85 * fundamental
                        - 0.26 * harmonic,
                    y: rotationAxis.y * 1.85 * fundamental
                        + 0.22 * harmonic,
                    z: rotationAxis.z * 1.85 * fundamental
                        + 0.18 * harmonic
                )
                let tiltX = 0.055 * accelerationAxis.x * sin(progress * .pi)
                let tiltY = 0.055 * accelerationAxis.y * sin(progress * .pi)
                motion = (
                    acceleration,
                    rotation,
                    MotionVector3(
                        x: tiltX,
                        y: tiltY,
                        z: -sqrt(max(0.80, 1 - tiltX * tiltX - tiltY * tiltY))
                    )
                )
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                detectedAt = detectedAt ?? time
                detectedSnapshot = detectedSnapshot ?? engine.diagnosticSnapshot
            }
        }

        XCTAssertNil(
            detectedAt,
            "非重复动作在 \(detectedAt ?? -1)s 被误判；\(String(describing: detectedSnapshot))"
        )
    }

    func testClearRepetitionCanConfirmAfterCandidateWindowRollsOver() {
        let engine = SetDetectionEngine()
        let start = Date()
        let movementStart = 0.60
        let nonPatternDuration = 7.80
        let repeatedMotionStart = movementStart + nonPatternDuration
        let repeatedPeriod = 0.96
        let repeatedMotionEnd = repeatedMotionStart + repeatedPeriod * 4
        var detectedAt: TimeInterval?

        let totalDuration = repeatedMotionEnd + 0.35
        for index in 0...Int((totalDuration * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if time >= movementStart && time < repeatedMotionStart {
                // Keeps the candidate alive without presenting a repeated signed
                // trajectory. Its mean energy is intentionally below a real set.
                motion = (
                    MotionVector3(x: 0.18, y: -0.025, z: 0.015),
                    MotionVector3(x: 0.04, y: 0.52, z: -0.03),
                    MotionVector3(x: 0.02, y: 0.01, z: -1)
                )
            } else if time >= repeatedMotionStart && time < repeatedMotionEnd {
                motion = trainingMotion(
                    time: time - repeatedMotionStart,
                    period: repeatedPeriod
                )
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedAt == nil {
                detectedAt = time
            }
        }

        guard let detectedAt else {
            XCTFail("候选窗口滚动后的清晰重复动作仍应能确认")
            return
        }
        XCTAssertGreaterThanOrEqual(detectedAt, repeatedMotionStart)
        XCTAssertLessThanOrEqual(detectedAt, repeatedMotionEnd + 0.20)
    }

    func testTopHoldCanSplitARepetitionAndStillStartSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        let cycleDuration = 0.80 + 2.20 + 0.80 + 0.65
        var detectedAt: TimeInterval?

        for index in 0...Int((cycleDuration * 2.5 * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let motion = pausedTopHoldMotion(time: time, repetitions: 3)
            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedAt == nil {
                detectedAt = time
            }
        }

        XCTAssertNotNil(detectedAt)
        XCTAssertLessThanOrEqual(detectedAt ?? .infinity, cycleDuration * 2.0)
    }

    func testVerySlowLowInertiaRepetitionsUsePostureEvidence() {
        let engine = SetDetectionEngine()
        let start = Date()
        let cycleDuration = 1.50 + 2.20 + 1.50 + 0.70
        var detectedAt: TimeInterval?

        for index in 0...Int((cycleDuration * 2.4 * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let motion = pausedTopHoldMotion(
                time: time,
                repetitions: 3,
                outboundDuration: 1.50,
                topHoldDuration: 2.20,
                returnDuration: 1.50,
                bottomHoldDuration: 0.70,
                motionScale: 0.12,
                maximumTilt: 0.20
            )
            if case .setStarted? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )), detectedAt == nil {
                detectedAt = time
            }
        }

        XCTAssertNotNil(detectedAt)
        XCTAssertLessThanOrEqual(detectedAt ?? .infinity, cycleDuration * 2.0)
    }

    func testTopHoldAfterActivationDoesNotEndSetPrematurely() {
        let engine = SetDetectionEngine()
        let start = Date()
        let repetitions = 3
        let outboundDuration = 0.80
        let topHoldDuration = 2.20
        let returnDuration = 0.80
        let bottomHoldDuration = 0.65
        let cycleDuration = outboundDuration + topHoldDuration
            + returnDuration + bottomHoldDuration
        let finalReturnEnd = Double(repetitions - 1) * cycleDuration
            + outboundDuration + topHoldDuration + returnDuration
        let totalDuration = Double(repetitions) * cycleDuration + 4.0
        var startCount = 0
        var endTimes: [TimeInterval] = []

        for index in 0...Int((totalDuration * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let motion = pausedTopHoldMotion(
                time: time,
                repetitions: repetitions
            )
            let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            ))
            if case .setStarted? = event {
                startCount += 1
            } else if case .setEnded? = event {
                endTimes.append(time)
            }
        }

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endTimes.count, 1)
        XCTAssertGreaterThanOrEqual(endTimes.first ?? 0, finalReturnEnd)
        XCTAssertLessThanOrEqual(endTimes.first ?? .infinity, finalReturnEnd + 2.2)
    }

    func testFastStartThenSlowLowEnergyTopHoldRemainsOneSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        let fastDuration = 4.0
        let outboundDuration = 2.0
        let topHoldDuration = 1.8
        let returnDuration = 2.0
        let finalReturnEnd = fastDuration + outboundDuration
            + topHoldDuration + returnDuration
        let totalDuration = finalReturnEnd + 4.2
        var startCount = 0
        var endTimes: [TimeInterval] = []

        for index in 0...Int((totalDuration * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if time < fastDuration {
                motion = trainingMotion(time: time, period: 0.8)
            } else {
                motion = pausedTopHoldMotion(
                    time: time - fastDuration,
                    repetitions: 1,
                    outboundDuration: outboundDuration,
                    topHoldDuration: topHoldDuration,
                    returnDuration: returnDuration,
                    bottomHoldDuration: 0.7,
                    motionScale: 0.18,
                    maximumTilt: 0.20
                )
            }
            let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            ))
            if case .setStarted? = event {
                startCount += 1
            } else if case .setEnded? = event {
                endTimes.append(time)
            }
        }

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endTimes.count, 1)
        XCTAssertGreaterThanOrEqual(endTimes.first ?? 0, finalReturnEnd)
        XCTAssertLessThanOrEqual(endTimes.first ?? .infinity, finalReturnEnd + 3.2)
    }

    func testFastStartThenTwoSecondBoundaryHoldCanContinueSameSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        let fastDuration = 4.0
        let movementDuration = 1.2
        let boundaryHoldDuration = 2.0
        let cycleDuration = movementDuration + boundaryHoldDuration
        let repetitionCount = 2
        let finalMovementEnd = fastDuration
            + Double(repetitionCount - 1) * cycleDuration
            + movementDuration
        let totalDuration = finalMovementEnd + 4.0
        var startCount = 0
        var endTimes: [TimeInterval] = []
        var estimatedEndTimes: [TimeInterval] = []

        for index in 0...Int((totalDuration * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if time < fastDuration {
                motion = trainingMotion(time: time, period: 0.8)
            } else {
                let localTime = time - fastDuration
                let repetition = Int(localTime / cycleDuration)
                let phaseTime = localTime - Double(repetition) * cycleDuration
                if repetition < repetitionCount, phaseTime < movementDuration {
                    let normalizedTime = phaseTime / movementDuration * 0.8
                    motion = trainingMotion(time: normalizedTime, period: 0.8)
                } else {
                    motion = (.zero, .zero, .restingGravity)
                }
            }
            let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            ))
            if case .setStarted? = event {
                startCount += 1
            } else if case .setEnded(let estimatedEnd)? = event {
                endTimes.append(time)
                estimatedEndTimes.append(estimatedEnd.timeIntervalSince(start))
            }
        }

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endTimes.count, 1)
        XCTAssertEqual(estimatedEndTimes.count, 1)
        XCTAssertGreaterThanOrEqual(endTimes.first ?? 0, finalMovementEnd)
        XCTAssertLessThanOrEqual(endTimes.first ?? .infinity, finalMovementEnd + 2.5)
        XCTAssertLessThanOrEqual(
            estimatedEndTimes.first ?? .infinity,
            finalMovementEnd + 0.35
        )
        XCTAssertGreaterThanOrEqual(
            estimatedEndTimes.first ?? 0,
            finalMovementEnd - 0.25
        )
    }

    func testCorrectedFalseEndTeachesAProtectedPause() {
        let engine = SetDetectionEngine()
        let start = Date()
        let correctedPause = 2.0
        let movementEnd = 1.2
        var endTimes: [TimeInterval] = []

        engine.forceActive(
            at: start,
            uptime: 0,
            correctedPause: correctedPause
        )
        for index in 0...Int(5.0 * 25) {
            let time = Double(index) / 25.0
            let baseMotion = time < movementEnd
                ? trainingMotion(time: time, period: movementEnd)
                : (.zero, .zero, .restingGravity)
            if case .setEnded? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: baseMotion.0,
                rotation: baseMotion.1,
                gravity: .restingGravity
            )) {
                endTimes.append(time)
            }
        }

        XCTAssertEqual(endTimes.count, 1)
        XCTAssertGreaterThanOrEqual(
            endTimes.first ?? 0,
            movementEnd + correctedPause + 0.20
        )
        XCTAssertLessThanOrEqual(
            endTimes.first ?? .infinity,
            movementEnd + correctedPause + 0.80
        )
    }

    func testAttitudeOnlyTopHoldAfterFastStartDoesNotEndSet() {
        let engine = SetDetectionEngine()
        let start = Date()
        let fastDuration = 4.0
        let outboundDuration = 1.4
        let holdDuration = 2.0
        let returnDuration = 1.4
        let finalReturnEnd = fastDuration + outboundDuration
            + holdDuration + returnDuration
        let totalDuration = finalReturnEnd + 4.0
        var startCount = 0
        var endTimes: [TimeInterval] = []

        for index in 0...Int((totalDuration * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let acceleration: MotionVector3
            let rotation: MotionVector3
            let yaw: Double
            if time < fastDuration {
                let phase = time / 0.8 * 2 * Double.pi
                acceleration = MotionVector3(
                    x: 0.46 * sin(phase),
                    y: 0.14 * sin(phase * 2),
                    z: 0.18 * cos(phase)
                )
                rotation = MotionVector3(x: 0.2, y: 0.3, z: 1.8 * cos(phase))
                yaw = 0.22 * sin(phase)
            } else {
                let localTime = time - fastDuration
                if localTime < outboundDuration {
                    let progress = localTime / outboundDuration
                    let envelope = sin(progress * .pi)
                    acceleration = MotionVector3(x: 0.10 * envelope, y: 0.02, z: 0)
                    rotation = MotionVector3(x: 0, y: 0, z: 0.52 * envelope)
                    yaw = 0.24 * progress
                } else if localTime < outboundDuration + holdDuration {
                    acceleration = .zero
                    rotation = .zero
                    yaw = 0.24
                } else if localTime < outboundDuration + holdDuration + returnDuration {
                    let progress = (localTime - outboundDuration - holdDuration)
                        / returnDuration
                    let envelope = sin(progress * .pi)
                    acceleration = MotionVector3(x: -0.10 * envelope, y: -0.02, z: 0)
                    rotation = MotionVector3(x: 0, y: 0, z: -0.52 * envelope)
                    yaw = 0.24 * (1 - progress)
                } else {
                    acceleration = .zero
                    rotation = .zero
                    yaw = 0
                }
            }
            let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: acceleration,
                rotation: rotation,
                gravity: .restingGravity,
                attitude: yawQuaternion(yaw)
            ))
            if case .setStarted? = event {
                startCount += 1
            } else if case .setEnded? = event {
                endTimes.append(time)
            }
        }

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endTimes.count, 1)
        XCTAssertGreaterThanOrEqual(endTimes.first ?? 0, finalReturnEnd)
        XCTAssertLessThanOrEqual(endTimes.first ?? .infinity, finalReturnEnd + 3.2)
    }

    func testSlowWristRaiseAfterLastRepDoesNotExtendProtectedEnd() {
        let engine = SetDetectionEngine()
        let start = Date()
        let finalReturnEnd = 12.70
        let wristRaiseStart = 12.90
        let wristRaiseDuration = 0.60
        var endTimes: [TimeInterval] = []

        for index in 0...Int((18.0 * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if time < finalReturnEnd {
                motion = pausedTopHoldMotion(time: time, repetitions: 3)
            } else if time >= wristRaiseStart
                        && time < wristRaiseStart + wristRaiseDuration {
                let progress = (time - wristRaiseStart) / wristRaiseDuration
                let tilt = 0.28 * progress
                motion = (
                    MotionVector3(x: 0.015 * sin(progress * .pi), y: 0, z: 0),
                    MotionVector3(x: 0, y: 0.42, z: 0),
                    MotionVector3(
                        x: tilt,
                        y: 0,
                        z: -sqrt(max(0.80, 1 - tilt * tilt))
                    )
                )
            } else if time >= wristRaiseStart + wristRaiseDuration {
                let tilt = 0.28
                motion = (
                    .zero,
                    .zero,
                    MotionVector3(
                        x: tilt,
                        y: 0,
                        z: -sqrt(max(0.80, 1 - tilt * tilt))
                    )
                )
            } else {
                motion = (.zero, .zero, .restingGravity)
            }

            if case .setEnded? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                endTimes.append(time)
            }
        }

        XCTAssertEqual(endTimes.count, 1)
        XCTAssertLessThanOrEqual(endTimes.first ?? .infinity, finalReturnEnd + 2.2)
    }

    func testRepeatedPartialHandlingPrefixesCannotRollEndDeadline() {
        var configuration = SetDetectionConfiguration.standard
        // Keep this trace deterministic: every short handling fragment looks
        // just plausible enough to exercise the continuation-prefix route,
        // but none of them closes a complete repetition.
        configuration.minimumBoundaryContinuationPrefixSimilarity = -1
        configuration.minimumIncompleteSlowOutgoingPrefixSimilarity = -1
        configuration.continuationPrefixDuration = 0.20
        configuration.minimumContinuationMotionRatio = 0.12
        let engine = SetDetectionEngine(configuration: configuration)
        let start = Date()
        let exerciseEnd = 4.0
        let handlingStarts = [5.20, 6.65, 8.10, 9.55]
        let handlingDuration = 0.42
        var endTimes: [TimeInterval] = []

        for index in 0...Int(13.0 * 25) {
            let time = Double(index) / 25.0
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if time < exerciseEnd {
                motion = trainingMotion(time: time, period: 0.8)
            } else if let gestureIndex = handlingStarts.lastIndex(where: {
                time >= $0
            }), time < handlingStarts[gestureIndex] + handlingDuration {
                let progress = (time - handlingStarts[gestureIndex])
                    / handlingDuration
                let tilt = 0.055 * progress
                motion = (
                    MotionVector3(
                        x: 0.16 * sin(progress * .pi),
                        y: 0.025 * Double(gestureIndex + 1),
                        z: 0
                    ),
                    MotionVector3(
                        x: 0.08 * Double(gestureIndex),
                        y: 0.78,
                        z: 0.10 * sin(progress * .pi)
                    ),
                    MotionVector3(
                        x: tilt,
                        y: 0,
                        z: -sqrt(max(0.80, 1 - tilt * tilt))
                    )
                )
            } else {
                motion = (
                    .zero,
                    .zero,
                    .restingGravity
                )
            }

            if case .setEnded? = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )) {
                endTimes.append(time)
            }
        }

        XCTAssertFalse(endTimes.isEmpty)
        XCTAssertLessThanOrEqual(
            endTimes.first ?? .infinity,
            exerciseEnd + configuration.maximumProtectedEndDuration + 0.30
        )
    }

    func testAnonymizedRecord001DoesNotRollEndAnchor() throws {
#if SWIFT_PACKAGE
        let bundle = Bundle.module
#else
        let bundle = Bundle(for: SetDetectionEngineTests.self)
#endif
        let fixtureURL = try XCTUnwrap(bundle.url(
            forResource: "record001_anonymized_motion",
            withExtension: "json"
        ))
        let fixture = try JSONDecoder().decode(
            MotionTraceFixture.self,
            from: Data(contentsOf: fixtureURL)
        )
        let firstUptime = try XCTUnwrap(fixture.samples.first?.uptime)
        let engine = SetDetectionEngine()
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var startCount = 0
        var detectedEndUptime: TimeInterval?
        var estimatedEndUptime: TimeInterval?

        for trace in fixture.samples {
            let sample = MotionSample(
                date: baseDate.addingTimeInterval(trace.uptime - firstUptime),
                uptime: trace.uptime,
                userAcceleration: trace.userAcceleration.motionVector,
                rotationRate: trace.rotationRate.motionVector,
                gravity: trace.gravity.motionVector,
                attitude: trace.attitude?.motionQuaternion
            )
            let event = engine.process(sample)
            if case .setStarted? = event {
                startCount += 1
            } else if case .setEnded(let estimatedEnd)? = event {
                detectedEndUptime = trace.uptime
                estimatedEndUptime = firstUptime
                    + estimatedEnd.timeIntervalSince(baseDate)
                break
            }
        }

        let detectedDelay = try XCTUnwrap(detectedEndUptime)
            - fixture.markerUptime
        let estimatedDelay = try XCTUnwrap(estimatedEndUptime)
            - fixture.markerUptime
        XCTAssertEqual(startCount, 1)
        XCTAssertLessThanOrEqual(detectedDelay, 25.0)
        XCTAssertLessThanOrEqual(estimatedDelay, 21.6)
        XCTAssertLessThanOrEqual(detectedDelay - estimatedDelay, 3.5)
    }

    func testUnfinishedTopHoldStillEndsAtABoundedDeadline() {
        let engine = SetDetectionEngine()
        let start = Date()
        let cycleDuration = 0.80 + 2.20 + 0.80 + 0.65
        let finalOutboundEnd = cycleDuration + 0.80
        let maximumTilt = 0.18
        let heldGravity = MotionVector3(
            x: maximumTilt,
            y: 0,
            z: -sqrt(max(0.80, 1 - maximumTilt * maximumTilt))
        )
        var startCount = 0
        var endTimes: [TimeInterval] = []

        for index in 0...Int(((finalOutboundEnd + 5.0) * 25).rounded(.up)) {
            let time = Double(index) / 25.0
            let motion: (MotionVector3, MotionVector3, MotionVector3)
            if time < finalOutboundEnd {
                motion = pausedTopHoldMotion(time: time, repetitions: 3)
            } else {
                motion = (.zero, .zero, heldGravity)
            }
            let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            ))
            if case .setStarted? = event {
                startCount += 1
            } else if case .setEnded? = event {
                endTimes.append(time)
            }
        }

        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(endTimes.count, 1)
        XCTAssertGreaterThanOrEqual(endTimes.first ?? 0, finalOutboundEnd)
        XCTAssertLessThanOrEqual(endTimes.first ?? .infinity, finalOutboundEnd + 4.2)
    }

    func testRestFidgetingDoesNotInflateStartThreshold() {
        let engine = SetDetectionEngine()
        let start = Date()
        engine.beginRestObservation()

        for index in 0..<250 {
            let time = Double(index) / 25.0
            let phase = time.truncatingRemainder(dividingBy: 4.0)
            let fidgeting = phase < 2.8
            engine.observeResting(MotionSample(
                date: start.addingTimeInterval(time),
                uptime: time,
                accelerationMagnitude: fidgeting ? 0.12 : 0.01,
                rotationMagnitude: fidgeting ? 0.50 : 0.02
            ))
        }

        XCTAssertLessThanOrEqual(engine.currentStartThreshold, 0.155)
    }

    func testHeartRateInflectionCanOnlySupportRepeatedMotion() {
        var strictConfiguration = SetDetectionConfiguration.standard
        strictConfiguration.minimumFastStartPatternQuality = 1.02
        strictConfiguration.minimumStartPatternQuality = 1.10
        let motionOnlyEngine = SetDetectionEngine(configuration: strictConfiguration)
        let supportedEngine = SetDetectionEngine(configuration: strictConfiguration)
        let start = Date()
        let heartRateHistory: [(TimeInterval, Double)] = [
            (-16, 144), (-14, 141), (-12, 138), (-10, 136), (-8, 134),
            (-6, 133), (-4, 136), (-2, 141), (0, 147)
        ]
        for (time, bpm) in heartRateHistory {
            supportedEngine.observeHeartRate(
                date: start.addingTimeInterval(time),
                bpm: bpm
            )
        }

        var motionOnlyStarted = false
        var supportedStarted = false
        let movementStart = 0.4
        for index in 0..<90 {
            let time = Double(index) / 25.0
            let motion = time < movementStart
                ? (MotionVector3.zero, MotionVector3.zero, MotionVector3.restingGravity)
                : trainingMotion(time: time - movementStart, period: 1.18)
            let sample = vectorSample(
                index: index,
                start: start,
                acceleration: motion.0,
                rotation: motion.1,
                gravity: motion.2
            )
            if case .setStarted? = motionOnlyEngine.process(sample) {
                motionOnlyStarted = true
            }
            if case .setStarted? = supportedEngine.process(sample) {
                supportedStarted = true
            }
        }

        XCTAssertFalse(motionOnlyStarted)
        XCTAssertTrue(supportedStarted)
    }

    func testRisingHeartRateCannotTurnOneHandlingMotionIntoASet() {
        let engine = SetDetectionEngine()
        let start = Date()
        let heartRateHistory: [(TimeInterval, Double)] = [
            (-16, 144), (-14, 141), (-12, 138), (-10, 136), (-8, 134),
            (-6, 133), (-4, 136), (-2, 141), (0, 147)
        ]
        for (time, bpm) in heartRateHistory {
            engine.observeHeartRate(date: start.addingTimeInterval(time), bpm: bpm)
        }

        var events: [SetDetectionEvent] = []
        for index in 0..<125 {
            let time = Double(index) / 25.0
            let moving = time >= 0.7 && time < 1.85
            let progress = moving ? (time - 0.7) / 1.15 : 0
            let envelope = moving ? sin(progress * .pi) : 0
            let event = engine.process(vectorSample(
                index: index,
                start: start,
                acceleration: MotionVector3(
                    x: 0.62 * envelope,
                    y: -0.20 * envelope * progress,
                    z: 0.12 * envelope
                ),
                rotation: MotionVector3(
                    x: 0.35 * envelope,
                    y: 2.25 * envelope,
                    z: 0.48 * progress
                )
            ))
            if let event { events.append(event) }
        }

        XCTAssertTrue(events.isEmpty)
    }

    private func sample(
        index: Int,
        start: Date,
        acceleration: Double,
        rotation: Double
    ) -> MotionSample {
        let uptime = Double(index) / 25.0
        return MotionSample(
            date: start.addingTimeInterval(uptime),
            uptime: uptime,
            accelerationMagnitude: acceleration,
            rotationMagnitude: rotation
        )
    }

    private func vectorSample(
        index: Int,
        start: Date,
        acceleration: MotionVector3,
        rotation: MotionVector3,
        gravity: MotionVector3 = .restingGravity,
        attitude: MotionQuaternion? = nil
    ) -> MotionSample {
        let uptime = Double(index) / 25.0
        return MotionSample(
            date: start.addingTimeInterval(uptime),
            uptime: uptime,
            userAcceleration: acceleration,
            rotationRate: rotation,
            gravity: gravity,
            attitude: attitude
        )
    }

    private func yawQuaternion(_ angle: Double) -> MotionQuaternion {
        MotionQuaternion(
            x: 0,
            y: 0,
            z: sin(angle / 2),
            w: cos(angle / 2)
        )
    }

    private func trainingMotion(
        time: TimeInterval,
        period: TimeInterval
    ) -> (MotionVector3, MotionVector3, MotionVector3) {
        let phase = time / period * 2 * Double.pi
        let acceleration = MotionVector3(
            x: 0.54 * sin(phase),
            y: 0.16 * sin(phase * 2 + 0.25),
            z: 0.24 * cos(phase)
        )
        let rotation = MotionVector3(
            x: 0.45 * sin(phase + 0.35),
            y: 2.05 * cos(phase),
            z: 0.62 * sin(phase * 2 - 0.2)
        )
        let tilt = 0.13 * sin(phase)
        let gravity = MotionVector3(
            x: tilt,
            y: 0.04 * cos(phase),
            z: -sqrt(max(0.80, 1 - tilt * tilt))
        )
        return (acceleration, rotation, gravity)
    }

    private func pausedTopHoldMotion(
        time: TimeInterval,
        repetitions: Int,
        outboundDuration: TimeInterval = 0.80,
        topHoldDuration: TimeInterval = 2.20,
        returnDuration: TimeInterval = 0.80,
        bottomHoldDuration: TimeInterval = 0.65,
        motionScale: Double = 1.0,
        maximumTilt: Double = 0.18
    ) -> (MotionVector3, MotionVector3, MotionVector3) {
        let cycleDuration = outboundDuration + topHoldDuration
            + returnDuration + bottomHoldDuration
        guard time >= 0 else {
            return (.zero, .zero, .restingGravity)
        }
        let repetition = Int(time / cycleDuration)
        guard repetition < repetitions else {
            return (.zero, .zero, .restingGravity)
        }
        let phaseTime = time - Double(repetition) * cycleDuration
        if phaseTime < outboundDuration {
            let progress = phaseTime / outboundDuration
            let envelope = sin(progress * .pi)
            let tilt = maximumTilt * progress
            return (
                MotionVector3(
                    x: 0.44 * motionScale * sin(progress * .pi * 2),
                    y: 0.14 * motionScale * envelope,
                    z: 0.11 * motionScale * cos(progress * .pi)
                ),
                MotionVector3(
                    x: 0.28 * motionScale * envelope,
                    y: 1.75 * motionScale * envelope,
                    z: 0.22 * motionScale * sin(progress * .pi * 2)
                ),
                MotionVector3(
                    x: tilt,
                    y: 0.025 * envelope,
                    z: -sqrt(max(0.80, 1 - tilt * tilt))
                )
            )
        }

        if phaseTime < outboundDuration + topHoldDuration {
            let tilt = maximumTilt
            return (
                .zero,
                .zero,
                MotionVector3(
                    x: tilt,
                    y: 0,
                    z: -sqrt(max(0.80, 1 - tilt * tilt))
                )
            )
        }

        let returnStart = outboundDuration + topHoldDuration
        if phaseTime < returnStart + returnDuration {
            let progress = (phaseTime - returnStart) / returnDuration
            let envelope = sin(progress * .pi)
            let tilt = maximumTilt * (1 - progress)
            return (
                MotionVector3(
                    x: -0.44 * motionScale * sin(progress * .pi * 2),
                    y: -0.14 * motionScale * envelope,
                    z: -0.11 * motionScale * cos(progress * .pi)
                ),
                MotionVector3(
                    x: -0.28 * motionScale * envelope,
                    y: -1.75 * motionScale * envelope,
                    z: -0.22 * motionScale * sin(progress * .pi * 2)
                ),
                MotionVector3(
                    x: tilt,
                    y: -0.025 * envelope,
                    z: -sqrt(max(0.80, 1 - tilt * tilt))
                )
            )
        }

        return (.zero, .zero, .restingGravity)
    }

    private func walkingMotion(
        time: TimeInterval
    ) -> (MotionVector3, MotionVector3, MotionVector3) {
        let phase = time / 0.92 * 2 * Double.pi
        let acceleration = MotionVector3(
            x: 0.13 * sin(phase),
            y: 0.06 * sin(phase * 2),
            z: 0.17 * abs(sin(phase))
        )
        let rotation = MotionVector3(
            x: 0.16 * sin(phase * 2),
            y: 0.82 * cos(phase),
            z: 0.20 * sin(phase)
        )
        let gravity = MotionVector3(
            x: 0.07 * sin(phase),
            y: 0.02 * cos(phase),
            z: -1
        )
        return (acceleration, rotation, gravity)
    }

    private func ambientRepetitiveMotion(
        time: TimeInterval
    ) -> (MotionVector3, MotionVector3, MotionVector3) {
        let phase = time / 0.94 * 2 * Double.pi
        let acceleration = MotionVector3(
            x: 0.18 * sin(phase * 2),
            y: 0.42 * sin(phase),
            z: 0.22 * cos(phase)
        )
        let rotation = MotionVector3(
            x: 1.65 * cos(phase),
            y: 0.28 * sin(phase * 2),
            z: 1.10 * sin(phase)
        )
        let gravity = MotionVector3(
            x: 0.03 * cos(phase),
            y: 0.11 * sin(phase),
            z: -1
        )
        return (acceleration, rotation, gravity)
    }
}
