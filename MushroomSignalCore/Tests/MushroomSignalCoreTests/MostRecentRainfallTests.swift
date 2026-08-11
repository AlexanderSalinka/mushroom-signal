import XCTest
@testable import MushroomSignalCore

final class MostRecentRainfallTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func daysAgo(_ n: Int, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(-Double(n) * 86400), meanTempC: 18, maxTempC: 22, minTempC: 14, precipitationMm: precipitationMm, humidityPercent: 70)
    }

    func testFindsMostRecentRainyDay() {
        let days = [daysAgo(5, precipitationMm: 3.0), daysAgo(2, precipitationMm: 8.0), daysAgo(8, precipitationMm: 1.0)]
        let result = MostRecentRainfall.find(in: days, asOf: today)
        XCTAssertEqual(result?.precipitationMm, 8.0)
    }

    func testDryDaysDoNotCount() {
        let days = [daysAgo(1, precipitationMm: 0.0), daysAgo(2, precipitationMm: 0.0)]
        XCTAssertNil(MostRecentRainfall.find(in: days, asOf: today))
    }

    func testEmptyArrayReturnsNil() {
        XCTAssertNil(MostRecentRainfall.find(in: [], asOf: today))
    }

    func testForecastFutureDaysAreExcludedEvenIfRainy() {
        let futureRain = DailyWeather(date: today.addingTimeInterval(2 * 86400), meanTempC: 18, maxTempC: 22, minTempC: 14, precipitationMm: 20.0, humidityPercent: 80)
        let pastRain = daysAgo(4, precipitationMm: 6.0)
        let result = MostRecentRainfall.find(in: [futureRain, pastRain], asOf: today)
        XCTAssertEqual(result?.precipitationMm, 6.0)
    }

    func testMultipleRainyDaysReturnsMostRecentNotLargest() {
        let days = [daysAgo(1, precipitationMm: 2.0), daysAgo(6, precipitationMm: 40.0)]
        let result = MostRecentRainfall.find(in: days, asOf: today)
        XCTAssertEqual(result?.precipitationMm, 2.0)
    }
}
