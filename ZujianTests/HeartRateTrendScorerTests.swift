import XCTest
#if canImport(Zujian)
@testable import Zujian
#else
@testable import DetectionCore
#endif

final class HeartRateTrendScorerTests: XCTestCase {
    func testHighButFlatHeartRateIsNeutral() {
        let scorer = HeartRateTrendScorer()
        let start = Date()

        for second in stride(from: 0, through: 16, by: 2) {
            scorer.observe(
                date: start.addingTimeInterval(TimeInterval(second)),
                bpm: 148
            )
        }

        XCTAssertEqual(
            scorer.confidenceBonus(at: start.addingTimeInterval(16)),
            0,
            accuracy: 0.000_1
        )
    }

    func testFallingHeartRateThatTurnsUpProducesEvidence() {
        let scorer = HeartRateTrendScorer()
        let start = Date()
        let values: [(TimeInterval, Double)] = [
            (0, 144), (2, 141), (4, 138), (6, 136), (8, 134),
            (10, 133), (12, 136), (14, 140), (16, 145)
        ]

        for (time, bpm) in values {
            scorer.observe(date: start.addingTimeInterval(time), bpm: bpm)
        }

        let bonus = scorer.confidenceBonus(at: start.addingTimeInterval(16))
        XCTAssertGreaterThan(bonus, 0)
        XCTAssertLessThanOrEqual(bonus, 0.08)
    }

    func testAnOldContinuousRiseIsNotANewInflection() {
        let scorer = HeartRateTrendScorer()
        let start = Date()

        for second in stride(from: 0, through: 16, by: 2) {
            scorer.observe(
                date: start.addingTimeInterval(TimeInterval(second)),
                bpm: 118 + Double(second)
            )
        }

        XCTAssertEqual(
            scorer.confidenceBonus(at: start.addingTimeInterval(16)),
            0,
            accuracy: 0.000_1
        )
    }

    func testStaleHeartRateIsNeutral() {
        let scorer = HeartRateTrendScorer()
        let start = Date()

        for second in stride(from: 0, through: 16, by: 2) {
            let bpm = second < 10 ? 132.0 : 132.0 + Double(second - 10)
            scorer.observe(
                date: start.addingTimeInterval(TimeInterval(second)),
                bpm: bpm
            )
        }

        XCTAssertEqual(
            scorer.confidenceBonus(at: start.addingTimeInterval(24)),
            0,
            accuracy: 0.000_1
        )
    }
}
