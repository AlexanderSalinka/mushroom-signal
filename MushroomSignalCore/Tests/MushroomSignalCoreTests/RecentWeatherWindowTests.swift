import XCTest
@testable import MushroomSignalCore

final class RecentWeatherWindowTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func day(_ offset: Int) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(offset) * 86400), meanTempC: 18, maxTempC: 22, minTempC: 14, precipitationMm: 2, humidityPercent: 70)
    }

    func testKeepsOnlyTheLastSevenPastDaysWhenMoreAreAvailable() {
        let days = (-10...0).map { day($0) }
        let result = RecentWeatherWindow.lastSevenDaysPlusForecast(in: days, asOf: today)
        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result.first?.date, day(-6).date)
        XCTAssertEqual(result.last?.date, day(0).date)
    }

    func testReturnsFewerThanSevenWhenFewerPastDaysExist() {
        let days = [day(-2), day(-1), day(0)]
        let result = RecentWeatherWindow.lastSevenDaysPlusForecast(in: days, asOf: today)
        XCTAssertEqual(result.count, 3)
    }

    func testIncludesAllForecastDaysRegardlessOfCount() {
        let days = [day(0), day(1), day(2), day(3), day(4), day(5)]
        let result = RecentWeatherWindow.lastSevenDaysPlusForecast(in: days, asOf: today)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.last?.date, day(5).date)
    }

    func testReturnsEmptyArrayWhenNoDataAvailable() {
        XCTAssertEqual(RecentWeatherWindow.lastSevenDaysPlusForecast(in: [], asOf: today), [])
    }

    func testPastDaysComeBeforeForecastDaysInResult() {
        let days = [day(1), day(-1), day(0), day(-2)]
        let result = RecentWeatherWindow.lastSevenDaysPlusForecast(in: days, asOf: today)
        XCTAssertEqual(result.map { $0.date }, [day(-2).date, day(-1).date, day(0).date, day(1).date])
    }
}
