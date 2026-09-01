import XCTest
#if canImport(Zujian)
@testable import Zujian
#else
@testable import DetectionCore
#endif

final class WorkoutStateTests: XCTestCase {
    func testRestingNeverAcceptsSetDetectionMotion() {
        XCTAssertFalse(WorkoutState.resting.acceptsSetDetectionMotion)
        XCTAssertTrue(WorkoutState.waitingForSet.acceptsSetDetectionMotion)
        XCTAssertTrue(WorkoutState.setActive.acceptsSetDetectionMotion)
    }
}
