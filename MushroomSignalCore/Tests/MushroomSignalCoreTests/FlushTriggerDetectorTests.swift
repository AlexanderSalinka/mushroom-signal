import XCTest
@testable import MushroomSignalCore

final class FlushTriggerDetectorTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func daysAgo(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(-Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, precipitationMm: precipitationMm)
    }

    func testTriggersOnQualifyingDayTwoDaysAgo() {
        let days = [daysAgo(2, maxTempC: 26.0, precipitationMm: 1.0)]
        XCTAssertTrue(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testTriggersOnQualifyingDaySevenDaysAgo() {
        let days = [daysAgo(7, maxTempC: 30.0, precipitationMm: 5.0)]
        XCTAssertTrue(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testDoesNotTriggerOneDayAgo() {
        let days = [daysAgo(1, maxTempC: 30.0, precipitationMm: 5.0)]
        XCTAssertFalse(FlushTriggerDetector.triggered(in: days, asOf: today), "one day ago is outside the 2-7 day lag window")
    }

    func testDoesNotTriggerEightDaysAgo() {
        let days = [daysAgo(8, maxTempC: 30.0, precipitationMm: 5.0)]
        XCTAssertFalse(FlushTriggerDetector.triggered(in: days, asOf: today), "eight days ago is outside the 2-7 day lag window")
    }

    func testDoesNotTriggerBelowTemperatureThreshold() {
        let days = [daysAgo(3, maxTempC: 25.9, precipitationMm: 5.0)]
        XCTAssertFalse(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testDoesNotTriggerWithoutRain() {
        let days = [daysAgo(3, maxTempC: 30.0, precipitationMm: 0.0)]
        XCTAssertFalse(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testTriggersIfAnyDayInWindowQualifiesEvenIfOthersDont() {
        let days = [
            daysAgo(2, maxTempC: 10.0, precipitationMm: 0.0),
            daysAgo(5, maxTempC: 27.0, precipitationMm: 2.0),
            daysAgo(6, maxTempC: 10.0, precipitationMm: 0.0)
        ]
        XCTAssertTrue(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testEmptyArrayDoesNotTrigger() {
        XCTAssertFalse(FlushTriggerDetector.triggered(in: [], asOf: today))
    }
}
