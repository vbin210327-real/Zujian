import Foundation

struct MotionVector3: Equatable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = MotionVector3(x: 0, y: 0, z: 0)
    static let restingGravity = MotionVector3(x: 0, y: 0, z: -1)

    var magnitude: Double {
        sqrt(x * x + y * y + z * z)
    }

    func interpolated(to other: MotionVector3, fraction: Double) -> MotionVector3 {
        MotionVector3(
            x: x + (other.x - x) * fraction,
            y: y + (other.y - y) * fraction,
            z: z + (other.z - z) * fraction
        )
    }

    func smoothed(toward other: MotionVector3, alpha: Double) -> MotionVector3 {
        interpolated(to: other, fraction: alpha)
    }

    func dot(_ other: MotionVector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }
}

struct MotionQuaternion: Equatable {
    let x: Double
    let y: Double
    let z: Double
    let w: Double

    static let identity = MotionQuaternion(x: 0, y: 0, z: 0, w: 1)

    private var normalizedComponents: (x: Double, y: Double, z: Double, w: Double) {
        let length = sqrt(x * x + y * y + z * z + w * w)
        guard length > 0.000_001 else { return (0, 0, 0, 1) }
        return (x / length, y / length, z / length, w / length)
    }

    func angularDistance(to other: MotionQuaternion) -> Double {
        let lhs = normalizedComponents
        let rhs = other.normalizedComponents
        let dot = abs(lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z + lhs.w * rhs.w)
        return 2 * acos(min(1, max(-1, dot)))
    }

    func interpolated(to other: MotionQuaternion, fraction: Double) -> MotionQuaternion {
        let lhs = normalizedComponents
        var rhs = other.normalizedComponents
        let dot = lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z + lhs.w * rhs.w
        if dot < 0 {
            rhs = (-rhs.x, -rhs.y, -rhs.z, -rhs.w)
        }
        let value = MotionQuaternion(
            x: lhs.x + (rhs.x - lhs.x) * fraction,
            y: lhs.y + (rhs.y - lhs.y) * fraction,
            z: lhs.z + (rhs.z - lhs.z) * fraction,
            w: lhs.w + (rhs.w - lhs.w) * fraction
        )
        let normalized = value.normalizedComponents
        return MotionQuaternion(
            x: normalized.x,
            y: normalized.y,
            z: normalized.z,
            w: normalized.w
        )
    }
}

struct MotionSample: Equatable {
    let date: Date
    let uptime: TimeInterval
    let userAcceleration: MotionVector3
    let rotationRate: MotionVector3
    let gravity: MotionVector3
    let attitude: MotionQuaternion?

    var accelerationMagnitude: Double { userAcceleration.magnitude }
    var rotationMagnitude: Double { rotationRate.magnitude }

    init(
        date: Date,
        uptime: TimeInterval,
        userAcceleration: MotionVector3,
        rotationRate: MotionVector3,
        gravity: MotionVector3,
        attitude: MotionQuaternion? = nil
    ) {
        self.date = date
        self.uptime = uptime
        self.userAcceleration = userAcceleration
        self.rotationRate = rotationRate
        self.gravity = gravity
        self.attitude = attitude
    }

    // Keeps simple magnitude-only traces useful for regression tests. Real
    // watch samples always use the signed six-axis initializer above.
    init(
        date: Date,
        uptime: TimeInterval,
        accelerationMagnitude: Double,
        rotationMagnitude: Double
    ) {
        self.init(
            date: date,
            uptime: uptime,
            userAcceleration: MotionVector3(x: accelerationMagnitude, y: 0, z: 0),
            rotationRate: MotionVector3(x: rotationMagnitude, y: 0, z: 0),
            gravity: .restingGravity
        )
    }
}

struct SetDetectionConfiguration: Equatable {
    var accelerationScale: Double = 1.25
    var rotationScale: Double = 3.5
    var accelerationWeight: Double = 0.62
    var rotationWeight: Double = 0.38
    var smoothingAlpha: Double = 0.22
    var trajectorySmoothingAlpha: Double = 0.30
    var windowDuration: TimeInterval = 1.4
    var minimumStartPeriod: TimeInterval = 0.52
    var maximumStartPeriod: TimeInterval = 6.0
    var startPeriodSearchStep: TimeInterval = 0.08
    var startCandidateMaximumDuration: TimeInterval = 12.8
    var startCandidateQuietResetDuration: TimeInterval = 0.92
    var startCandidatePatternQuietResetDuration: TimeInterval = 1.28
    var startEvidenceGraceDuration: TimeInterval = 0.40
    var startAnalysisInterval: TimeInterval = 0.12
    var startPatternSampleCount: Int = 20
    var minimumStartActiveRatio: Double = 0.26
    var targetStartActiveRatio: Double = 0.58
    var minimumStartMeanScoreRatio: Double = 1.08
    var minimumFastStartMeanScoreRatio: Double = 1.22
    var minimumStartCycleSimilarity: Double = 0.48
    var minimumFastStartCycleSimilarity: Double = 0.66
    var minimumStartPatternQuality: Double = 0.62
    var minimumFastStartPatternQuality: Double = 0.78
    var minimumStartReversalScore: Double = 0.18
    var minimumFastStartReversalScore: Double = 0.36
    var minimumKnownPatternSimilarity: Double = 0.52
    var maximumKnownPatternConfidenceBonus: Double = 0.06
    var minimumAmbientPatternSimilarity: Double = 0.78
    var ambientPatternPenaltyFloor: Double = 0.58
    var maximumAmbientPatternPenalty: Double = 0.08
    var minimumStartEnergyBalance: Double = 0.18
    var maximumCycleAccelerationShareDifference: Double = 0.45
    var maximumStartImpulseShare: Double = 0.74
    var startConfirmationDuration: TimeInterval = 0.16
    var fastStartConfirmationDuration: TimeInterval = 0.10
    var knownPatternConfirmationDuration: TimeInterval = 0.08
    var minimumMotionQualityForHeartRateSupport: Double = 0.54
    var ambientObservationDuration: TimeInterval = 6.5
    var ambientQuietReleaseDuration: TimeInterval = 0.62
    var defaultEndConfirmationDuration: TimeInterval = 1.70
    var minimumEndConfirmationDuration: TimeInterval = 1.65
    var maximumEndConfirmationDuration: TimeInterval = 1.90
    var maximumResumptionGraceDuration: TimeInterval = 2.55
    var cadenceEndMultiplier: Double = 1.7
    var endCandidateActivationDelay: TimeInterval = 0.08
    var resumptionWindowDuration: TimeInterval = 0.56
    var requiredResumptionRatio: Double = 0.56
    var minimumResumptionSpan: TimeInterval = 0.36
    var continuationScoreFraction: Double = 0.68
    var continuationStartThresholdFraction: Double = 0.95
    var continuationProfileTolerance: Double = 0.24
    var activeScoreLearningRate: Double = 0.08
    var minimumPeakInterval: TimeInterval = 0.28
    var maximumPeakInterval: TimeInterval = 2.8
    var minimumSetDuration: TimeInterval = 3.0
    var baseStartThreshold: Double = 0.13
    var baseEndThreshold: Double = 0.06
    var adaptiveStartOffset: Double = 0.095
    var adaptiveEndOffset: Double = 0.035
    var baselineLearningRate: Double = 0.018
    var baselineObservationDuration: TimeInterval = 8.0
    var baselinePercentile: Double = 0.25
    var maximumBaselineScore: Double = 0.075

    // Pause-tolerant start path. Continuous repetitions still use the periodic
    // matcher above; these values describe distinct movement motifs separated
    // by an intentional hold.
    var motifPreRollDuration: TimeInterval = 0.24
    var motifActivityLookbackDuration: TimeInterval = 0.24
    var motifQuietBoundaryDuration: TimeInterval = 0.16
    var motifMaximumGapDuration: TimeInterval = 5.0
    var motifMaximumHistoryDuration: TimeInterval = 36.0
    var motifMinimumDuration: TimeInterval = 0.28
    var motifMaximumDuration: TimeInterval = 6.2
    var motifActivityThresholdFraction: Double = 0.48
    var motifPeakThresholdFraction: Double = 0.72
    var motifMinimumGravityExcursion: Double = 0.035
    var motifGravityActivityExcursion: Double = 0.014
    var motifSampleCount: Int = 18
    var minimumAdjacentMotifSimilarity: Double = 0.70
    var minimumAlternatingMotifSimilarity: Double = 0.67
    var minimumMotifReturnScore: Double = 0.70
    var minimumKnownMotifSimilarity: Double = 0.64
    var minimumAmbientMotifSimilarity: Double = 0.82
    var motifHeartRateThresholdReduction: Double = 0.30

    // Slow, heavy repetitions are often individually noisy. This rescue path
    // lets several independently complete loops form a consensus instead of
    // requiring every adjacent pair to be a near-identical waveform.
    var repetitionConsensusMaximumCount: Int = 8
    var repetitionConsensusMinimumVotes: Int = 4
    var repetitionConsensusMinimumDuration: TimeInterval = 0.85
    var repetitionConsensusMinimumPeriod: TimeInterval = 1.30
    var repetitionConsensusMinimumPeakRatio: Double = 0.62
    var repetitionConsensusMinimumLoopQuality: Double = 0.30
    var repetitionConsensusMembershipSimilarity: Double = 0.34
    var repetitionConsensusFourVoteSimilarity: Double = 0.50
    var repetitionConsensusFiveVoteSimilarity: Double = 0.43
    var repetitionConsensusSixVoteSimilarity: Double = 0.37
    var repetitionConsensusMinimumAxisSimilarity: Double = 0.56
    var repetitionConsensusMinimumSignedSimilarity: Double = 0.18
    var repetitionConsensusAmbientSimilarity: Double = 0.78

    // A normal set still ends quickly. Only a start pattern that has already
    // proved long holds, or a clearly incomplete posture excursion, receives
    // this bounded extension.
    var normalEndHardDeadlineDuration: TimeInterval = 2.20
    var maximumNormalEndSequenceDuration: TimeInterval = 3.25
    var maximumProtectedEndDuration: TimeInterval = 3.8
    var endAnchorEstimationTolerance: TimeInterval = 0.16
    var continuationCompletionGraceDuration: TimeInterval = 1.35
    var protectedEndPauseMargin: TimeInterval = 0.44
    var incompleteExcursionEndDuration: TimeInterval = 3.2
    var minimumIncompleteGravityAngle: Double = 0.065
    var continuationPrefixDuration: TimeInterval = 0.28
    var continuationGravityReturnAngle: Double = 0.014
    var minimumBoundaryContinuationPrefixSimilarity: Double = 0.54
    var minimumIncompleteContinuationPrefixSimilarity: Double = 0.32
    var minimumContinuationMotionRatio: Double = 0.24
    var minimumCompletedIncompleteContinuationSimilarity: Double = 0.45

    // While a set is active, low-amplitude but directionally coherent motion
    // remains part of the repetition. This prevents the slow tail of a rep
    // from being counted as silence before the wrist has actually stopped.
    var semanticProgressLookbackDuration: TimeInterval = 0.44
    var semanticProgressTailDuration: TimeInterval = 0.16
    var minimumSemanticProgressDuration: TimeInterval = 0.24
    var minimumSemanticGravityProgress: Double = 0.010
    var minimumSemanticAttitudeProgress: Double = 0.014
    var minimumSemanticTailPoseProgress: Double = 0.0035
    var minimumSemanticRotationTravel: Double = 0.030
    var minimumSemanticProgressEfficiency: Double = 0.48
    var semanticProgressProfileTolerance: Double = 0.34
    var minimumSlowMotionEvidenceDuration: TimeInterval = 0.52
    var recentSlowMotionProtectionWindow: TimeInterval = 0.96
    var slowCadenceEndDuration: TimeInterval = 2.85
    var boundaryEndConfirmationDuration: TimeInterval = 1.90
    var minimumLearnedPauseDuration: TimeInterval = 0.70
    var minimumIncompleteSlowOutgoingPrefixSimilarity: Double = 0.38

    static let standard = SetDetectionConfiguration()
}

enum SetDetectionEvent: Equatable {
    case setStarted(estimatedStart: Date)
    case setEnded(estimatedEnd: Date)
}

struct SetDetectionDiagnosticSnapshot: Codable, Equatable, Sendable {
    let phase: String
    let smoothedMotionScore: Double
    let baselineScore: Double
    let startThreshold: Double
    let endThreshold: Double
    let periodicCandidateDuration: TimeInterval
    let completedMotifCount: Int
    let consensusVoteCount: Int
    let consensusAverageSimilarity: Double
    let consensusRequiredSimilarity: Double
    let consensusStatus: String
    let endCandidateDuration: TimeInterval
    let endHardDeadlineRemaining: TimeInterval?
    let activeExpectedPause: TimeInterval
    let endProtectionRemaining: TimeInterval?
}

final class SetDetectionEngine {
    private enum Phase {
        case idle
        case active
    }

    private struct WindowPoint {
        let date: Date
        let uptime: TimeInterval
        let score: Double
        let rawScore: Double
        let accelerationShare: Double
        let acceleration: MotionVector3
        let rotation: MotionVector3
        let gravity: MotionVector3
        let rawGravity: MotionVector3
        let attitude: MotionQuaternion?
    }

    private struct PatternSignature {
        let period: TimeInterval
        let phaseSampleCount: Int
        let normalizedWaveform: [Double]
        let accelerationShare: Double
    }

    private struct StartPatternMatch {
        let firstCycleStart: WindowPoint
        let period: TimeInterval
        let cycleSimilarity: Double
        let activeRatio: Double
        let meanScoreRatio: Double
        let energyBalance: Double
        let reversalScore: Double
        let impulseShare: Double
        let quality: Double
        let signature: PatternSignature
    }

    private struct StartDecision {
        let match: StartPatternMatch
        let estimatedStart: WindowPoint
        let confirmationDuration: TimeInterval
    }

    private struct MotionMotif {
        let start: WindowPoint
        let end: WindowPoint
        let duration: TimeInterval
        let points: [WindowPoint]
        let samples: [[Double]]
        let normalizedWaveform: [Double]
        let accelerationShare: Double
        let peakScoreRatio: Double
        let gravityExcursion: Double
        let integratedRotation: MotionVector3
        let rotationTravel: Double
    }

    private struct MotifStartDecision {
        let estimatedStart: WindowPoint
        let representative: MotionMotif
        let expectedPeriod: TimeInterval
        let expectedPause: TimeInterval
    }

    private struct BaselineObservation {
        let uptime: TimeInterval
        let score: Double
    }

    let configuration: SetDetectionConfiguration

    private var phase: Phase = .idle
    private var window: [WindowPoint] = []
    private var smoothedScore = 0.0
    private var smoothedAccelerationScore = 0.0
    private var smoothedRotationScore = 0.0
    private var smoothedAcceleration = MotionVector3.zero
    private var smoothedRotation = MotionVector3.zero
    private var smoothedGravity = MotionVector3.restingGravity
    private var smoothingNeedsSampleSeed = true
    private var baselineScore = 0.025
    private var startCandidateWindow: [WindowPoint] = []
    private var lastStartCandidateMotionUptime: TimeInterval?
    private var lastStartAnalysisUptime: TimeInterval?
    private var startConfirmationBeganAt: TimeInterval?
    private var pendingEstimatedStart: WindowPoint?
    private var pendingStartPeriod: TimeInterval?
    private var pendingStartSignature: PatternSignature?
    private var lastStartEvidenceUptime: TimeInterval?
    private var lastCredibleStartPatternUptime: TimeInterval?
    private var startDetectionNotBeforeUptime: TimeInterval?
    private var idleQuietBeganAt: TimeInterval?
    private var baselineObservations: [BaselineObservation] = []
    private var restObservationWindow: [WindowPoint] = []
    private var ambientPattern: PatternSignature?
    private var lastSetPattern: PatternSignature?
    private var currentSetPattern: PatternSignature?
    private var lastSetExpectedPeriod: TimeInterval?
    private var lastSetExpectedPause: TimeInterval = 0
    private var lastSetUsedPauseTolerantPattern = false
    private var motifPreRoll: [WindowPoint] = []
    private var motifSegmentPoints: [WindowPoint] = []
    private var motifLastActivityUptime: TimeInterval?
    private var completedMotifs: [MotionMotif] = []
    private var restMotifs: [MotionMotif] = []
    private var ambientMotifs: [MotionMotif] = []
    private var lastSetMotif: MotionMotif?
    private var currentSetMotif: MotionMotif?
    private var activeStartUptime: TimeInterval?
    private var observedMotionSinceActivation = false
    private var endWindow: [WindowPoint] = []
    private var endCandidateStart: WindowPoint?
    private var endLowMotionBeganAt: TimeInterval?
    private var endLowMotionAnchor: WindowPoint?
    private var endSequenceAnchor: WindowPoint?
    private var endSequenceHardDeadline: TimeInterval?
    private var endSequencePrefixExtensionUsed = false
    private var endSequencePrefixAcceptedAt: TimeInterval?
    private var endSequenceContinuationMotionStartedAt: TimeInterval?
    private var endSequenceMaximumPoseDistance = 0.0
    private var endSequenceMaximumRawScore = 0.0
    private var endSequencePendingPauseDuration: TimeInterval?
    private var endSequenceInitialPoseAngle: Double = 0
    private var endSequenceStartedIncomplete = false
    private var endSequenceFollowedSlowMotion = false
    private var endSequenceMaximumDuration: TimeInterval = 0
    private var endSequenceHasOutboundLeadIn = false
    private var verifiedContinuationGraceUntil: TimeInterval?
    private var verifiedContinuationQuietBeganAt: TimeInterval?
    private var candidateTrainingPeaks: [WindowPoint] = []
    private var activeScoreAverage = 0.0
    private var activeAccelerationShareAverage = 0.5
    private var lastTrainingLikePoint: WindowPoint?
    private var twoPointsAgo: WindowPoint?
    private var previousPoint: WindowPoint?
    private var lastPeakUptime: TimeInterval?
    private var peakIntervals: [TimeInterval] = []
    private var activeBoundaryGravity: MotionVector3?
    private var activeBoundaryAttitude: MotionQuaternion?
    private var activeExpectedPeriod: TimeInterval?
    private var activeExpectedPause: TimeInterval = 0
    private var activeUsesPauseTolerantPattern = false
    private var activeHasReliableBoundary = false
    private var activeHasSlowCadenceEvidence = false
    private var lastSemanticMotionPoint: WindowPoint?
    private var coherentSlowMotionBeganAt: TimeInterval?
    private var recentCoherentSlowMotionUptime: TimeInterval?
    private var activeMotifPreRoll: [WindowPoint] = []
    private var activeMotifSegmentPoints: [WindowPoint] = []
    private var activeMotifLastActivityUptime: TimeInterval?
    private var activeCompletedMotifs: [MotionMotif] = []
    private var activeMotifNeedsQuietBoundary = true
    private var activeMotifQuietBeganAt: TimeInterval?
    private var endCandidateProtectedUntil: TimeInterval?
    private var endCandidateInitialPoseAngle: Double = 0
    private var continuationEvidenceBeganAt: TimeInterval?
    private var pendingVerifiedPauseDuration: TimeInterval?
    private var verifiedPauseDurations: [TimeInterval] = []
    private let heartRateTrendScorer = HeartRateTrendScorer()
    private var lastConsensusVoteCount = 0
    private var lastConsensusAverageSimilarity = 0.0
    private var lastConsensusRequiredSimilarity = 0.0
    private var lastConsensusStatus = "等待重复动作"

    init(configuration: SetDetectionConfiguration = .standard) {
        self.configuration = configuration
    }

    var currentStartThreshold: Double {
        max(configuration.baseStartThreshold, baselineScore + configuration.adaptiveStartOffset)
    }

    var currentEndThreshold: Double {
        max(configuration.baseEndThreshold, baselineScore + configuration.adaptiveEndOffset)
    }

    var diagnosticSnapshot: SetDetectionDiagnosticSnapshot {
        let phaseName: String
        switch phase {
        case .idle: phaseName = "waiting"
        case .active: phaseName = "active"
        }
        let candidateDuration: TimeInterval
        if let first = startCandidateWindow.first,
           let last = startCandidateWindow.last {
            candidateDuration = max(0, last.uptime - first.uptime)
        } else {
            candidateDuration = 0
        }
        let latestUptime = endWindow.last?.uptime
            ?? window.last?.uptime
        let endCandidateDuration = endSequenceAnchor.flatMap { anchor in
            latestUptime.map { max(0, $0 - anchor.uptime) }
        } ?? 0
        let endHardDeadlineRemaining = endSequenceHardDeadline.flatMap { deadline in
            latestUptime.map { max(0, deadline - $0) }
        }
        let endProtectionRemaining = endCandidateProtectedUntil.flatMap { deadline in
            latestUptime.map { max(0, deadline - $0) }
        }
        return SetDetectionDiagnosticSnapshot(
            phase: phaseName,
            smoothedMotionScore: smoothedScore,
            baselineScore: baselineScore,
            startThreshold: currentStartThreshold,
            endThreshold: currentEndThreshold,
            periodicCandidateDuration: candidateDuration,
            completedMotifCount: completedMotifs.count,
            consensusVoteCount: lastConsensusVoteCount,
            consensusAverageSimilarity: lastConsensusAverageSimilarity,
            consensusRequiredSimilarity: lastConsensusRequiredSimilarity,
            consensusStatus: lastConsensusStatus,
            endCandidateDuration: endCandidateDuration,
            endHardDeadlineRemaining: endHardDeadlineRemaining,
            activeExpectedPause: activeExpectedPause,
            endProtectionRemaining: endProtectionRemaining
        )
    }

    func process(_ sample: MotionSample) -> SetDetectionEvent? {
        if phase == .idle,
           let startDetectionNotBeforeUptime,
           sample.uptime < startDetectionNotBeforeUptime {
            // Samples can be queued while resting and delivered after the UI
            // has entered waiting. They, and the rest-ended haptic itself,
            // must never seed a new set candidate.
            return nil
        }

        let point = makePoint(from: sample)
        appendToShortWindow(point)

        switch phase {
        case .idle:
            learnBaseline(from: smoothedScore, at: point.uptime)
            return processIdle(point)
        case .active:
            return processActive(point)
        }
    }

    func observeHeartRate(date: Date, bpm: Double) {
        heartRateTrendScorer.observe(date: date, bpm: bpm)
    }

    func observeResting(_ sample: MotionSample) {
        guard phase == .idle else { return }
        let point = makePoint(from: sample)
        appendToShortWindow(point)
        learnBaseline(from: smoothedScore, at: point.uptime)
        restObservationWindow.append(point)
        restObservationWindow.removeAll {
            point.uptime - $0.uptime > configuration.ambientObservationDuration
        }
        _ = processMotifPoint(point, observingRest: true)
        resetPeriodicStartCandidate()
    }

    func resetForNewWorkout(
        armedAtUptime: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        lastSetPattern = nil
        currentSetPattern = nil
        lastSetExpectedPeriod = nil
        lastSetExpectedPause = 0
        lastSetUsedPauseTolerantPattern = false
        lastSetMotif = nil
        currentSetMotif = nil
        ambientPattern = nil
        ambientMotifs.removeAll(keepingCapacity: true)
        restMotifs.removeAll(keepingCapacity: true)
        baselineScore = 0.025
        baselineObservations.removeAll(keepingCapacity: true)
        heartRateTrendScorer.reset()
        restObservationWindow.removeAll(keepingCapacity: true)
        resetToIdle()
        armStartDetection(at: armedAtUptime)
    }

    func beginRestObservation() {
        promoteCurrentSetPattern()
        phase = .idle
        window.removeAll(keepingCapacity: true)
        restObservationWindow.removeAll(keepingCapacity: true)
        restMotifs.removeAll(keepingCapacity: true)
        ambientMotifs.removeAll(keepingCapacity: true)
        ambientPattern = nil
        startDetectionNotBeforeUptime = nil
        resetSmoothedScoreToBaseline()
        resetStartCandidate()
        activeStartUptime = nil
        observedMotionSinceActivation = false
        resetActiveAnalysis()
        clearActiveSemanticProfile()
    }

    func armStartDetection(
        at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        contaminationGuard: TimeInterval = 0
    ) {
        phase = .idle
        ambientPattern = strongestAmbientPattern()
        ambientMotifs = restMotifs.suffix(4).map { $0 }
        startDetectionNotBeforeUptime = uptime + max(0, contaminationGuard)
        window.removeAll(keepingCapacity: true)
        resetSmoothedScoreToBaseline()
        resetStartCandidate()
        resetConsensusDiagnostics()
        idleQuietBeganAt = nil
        activeStartUptime = nil
        observedMotionSinceActivation = false
        resetActiveAnalysis()
        clearActiveSemanticProfile()
    }

    func resetToIdle() {
        promoteCurrentSetPattern()
        phase = .idle
        window.removeAll(keepingCapacity: true)
        resetSmoothedScoreToBaseline()
        resetStartCandidate()
        resetConsensusDiagnostics()
        startDetectionNotBeforeUptime = nil
        idleQuietBeganAt = nil
        activeStartUptime = nil
        observedMotionSinceActivation = false
        resetActiveAnalysis()
        clearActiveSemanticProfile()
    }

    func forceActive(
        at date: Date = Date(),
        uptime: TimeInterval = ProcessInfo.processInfo.systemUptime,
        correctedPause: TimeInterval? = nil
    ) {
        phase = .active
        window.removeAll(keepingCapacity: true)
        resetSmoothedScoreToBaseline()
        resetStartCandidate()
        startDetectionNotBeforeUptime = nil
        activeStartUptime = uptime
        observedMotionSinceActivation = false
        currentSetPattern = lastSetPattern
        currentSetMotif = lastSetMotif
        activeBoundaryGravity = lastSetMotif?.start.rawGravity
        activeBoundaryAttitude = lastSetMotif?.start.attitude
        activeExpectedPeriod = lastSetExpectedPeriod ?? lastSetPattern?.period
        activeExpectedPause = max(lastSetExpectedPause, correctedPause ?? 0)
        activeUsesPauseTolerantPattern = lastSetUsedPauseTolerantPattern
            && lastSetMotif != nil
        activeHasReliableBoundary = lastSetMotif != nil
        activeHasSlowCadenceEvidence = activeExpectedPause
                >= configuration.minimumLearnedPauseDuration
            || correctedPause != nil
        verifiedPauseDurations.removeAll(keepingCapacity: true)
        resetActiveAnalysis()
        resetActiveMotifTracking()
    }

    func prepareAfterInterruption() {
        window.removeAll(keepingCapacity: true)
        resetSmoothedScoreToBaseline()
        resetStartCandidate()
        resetActiveAnalysis()
        resetActiveMotifTracking()
    }

    private func makePoint(from sample: MotionSample) -> WindowPoint {
        let accelerationComponent = min(sample.accelerationMagnitude / configuration.accelerationScale, 2.0)
        let rotationComponent = min(sample.rotationMagnitude / configuration.rotationScale, 2.0)
        let weightedAcceleration = accelerationComponent * configuration.accelerationWeight
        let weightedRotation = rotationComponent * configuration.rotationWeight
        if smoothingNeedsSampleSeed {
            // State transitions and interruptions can happen at any wrist
            // orientation. Seed from the first real sample so convergence from
            // an invented gravity vector never looks like user movement.
            smoothedAccelerationScore = weightedAcceleration
            smoothedRotationScore = weightedRotation
            smoothedScore = weightedAcceleration + weightedRotation
            smoothedAcceleration = sample.userAcceleration
            smoothedRotation = sample.rotationRate
            smoothedGravity = sample.gravity
            smoothingNeedsSampleSeed = false
        } else {
            let smoothingAlpha = configuration.smoothingAlpha
            smoothedAccelerationScore += smoothingAlpha
                * (weightedAcceleration - smoothedAccelerationScore)
            smoothedRotationScore += smoothingAlpha
                * (weightedRotation - smoothedRotationScore)
            smoothedScore = smoothedAccelerationScore + smoothedRotationScore
            let trajectoryAlpha = configuration.trajectorySmoothingAlpha
            smoothedAcceleration = smoothedAcceleration.smoothed(
                toward: sample.userAcceleration,
                alpha: trajectoryAlpha
            )
            smoothedRotation = smoothedRotation.smoothed(
                toward: sample.rotationRate,
                alpha: trajectoryAlpha
            )
            smoothedGravity = smoothedGravity.smoothed(
                toward: sample.gravity,
                alpha: trajectoryAlpha
            )
        }
        let accelerationShare = smoothedScore > 0.000_001
            ? smoothedAccelerationScore / smoothedScore
            : activeAccelerationShareAverage
        return WindowPoint(
            date: sample.date,
            uptime: sample.uptime,
            score: smoothedScore,
            rawScore: weightedAcceleration + weightedRotation,
            accelerationShare: accelerationShare,
            acceleration: smoothedAcceleration,
            rotation: smoothedRotation,
            gravity: smoothedGravity,
            rawGravity: sample.gravity,
            attitude: sample.attitude
        )
    }

    private func appendToShortWindow(_ point: WindowPoint) {
        window.append(point)
        window.removeAll { point.uptime - $0.uptime > configuration.windowDuration }
    }

    private func processIdle(_ point: WindowPoint) -> SetDetectionEvent? {
        let threshold = currentStartThreshold
        updateAmbientReleaseState(with: point)

        if let motifDecision = processMotifPoint(point, observingRest: false) {
            let seedStart = motifDecision.estimatedStart.uptime
            let seed = completedMotifSeed(endingAt: point).filter {
                $0.uptime >= seedStart
            }
            return activateSet(
                estimatedStart: motifDecision.estimatedStart,
                pattern: nil,
                motif: motifDecision.representative,
                expectedPeriod: motifDecision.expectedPeriod,
                expectedPause: motifDecision.expectedPause,
                pauseTolerant: true,
                seed: seed
            )
        }

        if startCandidateWindow.isEmpty {
            guard point.score >= threshold else { return nil }
            startCandidateWindow = [point]
            lastStartCandidateMotionUptime = point.uptime
            return nil
        }

        startCandidateWindow.append(point)
        let motionFloor = max(currentEndThreshold * 1.12, threshold * 0.58)
        if point.score >= motionFloor {
            lastStartCandidateMotionUptime = point.uptime
        }

        let quietResetDuration = lastCredibleStartPatternUptime == nil
            ? configuration.startCandidateQuietResetDuration
            : configuration.startCandidatePatternQuietResetDuration
        if let lastStartCandidateMotionUptime,
           point.uptime - lastStartCandidateMotionUptime
            >= quietResetDuration {
            resetPeriodicStartCandidate()
            ambientPattern = nil
            return nil
        }

        trimStartCandidate(endingAt: point)
        let candidateDuration = point.uptime
            - (startCandidateWindow.first?.uptime ?? point.uptime)
        let analysisInterval = candidateDuration >= 6.0
            ? max(configuration.startAnalysisInterval, 0.24)
            : configuration.startAnalysisInterval
        if let lastStartAnalysisUptime,
           point.uptime - lastStartAnalysisUptime < analysisInterval {
            return nil
        }
        lastStartAnalysisUptime = point.uptime
        guard let initialMatch = strongestStartPattern(in: startCandidateWindow) else {
            decayPendingStartConfirmation(at: point.uptime)
            return nil
        }
        lastCredibleStartPatternUptime = point.uptime

        guard let decision = startDecision(
            initialMatch: initialMatch,
            in: startCandidateWindow,
            at: point
        ) else {
            decayPendingStartConfirmation(at: point.uptime)
            return nil
        }

        updatePendingStartConfirmation(
            with: decision.match,
            estimatedStart: decision.estimatedStart,
            at: point.uptime
        )
        guard let startConfirmationBeganAt,
              point.uptime - startConfirmationBeganAt
                >= decision.confirmationDuration,
              let estimatedStart = pendingEstimatedStart,
              let signature = pendingStartSignature else {
            return nil
        }

        let activeSeed = startCandidateWindow.filter {
            $0.uptime >= estimatedStart.uptime
        }
        return activateSet(
            estimatedStart: estimatedStart,
            pattern: signature,
            motif: nil,
            expectedPeriod: pendingStartPeriod,
            expectedPause: 0,
            pauseTolerant: false,
            seed: activeSeed
        )
    }

    private func startDecision(
        initialMatch: StartPatternMatch,
        in points: [WindowPoint],
        at point: WindowPoint
    ) -> StartDecision? {
        let initialEvidence = startConfidence(
            for: initialMatch,
            at: point.date
        )
        guard initialEvidence.ambientSimilarity
                < configuration.minimumAmbientPatternSimilarity else {
            // A pattern already present during rest (usually walking or
            // fidgeting) is not a new transition into a strength set.
            return nil
        }

        let hasFastStructure = initialMatch.cycleSimilarity
                >= configuration.minimumFastStartCycleSimilarity
            && initialMatch.meanScoreRatio
                >= configuration.minimumFastStartMeanScoreRatio
            && (
                initialMatch.reversalScore
                    >= configuration.minimumFastStartReversalScore
                || initialMatch.cycleSimilarity >= 0.82
            )
        if hasFastStructure,
           initialEvidence.confidence
            >= configuration.minimumFastStartPatternQuality {
            let hold = initialEvidence.knownSimilarity
                    >= configuration.minimumKnownPatternSimilarity
                ? configuration.knownPatternConfirmationDuration
                : configuration.fastStartConfirmationDuration
            return StartDecision(
                match: initialMatch,
                estimatedStart: initialMatch.firstCycleStart,
                confirmationDuration: hold
            )
        }

        guard let genericMatch = strongestGenericStartPattern(in: points) else {
            return nil
        }
        let genericEvidence = startConfidence(
            for: genericMatch.match,
            at: point.date
        )
        guard genericEvidence.ambientSimilarity
                < configuration.minimumAmbientPatternSimilarity,
              genericEvidence.confidence
                >= configuration.minimumStartPatternQuality else {
            return nil
        }
        let hold = genericEvidence.knownSimilarity
                >= configuration.minimumKnownPatternSimilarity
            ? configuration.knownPatternConfirmationDuration
            : configuration.startConfirmationDuration
        return StartDecision(
            match: genericMatch.match,
            estimatedStart: genericMatch.estimatedStart,
            confirmationDuration: hold
        )
    }

    private func startConfidence(
        for match: StartPatternMatch,
        at date: Date
    ) -> (
        confidence: Double,
        knownSimilarity: Double,
        ambientSimilarity: Double
    ) {
        let knownSimilarity = lastSetPattern.map {
            signatureSimilarity(match.signature, $0)
        } ?? 0
        let knownBonus = clampedProgress(
            knownSimilarity,
            from: configuration.minimumKnownPatternSimilarity,
            to: 0.90
        ) * configuration.maximumKnownPatternConfidenceBonus

        let heartRateBonus = match.quality
                >= configuration.minimumMotionQualityForHeartRateSupport
            ? heartRateTrendScorer.confidenceBonus(at: date)
            : 0

        let ambientSimilarity = similarityToArmedAmbientPattern(for: match)
        let ambientPenalty = clampedProgress(
            ambientSimilarity,
            from: configuration.ambientPatternPenaltyFloor,
            to: configuration.minimumAmbientPatternSimilarity
        ) * configuration.maximumAmbientPatternPenalty

        return (
            match.quality + knownBonus + heartRateBonus - ambientPenalty,
            knownSimilarity,
            ambientSimilarity
        )
    }

    // MARK: - Pause-tolerant motif detection

    /// Strength repetitions are not always continuous periodic waves. A slow
    /// repetition may be followed by a deliberate two-second hold, or may be
    /// split into an outbound and return movement by an isometric pause. This
    /// path compresses each actual movement into a small, speed-normalized
    /// motif, preserving it across quiet gaps without allowing unrelated
    /// handling gestures to accumulate.
    private func processMotifPoint(
        _ point: WindowPoint,
        observingRest: Bool
    ) -> MotifStartDecision? {
        motifPreRoll.append(point)
        let preRollCutoff = point.uptime - max(
            configuration.motifPreRollDuration,
            configuration.motifActivityLookbackDuration
        )
        motifPreRoll.removeAll { $0.uptime < preRollCutoff }

        let isActive = isMotifActivity(point, in: motifPreRoll)
        if motifSegmentPoints.isEmpty {
            guard isActive else { return nil }
            motifSegmentPoints = motifPreRoll
            motifLastActivityUptime = point.uptime
            return nil
        }

        if motifSegmentPoints.last?.uptime != point.uptime {
            motifSegmentPoints.append(point)
        }
        if isActive {
            motifLastActivityUptime = point.uptime
        }

        guard let segmentStart = motifSegmentPoints.first,
              let lastActivity = motifLastActivityUptime else {
            resetLiveMotifSegment()
            return nil
        }

        if point.uptime - segmentStart.uptime
            > configuration.motifMaximumDuration
                + configuration.motifQuietBoundaryDuration {
            // Continuous motion belongs to the original periodic path. Keep a
            // short pre-roll for the next separated movement, but never turn a
            // long, arbitrary handling trace into one giant motif.
            resetLiveMotifSegment()
            return nil
        }

        guard point.uptime - lastActivity
                >= configuration.motifQuietBoundaryDuration else {
            return nil
        }

        let completedPoints = motifSegmentPoints.filter {
            $0.uptime <= lastActivity + 0.000_1
        }
        resetLiveMotifSegment()
        guard let motif = makeMotionMotif(from: completedPoints) else {
            return nil
        }

        if observingRest {
            restMotifs.append(motif)
            trimMotifHistory(&restMotifs, endingAt: motif.end.uptime)
            return nil
        }

        completedMotifs.append(motif)
        trimMotifHistory(&completedMotifs, endingAt: motif.end.uptime)
        return pauseTolerantStartDecision(at: point.date)
    }

    private func isMotifActivity(
        _ point: WindowPoint,
        in preRoll: [WindowPoint]
    ) -> Bool {
        let scoreFloor = max(
            currentEndThreshold * 1.02,
            currentStartThreshold * configuration.motifActivityThresholdFraction
        )
        if point.rawScore >= scoreFloor {
            return true
        }

        let cutoff = point.uptime - configuration.motifActivityLookbackDuration
        let recent = preRoll.filter { $0.uptime >= cutoff }
        let maximumGravityChange = recent.map {
            angularDistance($0.gravity, point.gravity)
        }.max() ?? 0
        return maximumGravityChange
            >= configuration.motifGravityActivityExcursion
    }

    private func makeMotionMotif(from points: [WindowPoint]) -> MotionMotif? {
        guard let start = points.first,
              let end = points.last else {
            return nil
        }
        let duration = end.uptime - start.uptime
        guard duration >= configuration.motifMinimumDuration,
              duration <= configuration.motifMaximumDuration else {
            return nil
        }

        let peakScore = points.map(\.rawScore).max() ?? 0
        let peakScoreRatio = peakScore / max(currentStartThreshold, 0.001)
        let gravityExcursion = points.map {
            angularDistance(start.gravity, $0.gravity)
        }.max() ?? 0
        guard peakScoreRatio >= configuration.motifPeakThresholdFraction
                || gravityExcursion >= configuration.motifMinimumGravityExcursion else {
            return nil
        }

        let sampleCount = max(12, configuration.motifSampleCount)
        guard let samples = resampledMotifTrajectory(
            in: points,
            sampleCount: sampleCount
        ) else {
            return nil
        }
        let normalizedWaveform = centeredNormalizedWaveform(samples)
        guard !normalizedWaveform.isEmpty else { return nil }

        let accelerationShare = points.map(\.accelerationShare).reduce(0, +)
            / Double(points.count)
        return MotionMotif(
            start: start,
            end: end,
            duration: duration,
            points: points,
            samples: samples,
            normalizedWaveform: normalizedWaveform,
            accelerationShare: accelerationShare,
            peakScoreRatio: peakScoreRatio,
            gravityExcursion: gravityExcursion,
            integratedRotation: integratedRotation(in: points),
            rotationTravel: rotationTravel(in: points)
        )
    }

    private func resampledMotifTrajectory(
        in points: [WindowPoint],
        sampleCount: Int
    ) -> [[Double]]? {
        guard let first = points.first,
              let last = points.last,
              last.uptime > first.uptime else {
            return nil
        }
        var result: [[Double]] = []
        result.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(sampleCount - 1)
            let uptime = first.uptime + (last.uptime - first.uptime) * fraction
            guard let point = interpolatedPoint(at: uptime, in: points) else {
                return nil
            }
            result.append(motifTrajectoryChannels(for: point))
        }
        return result
    }

    private func motifTrajectoryChannels(for point: WindowPoint) -> [Double] {
        let accelerationFactor = sqrt(configuration.accelerationWeight)
            / configuration.accelerationScale
        let rotationFactor = sqrt(configuration.rotationWeight)
            / configuration.rotationScale
        return [
            point.acceleration.x * accelerationFactor,
            point.acceleration.y * accelerationFactor,
            point.acceleration.z * accelerationFactor,
            point.rotation.x * rotationFactor,
            point.rotation.y * rotationFactor,
            point.rotation.z * rotationFactor,
            point.gravity.x * 0.90,
            point.gravity.y * 0.90,
            point.gravity.z * 0.90,
            point.acceleration.magnitude / configuration.accelerationScale * 0.28,
            point.rotation.magnitude / configuration.rotationScale * 0.24
        ]
    }

    private func pauseTolerantStartDecision(
        at date: Date
    ) -> MotifStartDecision? {
        guard completedMotifs.count >= 2 else { return nil }
        let last = completedMotifs[completedMotifs.count - 1]
        let previous = completedMotifs[completedMotifs.count - 2]
        let recentGap = last.start.uptime - previous.end.uptime
        guard recentGap <= configuration.motifMaximumGapDuration else {
            return nil
        }

        let heartRateReduction = heartRateTrendScorer.confidenceBonus(at: date)
            * configuration.motifHeartRateThresholdReduction
        let knownSimilarity = lastSetMotif.map {
            motifSimilarity(last, $0)
        } ?? 0
        let knownReduction = knownSimilarity
                >= configuration.minimumKnownMotifSimilarity
            ? 0.035
            : 0
        let ambientSimilarity = ambientMotifs.map {
            motifSimilarity(last, $0)
        }.max() ?? 0
        guard ambientSimilarity < configuration.minimumAmbientMotifSimilarity else {
            return nil
        }

        let adjacentSimilarity = motifSimilarity(previous, last)
        let adjacentThreshold = configuration.minimumAdjacentMotifSimilarity
            - heartRateReduction - knownReduction
        let strongTwoThreshold = max(adjacentThreshold + 0.10, 0.77)
        let adjacentLoopQuality = min(
            motifLoopQuality(previous),
            motifLoopQuality(last)
        )
        let adjacentHasKinematicPeaks = previous.peakScoreRatio
                >= configuration.motifPeakThresholdFraction
            && last.peakScoreRatio
                >= configuration.motifPeakThresholdFraction
        if adjacentHasKinematicPeaks,
           adjacentLoopQuality >= 0.58,
           adjacentSimilarity >= strongTwoThreshold {
            return MotifStartDecision(
                estimatedStart: previous.start,
                representative: last,
                expectedPeriod: last.start.uptime - previous.start.uptime,
                expectedPause: max(0, recentGap)
            )
        }

        guard completedMotifs.count >= 3 else { return nil }
        let first = completedMotifs[completedMotifs.count - 3]
        let firstGap = previous.start.uptime - first.end.uptime
        guard firstGap <= configuration.motifMaximumGapDuration else {
            return nil
        }

        let firstAdjacentSimilarity = motifSimilarity(first, previous)
        let threeHaveKinematicPeaks = [first, previous, last].allSatisfy {
            $0.peakScoreRatio >= configuration.motifPeakThresholdFraction
        }
        if threeHaveKinematicPeaks,
           motifLoopQuality(first) >= 0.56,
           adjacentLoopQuality >= 0.56,
           firstAdjacentSimilarity >= adjacentThreshold,
           adjacentSimilarity >= adjacentThreshold {
            return MotifStartDecision(
                estimatedStart: first.start,
                representative: last,
                expectedPeriod: median([
                    previous.start.uptime - first.start.uptime,
                    last.start.uptime - previous.start.uptime
                ]),
                expectedPause: median([max(0, firstGap), max(0, recentGap)])
            )
        }

        // A long hold at the top splits one repetition into A (outbound) and B
        // (return). A-B-A is sufficient repeated structure when B brings the
        // wrist back along the same posture/rotation path.
        let alternatingSimilarity = motifSimilarity(first, last)
        let alternatingThreshold = configuration.minimumAlternatingMotifSimilarity
            - heartRateReduction - knownReduction
        let returnScore = motifReturnScore(outbound: first, returning: previous)
        if alternatingSimilarity >= alternatingThreshold,
           returnScore >= configuration.minimumMotifReturnScore {
            return MotifStartDecision(
                estimatedStart: first.start,
                representative: last,
                expectedPeriod: last.start.uptime - first.start.uptime,
                // A-B-A represents an outbound/return split by a top hold. Its
                // mixed gaps are not the pause expected at the completed-rep
                // boundary; incomplete-pose protection handles the top instead.
                expectedPause: 0
            )
        }

        return repetitionConsensusStartDecision(
            heartRateReduction: heartRateReduction
        )
    }

    private func motifSimilarity(_ lhs: MotionMotif, _ rhs: MotionMotif) -> Double {
        var bestWaveformSimilarity = -1.0
        for warp in [-0.16, -0.08, 0.0, 0.08, 0.16] {
            let warped = phaseWarpedSamples(rhs.samples, amount: warp)
            let normalized = centeredNormalizedWaveform(warped)
            guard normalized.count == lhs.normalizedWaveform.count else {
                continue
            }
            let similarity = zip(lhs.normalizedWaveform, normalized)
                .reduce(0) { $0 + $1.0 * $1.1 }
            bestWaveformSimilarity = max(bestWaveformSimilarity, similarity)
        }

        let durationRatio = min(lhs.duration, rhs.duration)
            / max(lhs.duration, rhs.duration)
        let shareScore = max(
            0,
            1 - abs(lhs.accelerationShare - rhs.accelerationShare) / 0.42
        )
        let gravityRatio: Double
        if max(lhs.gravityExcursion, rhs.gravityExcursion) < 0.015 {
            gravityRatio = 1
        } else {
            gravityRatio = min(lhs.gravityExcursion, rhs.gravityExcursion)
                / max(lhs.gravityExcursion, rhs.gravityExcursion)
        }
        let rotationDirection = vectorDirectionSimilarity(
            lhs.integratedRotation,
            rhs.integratedRotation
        )
        return max(0, bestWaveformSimilarity) * 0.76
            + durationRatio * 0.07
            + shareScore * 0.07
            + gravityRatio * 0.05
            + rotationDirection * 0.05
    }

    private func repetitionConsensusStartDecision(
        heartRateReduction: Double
    ) -> MotifStartDecision? {
        lastConsensusVoteCount = 0
        lastConsensusAverageSimilarity = 0
        lastConsensusRequiredSimilarity = 0
        lastConsensusStatus = "正在收集完整重复"

        let cappedRecent = Array(completedMotifs.suffix(
            configuration.repetitionConsensusMaximumCount
        ))
        guard let newestMotif = cappedRecent.last else { return nil }
        var episodeReversed = [newestMotif]
        var following = newestMotif
        for candidate in cappedRecent.dropLast().reversed() {
            let gap = following.start.uptime - candidate.end.uptime
            guard gap <= configuration.motifMaximumGapDuration else { break }
            episodeReversed.append(candidate)
            following = candidate
        }
        let recent = Array(episodeReversed.reversed())
        guard recent.count >= configuration.repetitionConsensusMinimumVotes,
              let newest = recent.last else {
            lastConsensusStatus = "完整重复数量不足"
            return nil
        }

        let eligible = recent.filter {
            $0.duration >= configuration.repetitionConsensusMinimumDuration
                && $0.peakScoreRatio
                    >= configuration.repetitionConsensusMinimumPeakRatio
                && motifLoopQuality($0)
                    >= configuration.repetitionConsensusMinimumLoopQuality
        }
        lastConsensusVoteCount = eligible.count
        guard eligible.count >= configuration.repetitionConsensusMinimumVotes,
              eligible.last?.end.uptime == newest.end.uptime else {
            lastConsensusStatus = eligible.last?.end.uptime == newest.end.uptime
                ? "有效重复数量不足"
                : "最新动作还不是完整往返"
            return nil
        }

        var bestMembers: [MotionMotif] = []
        var bestSimilarity = 0.0
        for anchor in eligible {
            var members: [MotionMotif] = []
            var similarities: [Double] = []
            for candidate in eligible {
                if candidate.end.uptime == anchor.end.uptime {
                    members.append(candidate)
                    continue
                }
                let axisSimilarity = motifAxisEnergySimilarity(anchor, candidate)
                let signedSimilarity = motifSimilarity(anchor, candidate)
                let similarity = broadRepetitionSimilarity(anchor, candidate)
                guard axisSimilarity
                        >= configuration.repetitionConsensusMinimumAxisSimilarity,
                      signedSimilarity
                        >= configuration.repetitionConsensusMinimumSignedSimilarity,
                      similarity
                        >= configuration.repetitionConsensusMembershipSimilarity else {
                    continue
                }
                members.append(candidate)
                similarities.append(similarity)
            }
            guard members.contains(where: {
                $0.end.uptime == newest.end.uptime
            }) else {
                continue
            }
            let averageSimilarity = similarities.isEmpty
                ? 0
                : similarities.reduce(0, +) / Double(similarities.count)
            if members.count > bestMembers.count
                || (members.count == bestMembers.count
                    && averageSimilarity > bestSimilarity) {
                bestMembers = members
                bestSimilarity = averageSimilarity
            }
        }

        lastConsensusVoteCount = bestMembers.count
        lastConsensusAverageSimilarity = bestSimilarity
        // The rescue route tolerates at most two genuinely bad repetitions.
        // It must not cherry-pick four coincidentally similar gestures out of a
        // long sequence of otherwise unrelated handling movements.
        let requiredVoteCount = max(
            configuration.repetitionConsensusMinimumVotes,
            recent.count - 2
        )
        guard bestMembers.count >= requiredVoteCount else {
            lastConsensusStatus = "重复动作的共同特征不足"
            return nil
        }
        let requiredSimilarity: Double
        switch bestMembers.count {
        case 6...:
            requiredSimilarity = configuration.repetitionConsensusSixVoteSimilarity
        case 5:
            requiredSimilarity = configuration.repetitionConsensusFiveVoteSimilarity
        default:
            requiredSimilarity = configuration.repetitionConsensusFourVoteSimilarity
        }
        lastConsensusRequiredSimilarity = requiredSimilarity
        let heartRateSupport = min(0.025, max(0, heartRateReduction * 0.45))
        guard bestSimilarity >= requiredSimilarity - heartRateSupport else {
            lastConsensusStatus = "重复相似度仍不足"
            return nil
        }

        let sortedMembers = bestMembers.sorted { $0.start.uptime < $1.start.uptime }
        let periods = zip(sortedMembers, sortedMembers.dropFirst()).map {
            $1.start.uptime - $0.start.uptime
        }
        guard !periods.isEmpty,
              median(periods) >= configuration.repetitionConsensusMinimumPeriod else {
            lastConsensusStatus = "节奏不属于慢速共识路径"
            return nil
        }

        let representative = sortedMembers.last ?? newest
        let ambientSimilarity = ambientMotifs.map {
            broadRepetitionSimilarity(representative, $0)
        }.max() ?? 0
        guard ambientSimilarity
                < configuration.repetitionConsensusAmbientSimilarity else {
            lastConsensusStatus = "动作与休息阶段模式过于相似"
            return nil
        }

        lastConsensusStatus = "多次重复共识已通过"
        let pauses = zip(sortedMembers, sortedMembers.dropFirst()).map {
            max(0, $1.start.uptime - $0.end.uptime)
        }
        return MotifStartDecision(
            estimatedStart: sortedMembers[0].start,
            representative: representative,
            expectedPeriod: median(periods),
            expectedPause: median(pauses)
        )
    }

    private func broadRepetitionSimilarity(
        _ lhs: MotionMotif,
        _ rhs: MotionMotif
    ) -> Double {
        let signedSimilarity = motifSimilarity(lhs, rhs)
        let invariantSimilarity = motifInvariantWaveformSimilarity(lhs, rhs)
        let axisSimilarity = motifAxisEnergySimilarity(lhs, rhs)
        let durationRatio = min(lhs.duration, rhs.duration)
            / max(lhs.duration, rhs.duration)
        let loopSimilarity = min(
            motifLoopQuality(lhs),
            motifLoopQuality(rhs)
        )
        return signedSimilarity * 0.36
            + invariantSimilarity * 0.32
            + axisSimilarity * 0.17
            + durationRatio * 0.07
            + loopSimilarity * 0.08
    }

    private func motifInvariantWaveformSimilarity(
        _ lhs: MotionMotif,
        _ rhs: MotionMotif
    ) -> Double {
        let lhsSamples = invariantMotifSamples(lhs.samples)
        let lhsWaveform = centeredNormalizedWaveform(lhsSamples)
        guard !lhsWaveform.isEmpty else { return 0 }

        var best = 0.0
        for warp in [-0.20, -0.10, 0.0, 0.10, 0.20] {
            let warped = phaseWarpedSamples(rhs.samples, amount: warp)
            let rhsWaveform = centeredNormalizedWaveform(
                invariantMotifSamples(warped)
            )
            guard rhsWaveform.count == lhsWaveform.count else { continue }
            best = max(
                best,
                zip(lhsWaveform, rhsWaveform)
                    .reduce(0) { $0 + $1.0 * $1.1 }
            )
        }
        return max(0, min(1, best))
    }

    private func invariantMotifSamples(_ samples: [[Double]]) -> [[Double]] {
        guard let first = samples.first, first.count >= 11 else { return [] }
        return samples.map { sample in
            guard sample.count >= 11 else { return [0, 0, 0] }
            let gravityDelta = sqrt(
                pow(sample[6] - first[6], 2)
                    + pow(sample[7] - first[7], 2)
                    + pow(sample[8] - first[8], 2)
            )
            return [sample[9], sample[10], gravityDelta]
        }
    }

    private func motifAxisEnergySimilarity(
        _ lhs: MotionMotif,
        _ rhs: MotionMotif
    ) -> Double {
        func normalizedAxisEnergy(_ samples: [[Double]]) -> [Double] {
            var energies = Array(repeating: 0.0, count: 6)
            for sample in samples where sample.count >= 6 {
                for index in 0..<6 {
                    energies[index] += sample[index] * sample[index]
                }
            }
            let norm = sqrt(energies.reduce(0) { $0 + $1 * $1 })
            guard norm > 0.000_001 else { return energies }
            return energies.map { $0 / norm }
        }
        let lhsEnergy = normalizedAxisEnergy(lhs.samples)
        let rhsEnergy = normalizedAxisEnergy(rhs.samples)
        guard lhsEnergy.count == rhsEnergy.count else { return 0 }
        return max(
            0,
            min(1, zip(lhsEnergy, rhsEnergy).reduce(0) { $0 + $1.0 * $1.1 })
        )
    }

    private func motifLoopQuality(_ motif: MotionMotif) -> Double {
        let returnAngle = angularDistance(motif.start.gravity, motif.end.gravity)
        let gravityReturn = motif.gravityExcursion
                >= configuration.motifMinimumGravityExcursion
            ? max(0, 1 - returnAngle / 0.16)
            : 0
        guard let channelCount = motif.samples.first?.count,
              channelCount >= 6 else {
            return gravityReturn
        }
        var energies = Array(repeating: 0.0, count: 6)
        for sample in motif.samples {
            for channel in 0..<6 {
                energies[channel] += sample[channel] * sample[channel]
            }
        }
        let dominant = energies.indices.max(by: { energies[$0] < energies[$1] }) ?? 0
        let reversal = reversalScore(in: motif.samples.map { $0[dominant] })
        let rotationClosure = motif.rotationTravel > 0.000_1
            ? max(
                0,
                1 - motif.integratedRotation.magnitude / motif.rotationTravel
            )
            : 0
        let kinematicLoop = reversal * 0.56 + rotationClosure * 0.44
        return max(gravityReturn, kinematicLoop)
    }

    private func motifReturnScore(
        outbound: MotionMotif,
        returning: MotionMotif
    ) -> Double {
        // A-B-A handling gestures can accidentally alternate signed axes while
        // the wrist pose never travels anywhere. The split-repetition path is
        // therefore reserved for a real posture excursion; fixed-pose exercises
        // remain covered by complete repeated motifs and the periodic matcher.
        guard max(outbound.gravityExcursion, returning.gravityExcursion)
                >= configuration.motifMinimumGravityExcursion else {
            return 0
        }
        let outboundDisplacement = angularDistance(
            outbound.start.gravity,
            outbound.end.gravity
        )
        let returnDisplacement = angularDistance(
            returning.start.gravity,
            returning.end.gravity
        )
        guard outboundDisplacement
                >= configuration.minimumIncompleteGravityAngle * 0.75,
              returnDisplacement
                >= configuration.minimumIncompleteGravityAngle * 0.75 else {
            return 0
        }
        let startReturn = max(
            0,
            1 - angularDistance(outbound.start.gravity, returning.end.gravity) / 0.18
        )
        let turnAlignment = max(
            0,
            1 - angularDistance(outbound.end.gravity, returning.start.gravity) / 0.18
        )
        let gravityReturn = (startReturn + turnAlignment) / 2

        let rotationOpposition = vectorOppositionSimilarity(
            outbound.integratedRotation,
            returning.integratedRotation
        )
        let reversedSamples = returning.samples.reversed().map { sample -> [Double] in
            var transformed = sample
            if transformed.count >= 6 {
                transformed[3] *= -1
                transformed[4] *= -1
                transformed[5] *= -1
            }
            return transformed
        }
        let reversedWaveform = centeredNormalizedWaveform(reversedSamples)
        let waveformReturn: Double
        if reversedWaveform.count == outbound.normalizedWaveform.count {
            waveformReturn = max(
                0,
                zip(outbound.normalizedWaveform, reversedWaveform)
                    .reduce(0) { $0 + $1.0 * $1.1 }
            )
        } else {
            waveformReturn = 0
        }
        return gravityReturn * 0.50
            + rotationOpposition * 0.25
            + waveformReturn * 0.25
    }

    private func phaseWarpedSamples(
        _ samples: [[Double]],
        amount: Double
    ) -> [[Double]] {
        guard samples.count >= 2 else { return samples }
        return samples.indices.map { index in
            let fraction = Double(index) / Double(samples.count - 1)
            let warpedFraction = min(
                1,
                max(0, fraction + amount * sin(.pi * fraction))
            )
            let position = warpedFraction * Double(samples.count - 1)
            let lower = Int(floor(position))
            let upper = min(samples.count - 1, lower + 1)
            let blend = position - Double(lower)
            guard samples[lower].count == samples[upper].count else {
                return samples[lower]
            }
            return zip(samples[lower], samples[upper]).map {
                $0 + ($1 - $0) * blend
            }
        }
    }

    private func integratedRotation(in points: [WindowPoint]) -> MotionVector3 {
        guard points.count >= 2 else { return .zero }
        var x = 0.0
        var y = 0.0
        var z = 0.0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let dt = max(0, current.uptime - previous.uptime)
            x += (previous.rotation.x + current.rotation.x) * 0.5 * dt
            y += (previous.rotation.y + current.rotation.y) * 0.5 * dt
            z += (previous.rotation.z + current.rotation.z) * 0.5 * dt
        }
        return MotionVector3(x: x, y: y, z: z)
    }

    private func rotationTravel(in points: [WindowPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var travel = 0.0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let dt = max(0, current.uptime - previous.uptime)
            travel += (previous.rotation.magnitude + current.rotation.magnitude)
                * 0.5 * dt
        }
        return travel
    }

    private func vectorDirectionSimilarity(
        _ lhs: MotionVector3,
        _ rhs: MotionVector3
    ) -> Double {
        let denominator = lhs.magnitude * rhs.magnitude
        guard denominator > 0.000_1 else { return 0.5 }
        return min(1, max(0, (lhs.dot(rhs) / denominator + 1) / 2))
    }

    private func vectorOppositionSimilarity(
        _ lhs: MotionVector3,
        _ rhs: MotionVector3
    ) -> Double {
        let denominator = lhs.magnitude * rhs.magnitude
        guard denominator > 0.000_1 else { return 0 }
        return min(1, max(0, -lhs.dot(rhs) / denominator))
    }

    private func angularDistance(
        _ lhs: MotionVector3,
        _ rhs: MotionVector3
    ) -> Double {
        let denominator = lhs.magnitude * rhs.magnitude
        guard denominator > 0.000_001 else { return .pi }
        let cosine = min(1, max(-1, lhs.dot(rhs) / denominator))
        return acos(cosine)
    }

    private func trimMotifHistory(
        _ motifs: inout [MotionMotif],
        endingAt uptime: TimeInterval
    ) {
        let cutoff = uptime - configuration.motifMaximumHistoryDuration
        motifs.removeAll { $0.end.uptime < cutoff }
        let maximumCount = max(
            10,
            configuration.repetitionConsensusMaximumCount + 2
        )
        if motifs.count > maximumCount {
            motifs.removeFirst(motifs.count - maximumCount)
        }
    }

    private func resetLiveMotifSegment() {
        motifSegmentPoints.removeAll(keepingCapacity: true)
        motifLastActivityUptime = nil
    }

    private func completedMotifSeed(endingAt point: WindowPoint) -> [WindowPoint] {
        let cutoff = point.uptime - configuration.motifMaximumHistoryDuration
        return completedMotifs
            .flatMap(\.points)
            .filter { $0.uptime >= cutoff }
    }

    private func activeMotifTemplate(
        from seed: [WindowPoint],
        expectedPeriod: TimeInterval?
    ) -> MotionMotif? {
        guard let expectedPeriod,
              expectedPeriod >= configuration.motifMinimumDuration,
              expectedPeriod <= configuration.motifMaximumDuration,
              let last = seed.last else {
            return nil
        }
        let cycleStart = last.uptime - expectedPeriod
        let points = seed.filter { $0.uptime >= cycleStart - 0.02 }
        return makeMotionMotif(from: points)
    }

    private func processActiveMotifPoint(_ point: WindowPoint) {
        activeMotifPreRoll.append(point)
        let preRollCutoff = point.uptime - max(
            configuration.motifPreRollDuration,
            configuration.motifActivityLookbackDuration
        )
        activeMotifPreRoll.removeAll { $0.uptime < preRollCutoff }

        let isActive = isMotifActivity(point, in: activeMotifPreRoll)
        if activeMotifNeedsQuietBoundary {
            if isActive {
                activeMotifQuietBeganAt = nil
            } else {
                activeMotifQuietBeganAt = activeMotifQuietBeganAt
                    ?? point.uptime
                if let activeMotifQuietBeganAt,
                   point.uptime - activeMotifQuietBeganAt
                    >= configuration.motifQuietBoundaryDuration {
                    activeMotifNeedsQuietBoundary = false
                    self.activeMotifQuietBeganAt = nil
                }
            }
            return
        }
        if activeMotifSegmentPoints.isEmpty {
            guard isActive else { return }
            activeMotifSegmentPoints = activeMotifPreRoll
            activeMotifLastActivityUptime = point.uptime
            return
        }

        if activeMotifSegmentPoints.last?.uptime != point.uptime {
            activeMotifSegmentPoints.append(point)
        }
        if isActive {
            activeMotifLastActivityUptime = point.uptime
        }

        guard let segmentStart = activeMotifSegmentPoints.first,
              let lastActivity = activeMotifLastActivityUptime else {
            resetActiveLiveMotifSegment()
            return
        }
        if point.uptime - segmentStart.uptime
            > configuration.motifMaximumDuration
                + configuration.motifQuietBoundaryDuration {
            resetActiveLiveMotifSegment()
            activeMotifNeedsQuietBoundary = true
            activeMotifQuietBeganAt = nil
            return
        }
        guard point.uptime - lastActivity
                >= configuration.motifQuietBoundaryDuration else {
            return
        }

        let completedPoints = activeMotifSegmentPoints.filter {
            $0.uptime <= lastActivity + 0.000_1
        }
        resetActiveLiveMotifSegment()
        guard let motif = makeMotionMotif(from: completedPoints) else {
            return
        }
        let completesVerifiedContinuation = isTrustedCompletedContinuation(
            motif
        )
        if endCandidateStart == nil
            || completesVerifiedContinuation {
            learnFromActiveMotif(motif)
        }
        if completesVerifiedContinuation {
            if endCandidateStart != nil {
                cancelEndCandidateForContinuation(at: motif.end)
            }
            clearEndSequenceForVerifiedContinuation()
        }
    }

    private func isTrustedCompletedContinuation(_ motif: MotionMotif) -> Bool {
        guard let anchor = endSequenceAnchor,
              motif.start.uptime >= anchor.uptime + 0.10 else {
            return false
        }

        if let currentSetMotif {
            let hasKinematicPeak = motif.peakScoreRatio >= max(
                configuration.repetitionConsensusMinimumPeakRatio,
                configuration.motifPeakThresholdFraction - 0.12
            )
            let hasCompleteLoop = motifLoopQuality(motif)
                >= configuration.repetitionConsensusMinimumLoopQuality
            let signedSimilarity = motifSimilarity(currentSetMotif, motif)
            let axisSimilarity = motifAxisEnergySimilarity(
                currentSetMotif,
                motif
            )
            let broadSimilarity = broadRepetitionSimilarity(
                currentSetMotif,
                motif
            )
            if hasKinematicPeak,
               hasCompleteLoop,
               signedSimilarity
                    >= configuration.repetitionConsensusMinimumSignedSimilarity,
               axisSimilarity
                    >= configuration.repetitionConsensusMinimumAxisSimilarity - 0.08,
               broadSimilarity
                    >= configuration.repetitionConsensusMembershipSimilarity + 0.06 {
                return true
            }
        }

        guard let outbound = activeCompletedMotifs.last(where: {
            $0.start.uptime <= anchor.uptime + 0.12
                && $0.end.uptime <= motif.start.uptime + 0.02
        }) else {
            return false
        }
        return motifReturnScore(outbound: outbound, returning: motif)
            >= configuration.minimumMotifReturnScore - 0.06
    }

    private func learnFromActiveMotif(_ motif: MotionMotif) {
        activeCompletedMotifs.append(motif)
        trimMotifHistory(&activeCompletedMotifs, endingAt: motif.end.uptime)

        guard activeCompletedMotifs.count >= 2 else { return }
        let last = activeCompletedMotifs[activeCompletedMotifs.count - 1]
        let previous = activeCompletedMotifs[activeCompletedMotifs.count - 2]
        let recentGap = max(0, last.start.uptime - previous.end.uptime)
        if activeCompletedMotifs.count >= 3 {
            let first = activeCompletedMotifs[activeCompletedMotifs.count - 3]
            let alternatingSimilarity = motifSimilarity(first, last)
            let splitReturn = motifReturnScore(
                outbound: first,
                returning: previous
            )
            if alternatingSimilarity
                    >= configuration.minimumAlternatingMotifSimilarity - 0.04,
               splitReturn >= configuration.minimumMotifReturnScore - 0.06 {
                currentSetMotif = last
                activeUsesPauseTolerantPattern = true
                activeHasReliableBoundary = true
                activeExpectedPeriod = max(
                    activeExpectedPeriod ?? 0,
                    last.start.uptime - first.start.uptime
                )
                updateActiveBoundary(from: first.start)
                return
            }
        }

        let adjacentSimilarity = motifSimilarity(previous, last)
        let hasKinematicPeaks = previous.peakScoreRatio
                >= configuration.motifPeakThresholdFraction
            && last.peakScoreRatio
                >= configuration.motifPeakThresholdFraction
        let hasClosedRepetitionPoses = poseDistance(
            from: previous.start,
            to: previous.end
        ) <= configuration.minimumIncompleteGravityAngle * 0.78
            && poseDistance(
                from: last.start,
                to: last.end
            ) <= configuration.minimumIncompleteGravityAngle * 0.78
        if hasKinematicPeaks,
           hasClosedRepetitionPoses,
           motifLoopQuality(previous) >= 0.56,
           motifLoopQuality(last) >= 0.56,
           adjacentSimilarity
                >= configuration.minimumAdjacentMotifSimilarity - 0.06 {
            currentSetMotif = last
            activeUsesPauseTolerantPattern = true
            activeHasReliableBoundary = true
            activeExpectedPeriod = last.start.uptime - previous.start.uptime
            if recentGap >= configuration.minimumLearnedPauseDuration {
                activeHasSlowCadenceEvidence = true
                verifiedPauseDurations.append(recentGap)
                if verifiedPauseDurations.count > 5 {
                    verifiedPauseDurations.removeFirst(
                        verifiedPauseDurations.count - 5
                    )
                }
                activeExpectedPause = max(
                    activeExpectedPause,
                    median(verifiedPauseDurations)
                )
            }
            updateActiveBoundary(from: last.start)
            return
        }

        let splitReturn = motifReturnScore(
            outbound: previous,
            returning: last
        )
        if splitReturn >= configuration.minimumMotifReturnScore - 0.06 {
            currentSetMotif = previous
            activeUsesPauseTolerantPattern = true
            activeHasReliableBoundary = true
            updateActiveBoundary(from: previous.start)
        }
    }

    private func updateActiveBoundary(from point: WindowPoint) {
        if let activeBoundaryGravity {
            let candidateDistance = angularDistance(
                activeBoundaryGravity,
                point.rawGravity
            )
            if candidateDistance
                <= configuration.minimumIncompleteGravityAngle * 1.8 {
                self.activeBoundaryGravity = activeBoundaryGravity.smoothed(
                    toward: point.rawGravity,
                    alpha: 0.18
                )
            }
        } else {
            activeBoundaryGravity = point.rawGravity
        }
        if let activeBoundaryAttitude,
           let attitude = point.attitude {
            if activeBoundaryAttitude.angularDistance(to: attitude)
                <= configuration.minimumIncompleteGravityAngle * 1.8 {
                self.activeBoundaryAttitude = activeBoundaryAttitude.interpolated(
                    to: attitude,
                    fraction: 0.18
                )
            }
        } else if let attitude = point.attitude {
            activeBoundaryAttitude = attitude
        }
    }

    private func resetActiveMotifTracking(seed: [WindowPoint] = []) {
        if let last = seed.last {
            let cutoff = last.uptime - max(
                configuration.motifPreRollDuration,
                configuration.motifActivityLookbackDuration
            )
            activeMotifPreRoll = seed.filter { $0.uptime >= cutoff }
        } else {
            activeMotifPreRoll.removeAll(keepingCapacity: true)
        }
        activeMotifSegmentPoints.removeAll(keepingCapacity: true)
        activeMotifLastActivityUptime = nil
        activeCompletedMotifs.removeAll(keepingCapacity: true)
        activeMotifNeedsQuietBoundary = true
        activeMotifQuietBeganAt = nil
    }

    private func resetActiveLiveMotifSegment() {
        activeMotifSegmentPoints.removeAll(keepingCapacity: true)
        activeMotifLastActivityUptime = nil
    }

    private func activateSet(
        estimatedStart: WindowPoint,
        pattern: PatternSignature?,
        motif: MotionMotif?,
        expectedPeriod: TimeInterval?,
        expectedPause: TimeInterval,
        pauseTolerant: Bool,
        seed: [WindowPoint]
    ) -> SetDetectionEvent {
        let inferredMotif = motif ?? activeMotifTemplate(
            from: seed,
            expectedPeriod: expectedPeriod
        )
        var resolvedExpectedPause = max(0, expectedPause)
        if let pattern,
           let lastSetPattern,
           signatureSimilarity(pattern, lastSetPattern)
                >= configuration.minimumKnownPatternSimilarity {
            resolvedExpectedPause = max(resolvedExpectedPause, lastSetExpectedPause)
        }
        if let inferredMotif,
           let lastSetMotif,
           motifSimilarity(inferredMotif, lastSetMotif)
                >= configuration.minimumKnownMotifSimilarity {
            resolvedExpectedPause = max(resolvedExpectedPause, lastSetExpectedPause)
        }
        let boundaryPoint = inferredMotif?.start ?? estimatedStart

        phase = .active
        activeStartUptime = estimatedStart.uptime
        observedMotionSinceActivation = true
        currentSetPattern = pattern
        currentSetMotif = inferredMotif
        activeBoundaryGravity = boundaryPoint.rawGravity
        activeBoundaryAttitude = boundaryPoint.attitude
        activeExpectedPeriod = expectedPeriod
        activeExpectedPause = resolvedExpectedPause
        activeUsesPauseTolerantPattern = pauseTolerant
            || resolvedExpectedPause >= configuration.minimumLearnedPauseDuration
        activeHasReliableBoundary = pattern != nil || inferredMotif != nil
        activeHasSlowCadenceEvidence = resolvedExpectedPause
            >= configuration.minimumLearnedPauseDuration
        verifiedPauseDurations.removeAll(keepingCapacity: true)
        startDetectionNotBeforeUptime = nil
        if motif == nil {
            lastConsensusStatus = "连续周期路径已通过"
        } else if lastConsensusStatus != "多次重复共识已通过" {
            lastConsensusStatus = "短窗重复路径已通过"
        }
        resetStartCandidate()
        resetActiveAnalysis(seed: seed)
        resetActiveMotifTracking(seed: seed)
        return .setStarted(estimatedStart: estimatedStart.date)
    }

    private func processActive(_ point: WindowPoint) -> SetDetectionEvent? {
        if point.score >= currentStartThreshold {
            observedMotionSinceActivation = true
        }

        endWindow.append(point)
        let retainedDuration = max(
            configuration.maximumProtectedEndDuration,
            configuration.maximumResumptionGraceDuration
        )
            + configuration.resumptionWindowDuration
        endWindow.removeAll { point.uptime - $0.uptime > retainedDuration }
        processActiveMotifPoint(point)
        if endSequencePrefixAcceptedAt != nil,
           let anchor = endSequenceAnchor {
            endSequenceMaximumPoseDistance = max(
                endSequenceMaximumPoseDistance,
                poseDistance(from: anchor, to: point)
            )
            endSequenceMaximumRawScore = max(
                endSequenceMaximumRawScore,
                point.rawScore
            )
        }

        let detectedPeak = updatePeakIntervals(
            with: point,
            recordInterval: endCandidateStart == nil
        )
        if endCandidateStart != nil,
           let detectedPeak,
           isTrainingLike(detectedPeak),
           candidateTrainingPeaks.last.map({
               detectedPeak.uptime - $0.uptime >= configuration.minimumPeakInterval
           }) ?? true {
            candidateTrainingPeaks.append(detectedPeak)
        }

        if endCandidateStart == nil {
            let trainingLike = isTrainingLike(point)
            let semanticTrainingLike = trainingLike
                && point.rawScore >= currentEndThreshold * 0.28
            let coherentSlowMotion = !semanticTrainingLike
                && isCoherentSlowTrainingMotion(endingAt: point)
            var withinVerifiedContinuationGrace = verifiedContinuationGraceUntil.map {
                point.uptime < $0
            } ?? false
            let hasContinuationMotion = semanticTrainingLike
                || coherentSlowMotion
                || point.rawScore >= currentEndThreshold * 0.18
            if withinVerifiedContinuationGrace && !hasContinuationMotion {
                verifiedContinuationQuietBeganAt = verifiedContinuationQuietBeganAt
                    ?? point.uptime
                if let quietBeganAt = verifiedContinuationQuietBeganAt,
                   point.uptime - quietBeganAt >= 0.12 {
                    verifiedContinuationGraceUntil = nil
                    verifiedContinuationQuietBeganAt = nil
                    withinVerifiedContinuationGrace = false
                    // The quiet interval began while the bounded continuation
                    // grace was active. Preserve its real start so a wrist
                    // raise immediately afterward cannot erase genuine stop
                    // evidence and restart the whole end clock.
                    endLowMotionBeganAt = quietBeganAt
                    endLowMotionAnchor = lastSemanticMotionPoint ?? point
                }
            } else if hasContinuationMotion {
                verifiedContinuationQuietBeganAt = nil
            }
            if !withinVerifiedContinuationGrace {
                verifiedContinuationGraceUntil = nil
            } else {
                endLowMotionBeganAt = nil
                endLowMotionAnchor = nil
                if hasContinuationMotion {
                    lastSemanticMotionPoint = point
                }
            }
            if trainingLike {
                lastTrainingLikePoint = point
                updateActiveProfile(with: point)
            }
            let pendingBoundaryDuration = endLowMotionBeganAt.map {
                point.uptime - $0
            } ?? 0
            let continuesBeforeBoundary = semanticTrainingLike
                && endLowMotionBeganAt != nil
                && pendingBoundaryDuration
                    < configuration.endCandidateActivationDelay
            if continuesBeforeBoundary {
                endLowMotionBeganAt = nil
                endLowMotionAnchor = nil
            }
            let mayExtendSemanticMotion = endLowMotionBeganAt == nil
            if semanticTrainingLike && mayExtendSemanticMotion {
                lastSemanticMotionPoint = point
            } else if coherentSlowMotion && mayExtendSemanticMotion {
                lastSemanticMotionPoint = point
            }
            if coherentSlowMotion && mayExtendSemanticMotion {
                coherentSlowMotionBeganAt = coherentSlowMotionBeganAt
                    ?? point.uptime
                if let coherentSlowMotionBeganAt,
                   point.uptime - coherentSlowMotionBeganAt
                    >= configuration.minimumSlowMotionEvidenceDuration {
                    recentCoherentSlowMotionUptime = point.uptime
                }
            } else {
                coherentSlowMotionBeganAt = nil
            }

            let needsBoundaryCandidate = !withinVerifiedContinuationGrace
                && !semanticTrainingLike
                && (!coherentSlowMotion || endLowMotionBeganAt != nil)
            if needsBoundaryCandidate {
                endLowMotionBeganAt = endLowMotionBeganAt ?? point.uptime
                endLowMotionAnchor = endLowMotionAnchor
                    ?? lastSemanticMotionPoint
                    ?? point
                if let endLowMotionBeganAt,
                   point.uptime - endLowMotionBeganAt
                    >= configuration.endCandidateActivationDelay {
                    beginEndCandidate(at: endLowMotionAnchor ?? point)
                }
            } else if !withinVerifiedContinuationGrace,
                      semanticTrainingLike,
                      let endLowMotionBeganAt,
                      point.uptime - endLowMotionBeganAt
                        >= configuration.endCandidateActivationDelay {
                // Motion after a real quiet boundary must prove that it is the
                // same repetition; don't silently merge a wrist raise or grab.
                beginEndCandidate(at: endLowMotionAnchor ?? point)
            }
        }
        if endCandidateStart != nil {
            let hasPausePrefix = hasPauseTolerantContinuationPrefix(
                endingAt: point
            )
            let hasSustainedResumption = hasSustainedTrainingResumption(
                endingAt: point
            )
            if hasPausePrefix || hasSustainedResumption {
                let hasVerifiedBoundaryLaunch = hasPausePrefix
                    && !endSequenceStartedIncomplete
                    && !endSequenceHasOutboundLeadIn
                    && endCandidateInitialPoseAngle
                        < configuration.minimumIncompleteGravityAngle
                // Once an end candidate exists, a single shake, wrist raise,
                // or walking motion must not restart it. Only sustained motion
                // or a signed launch from a verified repetition boundary can
                // replace the original end anchor.
                if hasSustainedResumption || hasVerifiedBoundaryLaunch {
                    if let pause = pendingVerifiedPauseDuration,
                       pause >= configuration.minimumLearnedPauseDuration,
                       !endSequenceStartedIncomplete,
                       !endSequenceHasOutboundLeadIn {
                        recordVerifiedPause(pause)
                    }
                    // The boundary-launch exception is deliberately unavailable
                    // to incomplete or outbound handling sequences.
                    clearEndSequenceForVerifiedContinuation()
                } else {
                    // A matching prefix is useful evidence, but it is not a
                    // completed repetition. It receives one bounded chance to
                    // finish and can never restart the hard clock again.
                    extendEndSequenceForContinuationPrefix(at: point)
                }
                cancelEndCandidateForContinuation(at: point)
                if let latestTrainingPoint = endWindow.last(where: isTrainingLike) {
                    lastTrainingLikePoint = latestTrainingPoint
                    lastSemanticMotionPoint = latestTrainingPoint
                    updateActiveProfile(with: latestTrainingPoint)
                } else {
                    lastSemanticMotionPoint = point
                }
                return nil
            }
        }

        if hasCompletedIncompleteExcursion(endingAt: point) {
            if endCandidateStart != nil {
                cancelEndCandidateForContinuation(at: point)
            }
            clearEndSequenceForVerifiedContinuation()
            verifiedContinuationGraceUntil = point.uptime + 0.28
            verifiedContinuationQuietBeganAt = nil
            lastTrainingLikePoint = point
            lastSemanticMotionPoint = point
            return nil
        }

        if hasCompletedClosedLoopAfterPrefix(endingAt: point) {
            if let pause = endSequencePendingPauseDuration,
               pause >= configuration.minimumLearnedPauseDuration,
               !endSequenceStartedIncomplete,
               !endSequenceHasOutboundLeadIn {
                recordVerifiedPause(pause)
            }
            if endCandidateStart != nil {
                cancelEndCandidateForContinuation(at: point)
            }
            commitVerifiedBoundary(at: point)
            verifiedContinuationGraceUntil = nil
            lastTrainingLikePoint = point
            lastSemanticMotionPoint = point
            clearEndSequenceForVerifiedContinuation()
            return nil
        }

        if let hardDeadline = endSequenceHardDeadline,
           point.uptime >= hardDeadline - 0.02,
           let anchor = endSequenceAnchor {
            return completeActiveSet(estimatedEnd: anchor.date)
        }

        guard observedMotionSinceActivation,
              let activeStartUptime,
              point.uptime - activeStartUptime >= configuration.minimumSetDuration else {
            return nil
        }

        let requiredDuration = adaptiveEndConfirmationDuration
        guard let endCandidateStart,
              point.uptime - endCandidateStart.uptime >= requiredDuration - 0.02 else {
            return nil
        }
        if let protectedUntil = endCandidateProtectedUntil,
           point.uptime < protectedUntil - 0.02 {
            return nil
        }
        let candidateDuration = point.uptime - endCandidateStart.uptime
        if candidateDuration
                < configuration.maximumResumptionGraceDuration - 0.02,
           continuationEvidenceBeganAt != nil {
            // A matching directional prefix may start just before the normal
            // boundary deadline. Let the fixed hard window decide it instead
            // of cutting off a deliberately slow next repetition mid-start.
            return nil
        }
        if endCandidateProtectedUntil == nil,
           candidateDuration < configuration.maximumResumptionGraceDuration - 0.02,
           hasRecentTrainingLikeEvidence(endingAt: point) {
            // A real next repetition may begin immediately before the normal
            // deadline. Give it only the remaining hard-limit window to prove
            // that training resumed; unrelated movement still cannot restart
            // the entire confirmation period.
            return nil
        }
        let estimatedEnd = endSequenceAnchor?.date ?? endCandidateStart.date
        return completeActiveSet(estimatedEnd: estimatedEnd)
    }

    private func completeActiveSet(estimatedEnd: Date) -> SetDetectionEvent {
        promoteCurrentSetPattern()
        phase = .idle
        resetStartCandidate()
        activeStartUptime = nil
        observedMotionSinceActivation = false
        resetActiveAnalysis()
        clearActiveSemanticProfile()
        return .setEnded(estimatedEnd: estimatedEnd)
    }

    private func strongestStartPattern(
        in points: [WindowPoint]
    ) -> StartPatternMatch? {
        guard let first = points.first,
              let last = points.last else {
            return nil
        }
        let availableDuration = last.uptime - first.uptime
        let maximumPeriod = min(
            configuration.maximumStartPeriod,
            availableDuration / 2
        )
        guard maximumPeriod >= configuration.minimumStartPeriod else {
            return nil
        }

        var best: StartPatternMatch?
        var period = configuration.minimumStartPeriod
        while period <= maximumPeriod + 0.000_1 {
            if let match = evaluateStartPattern(in: points, period: period),
               best.map({ match.quality > $0.quality }) ?? true {
                best = match
            }
            period += configuration.startPeriodSearchStep
        }
        if let coarseBest = best {
            let refinement = configuration.startPeriodSearchStep / 2
            for refinedPeriod in [
                coarseBest.period - refinement,
                coarseBest.period + refinement
            ] where refinedPeriod >= configuration.minimumStartPeriod
                    && refinedPeriod <= maximumPeriod {
                if let match = evaluateStartPattern(
                    in: points,
                    period: refinedPeriod
                ), match.quality > (best?.quality ?? -.infinity) {
                    best = match
                }
            }
        }
        return best
    }

    private func evaluateStartPattern(
        in points: [WindowPoint],
        period: TimeInterval
    ) -> StartPatternMatch? {
        guard let last = points.last else { return nil }
        let cycleStartUptime = last.uptime - period * 2
        let secondCycleStartUptime = last.uptime - period
        guard let firstPoint = points.first,
              firstPoint.uptime <= cycleStartUptime + 0.025,
              let cycleStart = interpolatedPoint(
                at: cycleStartUptime,
                in: points
              ) else {
            return nil
        }

        let phaseCount = max(12, configuration.startPatternSampleCount)
        guard let firstCycle = resampledTrajectory(
            in: points,
            from: cycleStartUptime,
            duration: period,
            sampleCount: phaseCount
        ), let secondCycle = resampledTrajectory(
            in: points,
            from: secondCycleStartUptime,
            duration: period,
            sampleCount: phaseCount
        ) else {
            return nil
        }

        let firstWaveform = centeredNormalizedWaveform(firstCycle)
        let secondWaveform = centeredNormalizedWaveform(secondCycle)
        guard !firstWaveform.isEmpty,
              firstWaveform.count == secondWaveform.count else {
            return nil
        }
        let cycleSimilarity = zip(firstWaveform, secondWaveform)
            .reduce(0) { $0 + $1.0 * $1.1 }
        guard cycleSimilarity >= configuration.minimumStartCycleSimilarity else {
            return nil
        }

        let relevant = points.filter {
            $0.uptime >= cycleStartUptime && $0.uptime <= last.uptime
        }
        guard !relevant.isEmpty else { return nil }
        let activeFloor = currentStartThreshold * 0.70
        let activeRatio = Double(relevant.filter { $0.score >= activeFloor }.count)
            / Double(relevant.count)
        guard activeRatio >= configuration.minimumStartActiveRatio else {
            return nil
        }
        let meanScore = relevant.map(\.score).reduce(0, +)
            / Double(relevant.count)
        let meanScoreRatio = meanScore / max(currentStartThreshold, 0.001)
        guard meanScoreRatio >= configuration.minimumStartMeanScoreRatio else {
            return nil
        }

        let firstEnergy = waveformEnergy(firstCycle)
        let secondEnergy = waveformEnergy(secondCycle)
        guard firstEnergy > 0.000_001, secondEnergy > 0.000_001 else {
            return nil
        }
        let energyBalance = min(firstEnergy, secondEnergy)
            / max(firstEnergy, secondEnergy)
        guard energyBalance >= configuration.minimumStartEnergyBalance else {
            return nil
        }

        let firstShare = averageAccelerationShare(
            in: relevant,
            from: cycleStartUptime,
            to: secondCycleStartUptime
        )
        let secondShare = averageAccelerationShare(
            in: relevant,
            from: secondCycleStartUptime,
            to: last.uptime
        )
        let shareDifference = abs(firstShare - secondShare)
        guard shareDifference
            <= configuration.maximumCycleAccelerationShareDifference else {
            return nil
        }

        let impulseShare = maximumImpulseShare(in: relevant)
        guard impulseShare <= configuration.maximumStartImpulseShare else {
            return nil
        }

        let reversalScore = dominantChannelReversalScore(
            firstCycle: firstCycle,
            secondCycle: secondCycle
        )
        guard reversalScore >= configuration.minimumStartReversalScore
                || cycleSimilarity >= 0.76 else {
            return nil
        }

        let gravityReturn = gravityReturnScore(
            in: points,
            start: cycleStartUptime,
            middle: secondCycleStartUptime,
            end: last.uptime
        )
        let shareConsistency = max(
            0,
            1 - shareDifference
                / max(configuration.maximumCycleAccelerationShareDifference, 0.01)
        )
        let activityScore = min(
            1,
            activeRatio / max(configuration.targetStartActiveRatio, 0.01)
        )
        let impulseConsistency = clampedProgress(
            configuration.maximumStartImpulseShare - impulseShare,
            from: 0,
            to: configuration.maximumStartImpulseShare - 0.32
        )
        let quality = cycleSimilarity * 0.46
            + reversalScore * 0.16
            + activityScore * 0.12
            + energyBalance * 0.09
            + shareConsistency * 0.07
            + impulseConsistency * 0.06
            + gravityReturn * 0.04

        let averagedWaveform = normalizedAverage(
            firstWaveform,
            secondWaveform
        )
        let signature = PatternSignature(
            period: period,
            phaseSampleCount: phaseCount,
            normalizedWaveform: averagedWaveform,
            accelerationShare: (firstShare + secondShare) / 2
        )
        return StartPatternMatch(
            firstCycleStart: cycleStart,
            period: period,
            cycleSimilarity: cycleSimilarity,
            activeRatio: activeRatio,
            meanScoreRatio: meanScoreRatio,
            energyBalance: energyBalance,
            reversalScore: reversalScore,
            impulseShare: impulseShare,
            quality: quality,
            signature: signature
        )
    }

    private func strongestAmbientPattern() -> PatternSignature? {
        strongestStartPattern(in: restObservationWindow)?.signature
    }

    private func similarityToArmedAmbientPattern(
        for match: StartPatternMatch
    ) -> Double {
        guard let ambientPattern else { return 0 }
        var similarity = signatureSimilarity(match.signature, ambientPattern)
        if let samePeriodAmbient = evaluateStartPattern(
            in: restObservationWindow,
            period: match.period
        ) {
            similarity = max(
                similarity,
                signatureSimilarity(match.signature, samePeriodAmbient.signature)
            )
        }
        return similarity
    }

    private func strongestGenericStartPattern(
        in points: [WindowPoint]
    ) -> (match: StartPatternMatch, estimatedStart: WindowPoint)? {
        guard let first = points.first,
              let last = points.last else {
            return nil
        }
        let availableDuration = last.uptime - first.uptime
        let maximumPeriod = min(
            configuration.maximumStartPeriod,
            availableDuration / 3
        )
        guard maximumPeriod >= configuration.minimumStartPeriod else {
            return nil
        }

        var best: (match: StartPatternMatch, estimatedStart: WindowPoint)?
        var period = configuration.minimumStartPeriod
        while period <= maximumPeriod + 0.000_1 {
            if let match = evaluateStartPattern(in: points, period: period),
               let estimatedStart = precedingConsistentCycleStart(
                before: match,
                in: points
               ), best.map({ match.quality > $0.match.quality }) ?? true {
                best = (match, estimatedStart)
            }
            period += configuration.startPeriodSearchStep
        }
        if let coarseBest = best {
            let refinement = configuration.startPeriodSearchStep / 2
            for refinedPeriod in [
                coarseBest.match.period - refinement,
                coarseBest.match.period + refinement
            ] where refinedPeriod >= configuration.minimumStartPeriod
                    && refinedPeriod <= maximumPeriod {
                if let match = evaluateStartPattern(
                    in: points,
                    period: refinedPeriod
                ), let estimatedStart = precedingConsistentCycleStart(
                    before: match,
                    in: points
                ), match.quality > (best?.match.quality ?? -.infinity) {
                    best = (match, estimatedStart)
                }
            }
        }
        return best
    }

    private func precedingConsistentCycleStart(
        before match: StartPatternMatch,
        in points: [WindowPoint]
    ) -> WindowPoint? {
        let precedingStartUptime = match.firstCycleStart.uptime - match.period
        guard let first = points.first,
              first.uptime <= precedingStartUptime + 0.025,
              let precedingStart = interpolatedPoint(
                at: precedingStartUptime,
                in: points
              ) else {
            return nil
        }
        let phaseCount = max(12, configuration.startPatternSampleCount)
        guard let precedingCycle = resampledTrajectory(
            in: points,
            from: precedingStartUptime,
            duration: match.period,
            sampleCount: phaseCount
        ), let firstMatchedCycle = resampledTrajectory(
            in: points,
            from: match.firstCycleStart.uptime,
            duration: match.period,
            sampleCount: phaseCount
        ) else {
            return nil
        }
        let precedingWaveform = centeredNormalizedWaveform(precedingCycle)
        let matchedWaveform = centeredNormalizedWaveform(firstMatchedCycle)
        guard !precedingWaveform.isEmpty,
              precedingWaveform.count == matchedWaveform.count else {
            return nil
        }
        let similarity = zip(precedingWaveform, matchedWaveform)
            .reduce(0) { $0 + $1.0 * $1.1 }
        guard similarity >= configuration.minimumStartCycleSimilarity - 0.025 else {
            return nil
        }
        let precedingEnergy = waveformEnergy(precedingCycle)
        let matchedEnergy = waveformEnergy(firstMatchedCycle)
        guard precedingEnergy > 0.000_001, matchedEnergy > 0.000_001 else {
            return nil
        }
        let balance = min(precedingEnergy, matchedEnergy)
            / max(precedingEnergy, matchedEnergy)
        guard balance >= configuration.minimumStartEnergyBalance else {
            return nil
        }
        return precedingStart
    }

    private func resampledTrajectory(
        in points: [WindowPoint],
        from start: TimeInterval,
        duration: TimeInterval,
        sampleCount: Int
    ) -> [[Double]]? {
        guard sampleCount >= 2 else { return nil }
        var result: [[Double]] = []
        result.reserveCapacity(sampleCount)
        for index in 0..<sampleCount {
            let fraction = Double(index) / Double(sampleCount)
            let uptime = start + duration * fraction
            guard let point = interpolatedPoint(at: uptime, in: points) else {
                return nil
            }
            result.append(trajectoryChannels(for: point))
        }
        return result
    }

    private func trajectoryChannels(for point: WindowPoint) -> [Double] {
        let accelerationFactor = sqrt(configuration.accelerationWeight)
            / configuration.accelerationScale
        let rotationFactor = sqrt(configuration.rotationWeight)
            / configuration.rotationScale
        return [
            point.acceleration.x * accelerationFactor,
            point.acceleration.y * accelerationFactor,
            point.acceleration.z * accelerationFactor,
            point.rotation.x * rotationFactor,
            point.rotation.y * rotationFactor,
            point.rotation.z * rotationFactor
        ]
    }

    private func centeredNormalizedWaveform(_ samples: [[Double]]) -> [Double] {
        guard let channelCount = samples.first?.count,
              channelCount > 0,
              samples.allSatisfy({ $0.count == channelCount }) else {
            return []
        }
        var means = Array(repeating: 0.0, count: channelCount)
        for sample in samples {
            for channel in 0..<channelCount {
                means[channel] += sample[channel]
            }
        }
        for channel in 0..<channelCount {
            means[channel] /= Double(samples.count)
        }

        var flattened: [Double] = []
        flattened.reserveCapacity(samples.count * channelCount)
        for sample in samples {
            for channel in 0..<channelCount {
                flattened.append(sample[channel] - means[channel])
            }
        }
        let norm = sqrt(flattened.reduce(0) { $0 + $1 * $1 })
        guard norm > 0.000_001 else { return [] }
        return flattened.map { $0 / norm }
    }

    private func waveformEnergy(_ samples: [[Double]]) -> Double {
        samples.reduce(0) { total, sample in
            total + sample.reduce(0) { $0 + $1 * $1 }
        }
    }

    private func normalizedAverage(_ lhs: [Double], _ rhs: [Double]) -> [Double] {
        guard lhs.count == rhs.count else { return lhs }
        let average = zip(lhs, rhs).map { ($0 + $1) / 2 }
        let norm = sqrt(average.reduce(0) { $0 + $1 * $1 })
        guard norm > 0.000_001 else { return lhs }
        return average.map { $0 / norm }
    }

    private func dominantChannelReversalScore(
        firstCycle: [[Double]],
        secondCycle: [[Double]]
    ) -> Double {
        guard let channelCount = firstCycle.first?.count,
              channelCount > 0 else {
            return 0
        }
        var channelEnergy = Array(repeating: 0.0, count: channelCount)
        for sample in firstCycle + secondCycle {
            for channel in 0..<channelCount {
                channelEnergy[channel] += sample[channel] * sample[channel]
            }
        }
        guard let dominant = channelEnergy.indices.max(by: {
            channelEnergy[$0] < channelEnergy[$1]
        }) else {
            return 0
        }
        let firstValues = firstCycle.map { $0[dominant] }
        let secondValues = secondCycle.map { $0[dominant] }
        return (
            reversalScore(in: firstValues)
                + reversalScore(in: secondValues)
        ) / 2
    }

    private func reversalScore(in values: [Double]) -> Double {
        guard values.count >= 4 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let centered = values.map { $0 - mean }
        let rms = sqrt(centered.reduce(0) { $0 + $1 * $1 } / Double(values.count))
        guard rms > 0.000_001 else { return 0 }
        let deadBand = rms * 0.16
        var previousSign = 0
        var changes = 0
        for value in centered {
            let sign: Int
            if value > deadBand {
                sign = 1
            } else if value < -deadBand {
                sign = -1
            } else {
                continue
            }
            if previousSign != 0, sign != previousSign {
                changes += 1
            }
            previousSign = sign
        }
        return min(1, Double(changes) / 2)
    }

    private func maximumImpulseShare(in points: [WindowPoint]) -> Double {
        guard !points.isEmpty else { return 1 }
        let energies = points.map { $0.score * $0.score }
        let total = energies.reduce(0, +)
        guard total > 0.000_001 else { return 1 }
        let rollingCount = max(2, Int((0.30 * 25).rounded()))
        var rolling = 0.0
        var maximum = 0.0
        for index in energies.indices {
            rolling += energies[index]
            if index >= rollingCount {
                rolling -= energies[index - rollingCount]
            }
            maximum = max(maximum, rolling)
        }
        return maximum / total
    }

    private func averageAccelerationShare(
        in points: [WindowPoint],
        from start: TimeInterval,
        to end: TimeInterval
    ) -> Double {
        let selected = points.filter {
            $0.uptime >= start && $0.uptime < end
        }
        guard !selected.isEmpty else { return 0.5 }
        return selected.map(\.accelerationShare).reduce(0, +)
            / Double(selected.count)
    }

    private func gravityReturnScore(
        in points: [WindowPoint],
        start: TimeInterval,
        middle: TimeInterval,
        end: TimeInterval
    ) -> Double {
        guard let startGravity = interpolatedPoint(at: start, in: points)?.gravity,
              let middleGravity = interpolatedPoint(at: middle, in: points)?.gravity,
              let endGravity = interpolatedPoint(at: end, in: points)?.gravity else {
            return 0
        }
        let firstReturn = cosineSimilarity(startGravity, middleGravity)
        let secondReturn = cosineSimilarity(middleGravity, endGravity)
        let weakest = min(firstReturn, secondReturn)
        return min(1, max(0, (weakest - 0.82) / 0.18))
    }

    private func cosineSimilarity(_ lhs: MotionVector3, _ rhs: MotionVector3) -> Double {
        let denominator = lhs.magnitude * rhs.magnitude
        guard denominator > 0.000_001 else { return 0 }
        return lhs.dot(rhs) / denominator
    }

    private func interpolatedPoint(
        at uptime: TimeInterval,
        in points: [WindowPoint]
    ) -> WindowPoint? {
        guard let first = points.first,
              let last = points.last,
              uptime >= first.uptime - 0.000_1,
              uptime <= last.uptime + 0.000_1 else {
            return nil
        }
        if uptime <= first.uptime { return first }
        if uptime >= last.uptime { return last }
        guard let upperIndex = points.firstIndex(where: { $0.uptime >= uptime }),
              upperIndex > points.startIndex else {
            return nil
        }
        let lower = points[points.index(before: upperIndex)]
        let upper = points[upperIndex]
        let span = upper.uptime - lower.uptime
        let fraction = span > 0 ? (uptime - lower.uptime) / span : 0
        return WindowPoint(
            date: lower.date.addingTimeInterval(uptime - lower.uptime),
            uptime: uptime,
            score: lower.score + (upper.score - lower.score) * fraction,
            rawScore: lower.rawScore + (upper.rawScore - lower.rawScore) * fraction,
            accelerationShare: lower.accelerationShare
                + (upper.accelerationShare - lower.accelerationShare) * fraction,
            acceleration: lower.acceleration.interpolated(
                to: upper.acceleration,
                fraction: fraction
            ),
            rotation: lower.rotation.interpolated(
                to: upper.rotation,
                fraction: fraction
            ),
            gravity: lower.gravity.interpolated(
                to: upper.gravity,
                fraction: fraction
            ),
            rawGravity: lower.rawGravity.interpolated(
                to: upper.rawGravity,
                fraction: fraction
            ),
            attitude: {
                guard let lowerAttitude = lower.attitude,
                      let upperAttitude = upper.attitude else {
                    return lower.attitude ?? upper.attitude
                }
                return lowerAttitude.interpolated(
                    to: upperAttitude,
                    fraction: fraction
                )
            }()
        )
    }

    private func signatureSimilarity(
        _ lhs: PatternSignature,
        _ rhs: PatternSignature
    ) -> Double {
        guard lhs.phaseSampleCount == rhs.phaseSampleCount,
              lhs.normalizedWaveform.count == rhs.normalizedWaveform.count,
              lhs.phaseSampleCount > 0 else {
            return 0
        }
        let channelCount = lhs.normalizedWaveform.count / lhs.phaseSampleCount
        guard channelCount > 0 else { return 0 }

        var bestWaveformSimilarity = -1.0
        for shift in 0..<lhs.phaseSampleCount {
            var dotProduct = 0.0
            for phase in 0..<lhs.phaseSampleCount {
                let shiftedPhase = (phase + shift) % lhs.phaseSampleCount
                for channel in 0..<channelCount {
                    let lhsIndex = phase * channelCount + channel
                    let rhsIndex = shiftedPhase * channelCount + channel
                    dotProduct += lhs.normalizedWaveform[lhsIndex]
                        * rhs.normalizedWaveform[rhsIndex]
                }
            }
            bestWaveformSimilarity = max(bestWaveformSimilarity, dotProduct)
        }

        let periodRatio = min(lhs.period, rhs.period) / max(lhs.period, rhs.period)
        let shareScore = max(
            0,
            1 - abs(lhs.accelerationShare - rhs.accelerationShare) / 0.35
        )
        return max(0, bestWaveformSimilarity) * 0.78
            + periodRatio * 0.14
            + shareScore * 0.08
    }

    private func updatePendingStartConfirmation(
        with match: StartPatternMatch,
        estimatedStart: WindowPoint,
        at uptime: TimeInterval
    ) {
        if let pendingStartPeriod {
            let periodDifference = abs(pendingStartPeriod - match.period)
                / max(pendingStartPeriod, match.period)
            if periodDifference > 0.34 {
                resetPendingStartConfirmation()
            }
        }

        if startConfirmationBeganAt == nil {
            startConfirmationBeganAt = uptime
            pendingEstimatedStart = estimatedStart
        }
        pendingStartPeriod = match.period
        pendingStartSignature = match.signature
        lastStartEvidenceUptime = uptime
    }

    private func decayPendingStartConfirmation(at uptime: TimeInterval) {
        guard let lastStartEvidenceUptime else {
            resetPendingStartConfirmation()
            return
        }
        if uptime - lastStartEvidenceUptime
            > configuration.startEvidenceGraceDuration {
            resetPendingStartConfirmation()
        }
    }

    private func updateAmbientReleaseState(with point: WindowPoint) {
        let quietThreshold = max(
            currentEndThreshold * 1.08,
            currentStartThreshold * 0.48
        )
        if point.score <= quietThreshold {
            idleQuietBeganAt = idleQuietBeganAt ?? point.uptime
            if let idleQuietBeganAt,
               point.uptime - idleQuietBeganAt
                >= configuration.ambientQuietReleaseDuration {
                ambientPattern = nil
                ambientMotifs.removeAll(keepingCapacity: true)
            }
        } else {
            idleQuietBeganAt = nil
        }
    }

    private func trimStartCandidate(endingAt point: WindowPoint) {
        let cutoff = point.uptime - configuration.startCandidateMaximumDuration
        guard let first = startCandidateWindow.first,
              first.uptime < cutoff else {
            return
        }
        startCandidateWindow.removeAll { $0.uptime < cutoff }
        // A rolling raw window must not cancel a fresh confirmation on every
        // 25 Hz sample. Only discard it when the evidence it references was
        // actually trimmed away.
        if let pendingEstimatedStart,
           pendingEstimatedStart.uptime < cutoff {
            resetPendingStartConfirmation()
        }
    }

    private func resetStartCandidate() {
        resetPeriodicStartCandidate()
        resetMotifStartCandidate()
    }

    private func resetPeriodicStartCandidate() {
        startCandidateWindow.removeAll(keepingCapacity: true)
        lastStartCandidateMotionUptime = nil
        lastStartAnalysisUptime = nil
        lastCredibleStartPatternUptime = nil
        resetPendingStartConfirmation()
    }

    private func resetMotifStartCandidate() {
        motifPreRoll.removeAll(keepingCapacity: true)
        motifSegmentPoints.removeAll(keepingCapacity: true)
        motifLastActivityUptime = nil
        completedMotifs.removeAll(keepingCapacity: true)
    }

    private func resetConsensusDiagnostics() {
        lastConsensusVoteCount = 0
        lastConsensusAverageSimilarity = 0
        lastConsensusRequiredSimilarity = 0
        lastConsensusStatus = "等待重复动作"
    }

    private func resetPendingStartConfirmation() {
        startConfirmationBeganAt = nil
        pendingEstimatedStart = nil
        pendingStartPeriod = nil
        pendingStartSignature = nil
        lastStartEvidenceUptime = nil
    }

    private func promoteCurrentSetPattern() {
        guard currentSetPattern != nil || currentSetMotif != nil else { return }
        lastSetPattern = currentSetPattern
        lastSetMotif = currentSetMotif
        lastSetExpectedPeriod = activeExpectedPeriod
        lastSetExpectedPause = activeExpectedPause
        lastSetUsedPauseTolerantPattern = activeUsesPauseTolerantPattern
        currentSetPattern = nil
        currentSetMotif = nil
    }

    private var adaptiveEndConfirmationDuration: TimeInterval {
        guard peakIntervals.count >= 2 else {
            return configuration.defaultEndConfirmationDuration
        }
        let sorted = peakIntervals.sorted()
        let median = sorted[sorted.count / 2]
        return min(
            configuration.maximumEndConfirmationDuration,
            max(
                configuration.minimumEndConfirmationDuration,
                median * configuration.cadenceEndMultiplier
            )
        )
    }

    private func updatePeakIntervals(
        with point: WindowPoint,
        recordInterval: Bool
    ) -> WindowPoint? {
        defer {
            twoPointsAgo = previousPoint
            previousPoint = point
        }

        guard let twoPointsAgo,
              let previousPoint,
              previousPoint.score > twoPointsAgo.score,
              previousPoint.score >= point.score,
              previousPoint.score >= currentStartThreshold else {
            return nil
        }

        guard recordInterval else { return previousPoint }

        guard let lastPeakUptime else {
            self.lastPeakUptime = previousPoint.uptime
            return previousPoint
        }

        let interval = previousPoint.uptime - lastPeakUptime
        guard interval >= configuration.minimumPeakInterval else { return nil }
        self.lastPeakUptime = previousPoint.uptime
        guard interval <= configuration.maximumPeakInterval else { return previousPoint }
        peakIntervals.append(interval)
        if peakIntervals.count > 8 {
            peakIntervals.removeFirst(peakIntervals.count - 8)
        }
        return previousPoint
    }

    private func updateActiveProfile(with point: WindowPoint) {
        guard point.score >= currentStartThreshold * 0.85 else { return }
        if activeScoreAverage == 0 {
            activeScoreAverage = point.score
            activeAccelerationShareAverage = point.accelerationShare
            return
        }
        let learningRate = configuration.activeScoreLearningRate
        activeScoreAverage += learningRate * (point.score - activeScoreAverage)
        activeAccelerationShareAverage += learningRate
            * (point.accelerationShare - activeAccelerationShareAverage)
    }

    private func isTrainingLike(_ point: WindowPoint) -> Bool {
        let scoreThreshold = max(
            currentStartThreshold * configuration.continuationStartThresholdFraction,
            activeScoreAverage * configuration.continuationScoreFraction
        )
        guard point.score >= scoreThreshold else { return false }
        guard activeScoreAverage > 0 else { return true }
        return abs(point.accelerationShare - activeAccelerationShareAverage)
            <= configuration.continuationProfileTolerance
    }

    private func isCoherentSlowTrainingMotion(
        endingAt point: WindowPoint
    ) -> Bool {
        let cutoff = point.uptime - configuration.semanticProgressLookbackDuration
        let observations = endWindow.filter { $0.uptime >= cutoff }
        guard let first = observations.first,
              let last = observations.last,
              observations.count >= 5,
              last.uptime - first.uptime
                >= configuration.minimumSemanticProgressDuration else {
            return false
        }

        let averageShare = observations.map(\.accelerationShare).reduce(0, +)
            / Double(observations.count)
        guard activeScoreAverage == 0
                || abs(averageShare - activeAccelerationShareAverage)
                    <= configuration.semanticProgressProfileTolerance else {
            return false
        }

        let poseValues: [Double]
        if activeHasReliableBoundary,
           activeBoundaryGravity != nil {
            poseValues = observations.map(poseAngleFromActiveBoundary)
        } else {
            poseValues = observations.map {
                poseDistance(from: first, to: $0)
            }
        }
        let poseTravel = zip(poseValues, poseValues.dropFirst()).reduce(0.0) {
            $0 + abs($1.1 - $1.0)
        }
        let poseNet = abs((poseValues.last ?? 0) - (poseValues.first ?? 0))
        let poseEfficiency = poseTravel > 0.000_001 ? poseNet / poseTravel : 0
        let tailCutoff = last.uptime - configuration.semanticProgressTailDuration
        let tailStartIndex = observations.lastIndex {
            $0.uptime <= tailCutoff + 0.000_1
        } ?? observations.startIndex
        let tailPoseNet = abs(
            poseValues[poseValues.index(before: poseValues.endIndex)]
                - poseValues[tailStartIndex]
        )
        let hasPoseProgress = poseNet
                >= minimumSemanticPoseProgress(in: observations)
            && poseEfficiency >= configuration.minimumSemanticProgressEfficiency
            && tailPoseNet >= configuration.minimumSemanticTailPoseProgress

        var integratedRotation = MotionVector3.zero
        var rotationTravel = 0.0
        for (lower, upper) in zip(observations, observations.dropFirst()) {
            let dt = max(0, upper.uptime - lower.uptime)
            integratedRotation = MotionVector3(
                x: integratedRotation.x + (lower.rotation.x + upper.rotation.x) * 0.5 * dt,
                y: integratedRotation.y + (lower.rotation.y + upper.rotation.y) * 0.5 * dt,
                z: integratedRotation.z + (lower.rotation.z + upper.rotation.z) * 0.5 * dt
            )
            rotationTravel += (lower.rotation.magnitude + upper.rotation.magnitude)
                * 0.5 * dt
        }
        let rotationEfficiency = rotationTravel > 0.000_001
            ? integratedRotation.magnitude / rotationTravel
            : 0
        let peakRawScore = observations.map(\.rawScore).max() ?? 0
        let hasRotationProgress = rotationTravel
                >= configuration.minimumSemanticRotationTravel
            && rotationEfficiency >= configuration.minimumSemanticProgressEfficiency
            && peakRawScore >= currentEndThreshold * 0.30

        return hasPoseProgress
            && (hasRotationProgress || peakRawScore >= currentEndThreshold * 0.24)
    }

    private func minimumSemanticPoseProgress(
        in points: [WindowPoint]
    ) -> Double {
        let hasAttitude = points.contains { $0.attitude != nil }
        return hasAttitude
            ? configuration.minimumSemanticAttitudeProgress
            : configuration.minimumSemanticGravityProgress
    }

    private func poseAngleFromActiveBoundary(_ point: WindowPoint) -> Double {
        let gravityAngle = activeBoundaryGravity.map {
            angularDistance(point.rawGravity, $0)
        } ?? 0
        let attitudeAngle: Double
        if let attitude = point.attitude,
           let activeBoundaryAttitude {
            attitudeAngle = attitude.angularDistance(to: activeBoundaryAttitude)
        } else {
            attitudeAngle = 0
        }
        return max(gravityAngle, attitudeAngle)
    }

    private func poseDistance(
        from lhs: WindowPoint,
        to rhs: WindowPoint
    ) -> Double {
        let gravityAngle = angularDistance(lhs.rawGravity, rhs.rawGravity)
        let attitudeAngle: Double
        if let lhsAttitude = lhs.attitude,
           let rhsAttitude = rhs.attitude {
            attitudeAngle = lhsAttitude.angularDistance(to: rhsAttitude)
        } else {
            attitudeAngle = 0
        }
        return max(gravityAngle, attitudeAngle)
    }

    private func hasSustainedTrainingResumption(endingAt point: WindowPoint) -> Bool {
        guard let endCandidateStart else { return false }
        guard candidateTrainingPeaks.count >= 2 else { return false }
        let observation = endWindow.filter {
            $0.uptime >= endCandidateStart.uptime
                && point.uptime - $0.uptime <= configuration.resumptionWindowDuration
        }
        guard let first = observation.first,
              point.uptime - first.uptime
                >= configuration.resumptionWindowDuration - 0.08 else {
            return false
        }

        let trainingPoints = observation.filter(isTrainingLike)
        let ratio = Double(trainingPoints.count) / Double(max(observation.count, 1))
        guard ratio >= configuration.requiredResumptionRatio,
              let firstTraining = trainingPoints.first,
              let lastTraining = trainingPoints.last else {
            return false
        }
        return lastTraining.uptime - firstTraining.uptime
            >= configuration.minimumResumptionSpan - 0.08
    }

    private func hasRecentTrainingLikeEvidence(endingAt point: WindowPoint) -> Bool {
        guard let latest = endWindow.last(where: isTrainingLike) else { return false }
        return point.uptime - latest.uptime <= 0.20
    }

    private func resetActiveAnalysis(seed: [WindowPoint] = []) {
        endWindow = seed
        endCandidateStart = nil
        endLowMotionBeganAt = nil
        endLowMotionAnchor = nil
        endSequenceAnchor = nil
        endSequenceHardDeadline = nil
        endSequencePrefixExtensionUsed = false
        endSequencePrefixAcceptedAt = nil
        endSequenceContinuationMotionStartedAt = nil
        endSequenceMaximumPoseDistance = 0
        endSequenceMaximumRawScore = 0
        endSequencePendingPauseDuration = nil
        endSequenceInitialPoseAngle = 0
        endSequenceStartedIncomplete = false
        endSequenceFollowedSlowMotion = false
        endSequenceMaximumDuration = 0
        endSequenceHasOutboundLeadIn = false
        verifiedContinuationGraceUntil = nil
        verifiedContinuationQuietBeganAt = nil
        endCandidateProtectedUntil = nil
        endCandidateInitialPoseAngle = 0
        continuationEvidenceBeganAt = nil
        pendingVerifiedPauseDuration = nil
        candidateTrainingPeaks.removeAll(keepingCapacity: true)
        let activeScores = seed
            .map(\.score)
            .filter { $0 >= currentStartThreshold * 0.85 }
        activeScoreAverage = activeScores.isEmpty
            ? 0
            : activeScores.reduce(0, +) / Double(activeScores.count)
        let activeAccelerationShares = seed
            .filter { $0.score >= currentStartThreshold * 0.85 }
            .map(\.accelerationShare)
        activeAccelerationShareAverage = activeAccelerationShares.isEmpty
            ? 0.5
            : activeAccelerationShares.reduce(0, +) / Double(activeAccelerationShares.count)
        lastTrainingLikePoint = seed.last(where: isTrainingLike)
        lastSemanticMotionPoint = lastTrainingLikePoint ?? seed.last
        coherentSlowMotionBeganAt = nil
        recentCoherentSlowMotionUptime = nil
        twoPointsAgo = nil
        previousPoint = nil
        lastPeakUptime = nil
        peakIntervals.removeAll(keepingCapacity: true)
        for point in seed {
            _ = updatePeakIntervals(with: point, recordInterval: true)
        }
    }

    private func beginEndCandidate(at point: WindowPoint) {
        beginEndSequenceIfNeeded(at: point)
        endCandidateStart = point
        endLowMotionBeganAt = nil
        endLowMotionAnchor = nil
        candidateTrainingPeaks.removeAll(keepingCapacity: true)
        continuationEvidenceBeganAt = nil
        pendingVerifiedPauseDuration = nil

        let poseAngle = activeHasReliableBoundary
            ? poseAngleFromActiveBoundary(point)
            : 0
        endCandidateInitialPoseAngle = poseAngle
        let protectedDuration = protectedEndDuration(for: point)
        endCandidateProtectedUntil = protectedDuration.map {
            point.uptime + $0
        }
    }

    private func protectedEndDuration(for point: WindowPoint) -> TimeInterval? {
        let poseAngle = activeHasReliableBoundary
            ? poseAngleFromActiveBoundary(point)
            : 0
        let incompleteExcursion = activeHasReliableBoundary
            && poseAngle >= configuration.minimumIncompleteGravityAngle
        let expectedBoundaryPause = activeExpectedPause
            >= configuration.minimumLearnedPauseDuration
        let hasRecentSlowMotion = recentCoherentSlowMotionUptime.map {
            point.uptime - $0 <= configuration.recentSlowMotionProtectionWindow
        } ?? false
        let slowCadence = activeHasSlowCadenceEvidence || hasRecentSlowMotion
        if incompleteExcursion {
            return min(
                configuration.maximumProtectedEndDuration,
                configuration.incompleteExcursionEndDuration
            )
        }
        if expectedBoundaryPause {
            return min(
                configuration.maximumProtectedEndDuration,
                max(
                    configuration.defaultEndConfirmationDuration,
                    activeExpectedPause + configuration.protectedEndPauseMargin
                )
            )
        }
        if slowCadence {
            return min(
                configuration.maximumProtectedEndDuration,
                configuration.slowCadenceEndDuration
            )
        }
        if activeHasReliableBoundary {
            return min(
                configuration.maximumProtectedEndDuration,
                configuration.boundaryEndConfirmationDuration
            )
        }
        return nil
    }

    private func beginEndSequenceIfNeeded(at point: WindowPoint) {
        guard endSequenceAnchor == nil else { return }
        endSequenceAnchor = point
        endSequenceInitialPoseAngle = activeHasReliableBoundary
            ? poseAngleFromActiveBoundary(point)
            : 0
        endSequenceStartedIncomplete = activeHasReliableBoundary
            && endSequenceInitialPoseAngle
                >= configuration.minimumIncompleteGravityAngle
        let hasRecentSlowMotion = recentCoherentSlowMotionUptime.map {
            point.uptime - $0 <= configuration.recentSlowMotionProtectionWindow
        } ?? false
        endSequenceFollowedSlowMotion = activeHasSlowCadenceEvidence
            || hasRecentSlowMotion
        endSequenceHasOutboundLeadIn = hasOutboundLeadIn(endingAt: point)
        endSequenceMaximumDuration = endSequenceFollowedSlowMotion
            ? configuration.maximumProtectedEndDuration
            : min(
                configuration.maximumProtectedEndDuration,
                configuration.maximumNormalEndSequenceDuration
            )
        let protectedDuration = protectedEndDuration(for: point) ?? 0
        let duration = min(
            endSequenceMaximumDuration,
            max(configuration.normalEndHardDeadlineDuration, protectedDuration)
        )
        endSequenceHardDeadline = point.uptime + duration
            + configuration.endAnchorEstimationTolerance
        endSequencePrefixExtensionUsed = false
        endSequencePrefixAcceptedAt = nil
        endSequenceContinuationMotionStartedAt = nil
        endSequenceMaximumPoseDistance = 0
        endSequenceMaximumRawScore = 0
        endSequencePendingPauseDuration = nil
    }

    private func extendEndSequenceForContinuationPrefix(at point: WindowPoint) {
        guard let anchor = endSequenceAnchor,
              !endSequencePrefixExtensionUsed else {
            return
        }
        endSequencePrefixExtensionUsed = true
        endSequencePrefixAcceptedAt = point.uptime
        endSequenceContinuationMotionStartedAt = continuationEvidenceBeganAt
            ?? point.uptime
        endSequenceMaximumPoseDistance = endSequenceAnchor.map {
            poseDistance(from: $0, to: point)
        } ?? 0
        endSequenceMaximumRawScore = point.rawScore
        endSequencePendingPauseDuration = pendingVerifiedPauseDuration
        let absoluteDeadline = anchor.uptime
            + endSequenceMaximumDuration
            + configuration.endAnchorEstimationTolerance
        let requestedDeadline = point.uptime
            + configuration.continuationCompletionGraceDuration
        endSequenceHardDeadline = min(
            absoluteDeadline,
            max(endSequenceHardDeadline ?? anchor.uptime, requestedDeadline)
        )
    }

    private func clearEndSequenceForVerifiedContinuation() {
        endSequenceAnchor = nil
        endSequenceHardDeadline = nil
        endSequencePrefixExtensionUsed = false
        endSequencePrefixAcceptedAt = nil
        endSequenceContinuationMotionStartedAt = nil
        endSequenceMaximumPoseDistance = 0
        endSequenceMaximumRawScore = 0
        endSequencePendingPauseDuration = nil
        endSequenceInitialPoseAngle = 0
        endSequenceStartedIncomplete = false
        endSequenceFollowedSlowMotion = false
        endSequenceMaximumDuration = 0
        endSequenceHasOutboundLeadIn = false
    }

    private func hasCompletedIncompleteExcursion(
        endingAt point: WindowPoint
    ) -> Bool {
        guard endSequenceStartedIncomplete || endSequenceHasOutboundLeadIn else {
            return false
        }
        let completionLookback = max(
            configuration.semanticProgressLookbackDuration,
            0.84
        )
        let cutoff = point.uptime - completionLookback
        let observations = endWindow.filter { $0.uptime >= cutoff }
        guard let firstObservation = observations.first,
              let lastObservation = observations.last,
              observations.count >= 5,
              lastObservation.uptime - firstObservation.uptime >= 0.62 else {
            return false
        }
        func hasDirectionalProgress(
            _ values: [Double],
            direction: Double
        ) -> Bool {
            guard let first = values.first,
                  let last = values.last else {
                return false
            }
            let travel = zip(values, values.dropFirst()).reduce(0.0) {
                $0 + abs($1.1 - $1.0)
            }
            let progress = (last - first) * direction
            let efficiency = travel > 0.000_001 ? progress / travel : 0
            let peakRawScore = observations.map(\.rawScore).max() ?? 0
            let activeIndices = values.indices.dropFirst().filter { index in
                abs(values[index] - values[index - 1]) >= 0.000_8
                    || observations[index].rawScore
                        >= currentEndThreshold * 0.18
            }
            guard let firstActiveIndex = activeIndices.first,
                  let lastActiveIndex = activeIndices.last,
                  observations[lastActiveIndex].uptime
                    - observations[firstActiveIndex].uptime >= 0.58 else {
                return false
            }
            return progress >= configuration.minimumSemanticGravityProgress
                && efficiency >= configuration.minimumSemanticProgressEfficiency
                && (peakRawScore >= currentEndThreshold * 0.18
                    || progress
                        >= configuration.minimumSemanticGravityProgress * 2)
        }
        func matchesExpectedContinuation(returning: Bool) -> Bool {
            guard let currentSetMotif else { return false }
            let prefixSimilarity = returning
                ? configuration.minimumIncompleteContinuationPrefixSimilarity
                : configuration.minimumIncompleteSlowOutgoingPrefixSimilarity
            let requiredSimilarity = endSequenceHasOutboundLeadIn
                ? max(
                    prefixSimilarity,
                    configuration.minimumCompletedIncompleteContinuationSimilarity
                )
                : prefixSimilarity
            let similarity = continuationPrefixSimilarity(
                observations,
                to: currentSetMotif,
                returning: returning
            )
            if returning && !endSequenceHasOutboundLeadIn {
                // A quiet candidate can begin on the slow tail of a real rep.
                // Returning substantially to the learned boundary completes
                // that already-observed excursion even when its speed differs
                // too much from the saved waveform for correlation to help.
                return true
            }
            return similarity >= requiredSimilarity
        }

        if endSequenceStartedIncomplete {
            let currentAngle = poseAngleFromActiveBoundary(point)
            if currentAngle <= endSequenceInitialPoseAngle * 0.72,
               endSequenceInitialPoseAngle - currentAngle
                    >= configuration.continuationGravityReturnAngle * 2.5,
               hasDirectionalProgress(
                    observations.map(poseAngleFromActiveBoundary),
                    direction: -1
               ), matchesExpectedContinuation(returning: true) {
                return true
            }
        }

        guard let endSequenceAnchor else {
            return false
        }
        let distance = poseDistance(from: endSequenceAnchor, to: point)
        guard distance >= configuration.minimumIncompleteGravityAngle else {
            return false
        }
        let completed = hasDirectionalProgress(
            observations.map {
                poseDistance(from: endSequenceAnchor, to: $0)
            },
            direction: 1
        )
        return completed && matchesExpectedContinuation(returning: false)
    }

    private func hasOutboundLeadIn(endingAt point: WindowPoint) -> Bool {
        let observations = endWindow.filter {
            $0.uptime >= point.uptime - 0.90
                && $0.uptime <= point.uptime + 0.02
        }
        guard let first = observations.first,
              let last = observations.last,
              last.uptime - first.uptime >= 0.52 else {
            return false
        }
        let angles = observations.map(poseAngleFromActiveBoundary)
        guard let firstAngle = angles.first,
              let lastAngle = angles.last else {
            return false
        }
        let travel = zip(angles, angles.dropFirst()).reduce(0.0) {
            $0 + abs($1.1 - $1.0)
        }
        let outwardProgress = lastAngle - firstAngle
        let efficiency = travel > 0.000_001 ? outwardProgress / travel : 0
        return outwardProgress
                >= configuration.minimumIncompleteGravityAngle * 0.42
            && efficiency >= 0.54
    }

    private func hasCompletedClosedLoopAfterPrefix(
        endingAt point: WindowPoint
    ) -> Bool {
        guard let prefixAcceptedAt = endSequencePrefixAcceptedAt,
              let anchor = endSequenceAnchor,
              point.uptime - prefixAcceptedAt >= 0.58,
              endSequenceMaximumPoseDistance
                >= configuration.minimumIncompleteGravityAngle,
              endSequenceMaximumRawScore
                >= currentEndThreshold * 0.45 else {
            return false
        }
        let currentDistance = poseDistance(from: anchor, to: point)
        guard currentDistance <= max(
            configuration.continuationGravityReturnAngle * 2.2,
            endSequenceMaximumPoseDistance * 0.32
        ), let motionStartedAt = endSequenceContinuationMotionStartedAt else {
            return false
        }
        let points = endWindow.filter {
            $0.uptime >= motionStartedAt - 0.04
                && $0.uptime <= point.uptime
        }
        guard let motif = makeMotionMotif(from: points) else { return false }
        return isTrustedCompletedContinuation(motif)
    }

    private func commitVerifiedBoundary(at point: WindowPoint) {
        guard let anchor = endSequenceAnchor else { return }
        activeBoundaryGravity = anchor.rawGravity.smoothed(
            toward: point.rawGravity,
            alpha: 0.50
        )
        if let anchorAttitude = anchor.attitude,
           let pointAttitude = point.attitude {
            activeBoundaryAttitude = anchorAttitude.interpolated(
                to: pointAttitude,
                fraction: 0.50
            )
        } else {
            activeBoundaryAttitude = anchor.attitude ?? point.attitude
        }
        activeHasReliableBoundary = true
    }

    private func hasPauseTolerantContinuationPrefix(
        endingAt point: WindowPoint
    ) -> Bool {
        guard let endCandidateStart,
              activeHasReliableBoundary,
              activeBoundaryGravity != nil else {
            continuationEvidenceBeganAt = nil
            return false
        }

        let currentAngle = poseAngleFromActiveBoundary(point)
        let incompleteExcursion = endCandidateInitialPoseAngle
            >= configuration.minimumIncompleteGravityAngle
        let returnsTowardBoundary = incompleteExcursion
            && currentAngle
                <= endCandidateInitialPoseAngle
                    - configuration.continuationGravityReturnAngle
        let continuesAwayFromCandidate = incompleteExcursion
            && poseDistance(from: endCandidateStart, to: point)
                >= configuration.continuationGravityReturnAngle
            && isCoherentSlowTrainingMotion(endingAt: point)
        let directionMatches: Bool
        if incompleteExcursion {
            directionMatches = returnsTowardBoundary
                || continuesAwayFromCandidate
        } else if let currentSetMotif,
                  currentSetMotif.gravityExcursion
                    >= configuration.motifMinimumGravityExcursion {
            directionMatches = currentAngle
                >= endCandidateInitialPoseAngle
                    + configuration.continuationGravityReturnAngle
                && point.rawScore
                    >= currentEndThreshold
                        * configuration.minimumContinuationMotionRatio
        } else {
            // Some exercises keep the wrist pose nearly fixed. They can still
            // resume through a matching signed acceleration/rotation prefix.
            directionMatches = point.rawScore
                >= currentStartThreshold
                    * configuration.minimumContinuationMotionRatio
        }
        guard directionMatches else {
            continuationEvidenceBeganAt = nil
            return false
        }

        continuationEvidenceBeganAt = continuationEvidenceBeganAt
            ?? point.uptime
        guard let evidenceStart = continuationEvidenceBeganAt,
              point.uptime - evidenceStart
                >= configuration.continuationPrefixDuration - 0.02 else {
            return false
        }

        let continuationPoints = endWindow.filter {
            $0.uptime >= evidenceStart - 0.000_1
        }
        let peakMotionRatio = (continuationPoints.map(\.rawScore).max() ?? 0)
            / max(currentStartThreshold, 0.001)
        let prefixSimilarity = currentSetMotif.map {
            continuationPrefixSimilarity(
                continuationPoints,
                to: $0,
                returning: returnsTowardBoundary
            )
        } ?? 0
        if returnsTowardBoundary {
            let gravityReturned = endCandidateInitialPoseAngle - currentAngle
                >= configuration.continuationGravityReturnAngle * 2
            guard prefixSimilarity
                    >= configuration.minimumIncompleteContinuationPrefixSimilarity
                    || (gravityReturned
                        && peakMotionRatio
                            >= configuration.minimumContinuationMotionRatio) else {
                continuationEvidenceBeganAt = nil
                return false
            }
        } else {
            // Moving away from the boundary is not enough: a wrist raise or
            // reaching for the phone does exactly that. Require the first part
            // of the learned signed trajectory before cancelling the end.
            let requiredPrefixSimilarity = incompleteExcursion
                ? configuration.minimumIncompleteSlowOutgoingPrefixSimilarity
                : configuration.minimumBoundaryContinuationPrefixSimilarity
            guard currentSetMotif != nil,
                  peakMotionRatio
                    >= configuration.minimumContinuationMotionRatio,
                  prefixSimilarity
                    >= requiredPrefixSimilarity else {
                continuationEvidenceBeganAt = nil
                return false
            }
        }
        pendingVerifiedPauseDuration = evidenceStart - endCandidateStart.uptime
        return true
    }

    private func continuationPrefixSimilarity(
        _ points: [WindowPoint],
        to motif: MotionMotif,
        returning: Bool
    ) -> Double {
        guard let first = points.first,
              let last = points.last,
              last.uptime > first.uptime else {
            return 0
        }
        let sampleCount = 10
        guard let observedSamples = resampledMotifTrajectory(
            in: points,
            sampleCount: sampleCount
        ) else {
            return 0
        }

        let sourceSamples: [[Double]]
        let sourceStartFraction: Double
        if returning {
            sourceSamples = motif.samples.reversed().map { sample in
                var transformed = sample
                if transformed.count >= 6 {
                    transformed[3] *= -1
                    transformed[4] *= -1
                    transformed[5] *= -1
                }
                return transformed
            }
            sourceStartFraction = 0
        } else {
            sourceSamples = motif.samples
            let activityPoint = motif.points.first {
                $0.rawScore
                    >= currentStartThreshold
                        * configuration.motifActivityThresholdFraction
                    || angularDistance(motif.start.gravity, $0.gravity)
                        >= configuration.motifGravityActivityExcursion
            }
            sourceStartFraction = activityPoint.map {
                ($0.uptime - motif.start.uptime) / max(motif.duration, 0.001)
            } ?? 0
        }

        let observedDuration = last.uptime - first.uptime
        let nominalFraction = observedDuration / max(motif.duration, 0.001)
        let fractions = [0.76, 1.0, 1.26].map {
            min(0.68, max(0.18, nominalFraction * $0))
        }
        let observedWaveform = centeredNormalizedWaveform(observedSamples)
        guard !observedWaveform.isEmpty else { return 0 }

        var best = 0.0
        for fraction in fractions {
            let expected = resampledFeaturePrefix(
                sourceSamples,
                startFraction: sourceStartFraction,
                fraction: fraction,
                sampleCount: sampleCount
            )
            for warp in [-0.12, 0.0, 0.12] {
                let warped = phaseWarpedSamples(expected, amount: warp)
                let expectedWaveform = centeredNormalizedWaveform(warped)
                guard expectedWaveform.count == observedWaveform.count else {
                    continue
                }
                let waveformSimilarity = max(
                    0,
                    zip(observedWaveform, expectedWaveform)
                        .reduce(0) { $0 + $1.0 * $1.1 }
                )
                let energySimilarity = motionEnergySimilarity(
                    observedSamples,
                    expected
                )
                let observedShare = points.map(\.accelerationShare).reduce(0, +)
                    / Double(points.count)
                let shareSimilarity = max(
                    0,
                    1 - abs(observedShare - motif.accelerationShare) / 0.46
                )
                best = max(
                    best,
                    waveformSimilarity * 0.84
                        + energySimilarity * 0.08
                        + shareSimilarity * 0.08
                )
            }
        }
        return best
    }

    private func resampledFeaturePrefix(
        _ samples: [[Double]],
        startFraction: Double,
        fraction: Double,
        sampleCount: Int
    ) -> [[Double]] {
        guard samples.count >= 2, sampleCount >= 2 else { return samples }
        let clampedStart = min(0.92, max(0, startFraction))
        let clampedEnd = min(1, clampedStart + max(0, fraction))
        return (0..<sampleCount).map { index in
            let progress = Double(index) / Double(sampleCount - 1)
            let sourceFraction = clampedStart
                + (clampedEnd - clampedStart) * progress
            let position = Double(samples.count - 1) * sourceFraction
            let lower = Int(floor(position))
            let upper = min(samples.count - 1, lower + 1)
            let blend = position - Double(lower)
            guard samples[lower].count == samples[upper].count else {
                return samples[lower]
            }
            return zip(samples[lower], samples[upper]).map {
                $0 + ($1 - $0) * blend
            }
        }
    }

    private func motionEnergySimilarity(
        _ lhs: [[Double]],
        _ rhs: [[Double]]
    ) -> Double {
        func dynamicEnergy(_ samples: [[Double]]) -> Double {
            guard let first = samples.first else { return 0 }
            return samples.reduce(0) { total, sample in
                let channelLimit = min(9, min(sample.count, first.count))
                return total + (0..<channelLimit).reduce(0) { subtotal, channel in
                    let value: Double
                    if channel >= 6 {
                        value = sample[channel] - first[channel]
                    } else {
                        value = sample[channel]
                    }
                    return subtotal + value * value
                }
            } / Double(max(samples.count, 1))
        }
        let lhsEnergy = dynamicEnergy(lhs)
        let rhsEnergy = dynamicEnergy(rhs)
        guard max(lhsEnergy, rhsEnergy) > 0.000_001 else { return 0 }
        return min(lhsEnergy, rhsEnergy) / max(lhsEnergy, rhsEnergy)
    }

    private func recordVerifiedPause(_ pause: TimeInterval) {
        verifiedPauseDurations.append(pause)
        if verifiedPauseDurations.count > 5 {
            verifiedPauseDurations.removeFirst(
                verifiedPauseDurations.count - 5
            )
        }
        activeExpectedPause = max(
            activeExpectedPause,
            median(verifiedPauseDurations)
        )
        activeHasSlowCadenceEvidence = true
        activeUsesPauseTolerantPattern = true
    }

    private func cancelEndCandidateForContinuation(at point: WindowPoint) {
        endCandidateStart = nil
        endLowMotionBeganAt = nil
        endLowMotionAnchor = nil
        endCandidateProtectedUntil = nil
        endCandidateInitialPoseAngle = 0
        continuationEvidenceBeganAt = nil
        pendingVerifiedPauseDuration = nil
        candidateTrainingPeaks.removeAll(keepingCapacity: true)
        lastTrainingLikePoint = point
        lastSemanticMotionPoint = point
    }

    private func clearActiveSemanticProfile() {
        activeBoundaryGravity = nil
        activeBoundaryAttitude = nil
        activeExpectedPeriod = nil
        activeExpectedPause = 0
        activeUsesPauseTolerantPattern = false
        activeHasReliableBoundary = false
        activeHasSlowCadenceEvidence = false
        lastSemanticMotionPoint = nil
        coherentSlowMotionBeganAt = nil
        recentCoherentSlowMotionUptime = nil
        verifiedPauseDurations.removeAll(keepingCapacity: true)
        endSequenceAnchor = nil
        endSequenceHardDeadline = nil
        endSequencePrefixExtensionUsed = false
        endSequencePrefixAcceptedAt = nil
        endSequenceContinuationMotionStartedAt = nil
        endSequenceMaximumPoseDistance = 0
        endSequenceMaximumRawScore = 0
        endSequencePendingPauseDuration = nil
        endSequenceInitialPoseAngle = 0
        endSequenceStartedIncomplete = false
        endSequenceFollowedSlowMotion = false
        endSequenceMaximumDuration = 0
        endSequenceHasOutboundLeadIn = false
        verifiedContinuationGraceUntil = nil
        verifiedContinuationQuietBeganAt = nil
        endCandidateProtectedUntil = nil
        endCandidateInitialPoseAngle = 0
        continuationEvidenceBeganAt = nil
        pendingVerifiedPauseDuration = nil
        resetActiveMotifTracking()
    }

    private func learnBaseline(from score: Double, at uptime: TimeInterval) {
        guard score < currentStartThreshold else { return }
        baselineObservations.append(
            BaselineObservation(uptime: uptime, score: score)
        )
        let cutoff = uptime - configuration.baselineObservationDuration
        baselineObservations.removeAll { $0.uptime < cutoff }
        let sortedScores = baselineObservations.map(\.score).sorted()
        guard !sortedScores.isEmpty else { return }
        let percentile = min(1, max(0, configuration.baselinePercentile))
        let index = Int(
            (Double(sortedScores.count - 1) * percentile).rounded(.down)
        )
        let quietTarget = sortedScores[index]
        baselineScore += configuration.baselineLearningRate
            * (quietTarget - baselineScore)
        baselineScore = min(
            max(baselineScore, 0.005),
            configuration.maximumBaselineScore
        )
    }

    private func clampedProgress(
        _ value: Double,
        from lowerBound: Double,
        to upperBound: Double
    ) -> Double {
        guard upperBound > lowerBound else {
            return value >= upperBound ? 1 : 0
        }
        return min(
            1,
            max(0, (value - lowerBound) / (upperBound - lowerBound))
        )
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func resetSmoothedScoreToBaseline() {
        smoothedAccelerationScore = baselineScore * configuration.accelerationWeight
        smoothedRotationScore = baselineScore * configuration.rotationWeight
        smoothedScore = baselineScore
        smoothedAcceleration = .zero
        smoothedRotation = .zero
        smoothedGravity = .restingGravity
        smoothingNeedsSampleSeed = true
    }
}
