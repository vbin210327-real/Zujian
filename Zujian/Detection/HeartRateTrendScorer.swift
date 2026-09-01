import Foundation

struct HeartRateTrendConfiguration: Equatable {
    var observationDuration: TimeInterval = 24
    var recentWindowDuration: TimeInterval = 7
    var precedingWindowDuration: TimeInterval = 9
    var freshnessDuration: TimeInterval = 6
    var minimumRecentSampleCount: Int = 3
    var minimumPrecedingSampleCount: Int = 2
    var minimumRecentSlope: Double = 0.28
    var fullRecentSlope: Double = 1.15
    var minimumSlopeImprovement: Double = 0.38
    var fullSlopeImprovement: Double = 1.25
    var minimumMedianRise: Double = 2.5
    var fullMedianRise: Double = 9
    var maximumConfidenceBonus: Double = 0.08

    static let standard = HeartRateTrendConfiguration()
}

/// Produces optional supporting evidence for a motion-based set start.
/// A high but flat heart rate is deliberately neutral; only a fresh upward
/// inflection can add confidence, and this scorer can never start a set alone.
final class HeartRateTrendScorer {
    private struct Sample {
        let date: Date
        let bpm: Double
    }

    private let configuration: HeartRateTrendConfiguration
    private var samples: [Sample] = []

    init(configuration: HeartRateTrendConfiguration = .standard) {
        self.configuration = configuration
    }

    func observe(date: Date, bpm: Double) {
        guard bpm.isFinite, bpm > 0 else { return }
        samples.append(Sample(date: date, bpm: bpm))
        samples.sort { $0.date < $1.date }
        trim(endingAt: date)
    }

    func confidenceBonus(at date: Date) -> Double {
        trim(endingAt: date)
        guard let latest = samples.last else { return 0 }
        let latestAge = date.timeIntervalSince(latest.date)
        guard latestAge >= 0,
              latestAge <= configuration.freshnessDuration else {
            return 0
        }

        let recentStart = date.addingTimeInterval(
            -configuration.recentWindowDuration
        )
        let precedingStart = recentStart.addingTimeInterval(
            -configuration.precedingWindowDuration
        )
        let recent = samples.filter { $0.date >= recentStart && $0.date <= date }
        let preceding = samples.filter {
            $0.date >= precedingStart && $0.date < recentStart
        }
        guard recent.count >= configuration.minimumRecentSampleCount,
              preceding.count >= configuration.minimumPrecedingSampleCount else {
            return 0
        }

        let recentSlope = regressionSlope(of: recent)
        let precedingSlope = regressionSlope(of: preceding)
        let slopeImprovement = recentSlope - precedingSlope
        let medianRise = median(recent.map(\.bpm))
            - median(preceding.map(\.bpm))

        let hasNewInflection = slopeImprovement
            >= configuration.minimumSlopeImprovement
        let roseFromStableBaseline = precedingSlope
                <= configuration.minimumRecentSlope * 0.5
            && medianRise >= configuration.minimumMedianRise
        guard recentSlope >= configuration.minimumRecentSlope,
              hasNewInflection || roseFromStableBaseline else {
            return 0
        }

        let slopeScore = normalized(
            recentSlope,
            minimum: configuration.minimumRecentSlope,
            full: configuration.fullRecentSlope
        )
        let inflectionScore = normalized(
            slopeImprovement,
            minimum: configuration.minimumSlopeImprovement,
            full: configuration.fullSlopeImprovement
        )
        let riseScore = normalized(
            medianRise,
            minimum: configuration.minimumMedianRise,
            full: configuration.fullMedianRise
        )
        let evidence = slopeScore * 0.45
            + inflectionScore * 0.40
            + riseScore * 0.15
        return configuration.maximumConfidenceBonus * min(1, max(0, evidence))
    }

    func reset() {
        samples.removeAll(keepingCapacity: true)
    }

    private func trim(endingAt date: Date) {
        let cutoff = date.addingTimeInterval(-configuration.observationDuration)
        samples.removeAll { $0.date < cutoff }
    }

    private func regressionSlope(of samples: [Sample]) -> Double {
        guard let origin = samples.first?.date, samples.count >= 2 else { return 0 }
        let times = samples.map { $0.date.timeIntervalSince(origin) }
        let timeMean = times.reduce(0, +) / Double(times.count)
        let bpmMean = samples.map(\.bpm).reduce(0, +) / Double(samples.count)
        var numerator = 0.0
        var denominator = 0.0
        for (time, sample) in zip(times, samples) {
            let centeredTime = time - timeMean
            numerator += centeredTime * (sample.bpm - bpmMean)
            denominator += centeredTime * centeredTime
        }
        guard denominator > 0.000_001 else { return 0 }
        return numerator / denominator
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

    private func normalized(
        _ value: Double,
        minimum: Double,
        full: Double
    ) -> Double {
        guard full > minimum else { return value >= full ? 1 : 0 }
        return min(1, max(0, (value - minimum) / (full - minimum)))
    }
}
