import XCTest
@testable import MushroomSignalCore

final class NotificationThresholdTests: XCTestCase {
    func testCrossesUpwardReturnsTrue() {
        XCTAssertTrue(NotificationThreshold.shouldNotify(previousScore: 2, newScore: 3, threshold: 3))
    }

    func testStaysAboveReturnsFalse() {
        XCTAssertFalse(NotificationThreshold.shouldNotify(previousScore: 3, newScore: 4, threshold: 3), "already notified once at/above threshold — don't repeat every refresh")
    }

    func testDropsThenRisesReturnsTrue() {
        XCTAssertTrue(NotificationThreshold.shouldNotify(previousScore: 1, newScore: 3, threshold: 3))
    }

    func testStaysBelowReturnsFalse() {
        XCTAssertFalse(NotificationThreshold.shouldNotify(previousScore: 1, newScore: 2, threshold: 3))
    }

    func testNilBaselineReturnsFalse() {
        XCTAssertFalse(NotificationThreshold.shouldNotify(previousScore: nil, newScore: 4, threshold: 3), "first-ever observation establishes a silent baseline, doesn't notify immediately")
    }
}
