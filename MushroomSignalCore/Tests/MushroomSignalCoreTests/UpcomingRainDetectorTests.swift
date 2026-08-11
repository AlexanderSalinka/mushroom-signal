import XCTest
@testable import MushroomSignalCore

final class UpcomingRainDetectorTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func daysFromNow(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, minTempC: maxTempC - 10, precipitationMm: precipitationMm, humidityPercent: 70)
    }

    func testReturnsNilWhenNoForecastDayQualifies() {
        let days = [
            daysFromNow(1, maxTempC: 20.0, precipitationMm: 0.0),
            daysFromNow(2, maxTempC: 27.0, precipitationMm: 2.0), // rain too low
            daysFromNow(3, maxTempC: 24.0, precipitationMm: 8.0)  // temp too low
        ]
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today))
    }

    func testReturnsEventWhenBothThresholdsMetOnSameDay() {
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        let event = UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today)
        XCTAssertEqual(event?.precipitationMm, 11.0)
        XCTAssertEqual(event?.maxTempC, 28.0)
    }

    func testRainAloneWithoutHeatDoesNotQualify() {
        let days = [daysFromNow(2, maxTempC: 20.0, precipitationMm: 20.0)]
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today))
    }

    func testHeatAloneWithoutRainDoesNotQualify() {
        let days = [daysFromNow(2, maxTempC: 30.0, precipitationMm: 0.0)]
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today))
    }

    func testReturnsEarliestQualifyingDayWhenMultipleQualify() {
        let days = [
            daysFromNow(4, maxTempC: 29.0, precipitationMm: 15.0),
            daysFromNow(1, maxTempC: 27.0, precipitationMm: 6.0)
        ]
        let event = UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today)
        XCTAssertEqual(event?.date, today.addingTimeInterval(86400))
    }

    func testIgnoresPastDaysEvenIfTheyQualify() {
        let pastQualifying = DailyWeather(date: today.addingTimeInterval(-2 * 86400), meanTempC: 25, maxTempC: 30, minTempC: 20, precipitationMm: 10, humidityPercent: 70)
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: [pastQualifying], asOf: today))
    }

    func testWindowIsTwoToSevenDaysAfterTriggerDay() {
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        let event = UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today)
        XCTAssertEqual(event?.flushWindowStart, event?.date.addingTimeInterval(2 * 86400))
        XCTAssertEqual(event?.flushWindowEnd, event?.date.addingTimeInterval(7 * 86400))
    }

    func testEmptyArrayReturnsNil() {
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: [], asOf: today))
    }

    func testQualifiesAtExactThresholds() {
        let days = [daysFromNow(2, maxTempC: 26.0, precipitationMm: 5.0)]
        let event = UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today)
        XCTAssertNotNil(event)
    }

    func testTodayItselfDoesNotQualifyEvenAtThresholds() {
        let days = [daysFromNow(0, maxTempC: 26.0, precipitationMm: 5.0)]
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today))
    }
}
