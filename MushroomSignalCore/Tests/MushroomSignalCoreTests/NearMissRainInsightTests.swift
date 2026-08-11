import XCTest
@testable import MushroomSignalCore

final class NearMissRainInsightTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func daysFromNow(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, minTempC: maxTempC - 10, precipitationMm: precipitationMm, humidityPercent: 70)
    }

    func testRainWithoutHeatIsDetected() {
        let days = [daysFromNow(2, maxTempC: 18.0, precipitationMm: 12.0)]
        let result = NearMissRainInsight.describe(in: days, asOf: today)
        XCTAssertEqual(result, .rainWithoutHeat(date: days[0].date, precipitationMm: 12.0, maxTempC: 18.0))
    }

    func testHeatWithoutRainIsDetected() {
        let days = [daysFromNow(3, maxTempC: 29.0, precipitationMm: 0.0)]
        let result = NearMissRainInsight.describe(in: days, asOf: today)
        XCTAssertEqual(result, .heatWithoutRain(date: days[0].date, precipitationMm: 0.0, maxTempC: 29.0))
    }

    func testFlatForecastReturnsNil() {
        let days = [daysFromNow(1, maxTempC: 18.0, precipitationMm: 0.0), daysFromNow(2, maxTempC: 20.0, precipitationMm: 1.0)]
        XCTAssertNil(NearMissRainInsight.describe(in: days, asOf: today))
    }

    func testFullTriggerDayIsSkippedNotReportedAsNearMiss() {
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        XCTAssertNil(NearMissRainInsight.describe(in: days, asOf: today))
    }

    func testReturnsEarliestQualifyingNearMiss() {
        let days = [daysFromNow(4, maxTempC: 18.0, precipitationMm: 12.0), daysFromNow(1, maxTempC: 29.0, precipitationMm: 0.0)]
        let result = NearMissRainInsight.describe(in: days, asOf: today)
        XCTAssertEqual(result, .heatWithoutRain(date: days[1].date, precipitationMm: 0.0, maxTempC: 29.0))
    }

    func testPastDaysAreIgnored() {
        let pastNearMiss = DailyWeather(date: today.addingTimeInterval(-2 * 86400), meanTempC: 15, maxTempC: 18, minTempC: 10, precipitationMm: 12.0, humidityPercent: 70)
        XCTAssertNil(NearMissRainInsight.describe(in: [pastNearMiss], asOf: today))
    }
}
