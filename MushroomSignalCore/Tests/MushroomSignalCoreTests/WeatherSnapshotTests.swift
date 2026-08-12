import XCTest
@testable import MushroomSignalCore

final class WeatherSnapshotTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func day(_ offset: Int, meanTemp: Double, humidity: Double, precip: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(offset) * 86400), meanTempC: meanTemp, maxTempC: meanTemp + 5, minTempC: meanTemp - 5, precipitationMm: precip, humidityPercent: humidity)
    }

    func testReturnsNilForEmptyArray() {
        XCTAssertNil(WeatherSnapshot.derive(regionId: "zilinsky", from: [], asOf: today))
    }

    func testAveragesExactlyTheTrailingWindowDays() {
        let days = (-9...0).map { day($0, meanTemp: 20, humidity: 70, precip: 1) }
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 10, asOf: today)
        XCTAssertEqual(snapshot!.averageTempLast10DaysC, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot!.averageHumidityLast10DaysPercent, 70, accuracy: 0.001)
        XCTAssertEqual(snapshot!.totalPrecipitationLast10DaysMm, 10, accuracy: 0.001)
        XCTAssertEqual(snapshot!.regionId, "zilinsky")
    }

    func testOnlyUsesTheMostRecentWindowDaysWhenMoreAreAvailable() {
        var days = (-19...(-10)).map { day($0, meanTemp: 0, humidity: 0, precip: 0) } // older, should be excluded
        days += (-9...0).map { day($0, meanTemp: 20, humidity: 70, precip: 1) } // most recent 10, should be used
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 10, asOf: today)
        XCTAssertEqual(snapshot!.averageTempLast10DaysC, 20, accuracy: 0.001, "older days outside the window must not pull the average down")
    }

    func testUsesFewerThanWindowDaysWhenFewerAreAvailable() {
        let days = [day(-2, meanTemp: 10, humidity: 60, precip: 3), day(-1, meanTemp: 20, humidity: 80, precip: 5), day(0, meanTemp: 30, humidity: 100, precip: 7)]
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 10, asOf: today)
        XCTAssertEqual(snapshot!.averageTempLast10DaysC, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot!.totalPrecipitationLast10DaysMm, 15, accuracy: 0.001)
    }

    func testExcludesForecastDaysFromTheAverage() {
        var days = (-9...0).map { day($0, meanTemp: 20, humidity: 70, precip: 1) }
        days += [day(1, meanTemp: 100, humidity: 100, precip: 100), day(2, meanTemp: 100, humidity: 100, precip: 100)] // forecast days, must be excluded
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 10, asOf: today)
        XCTAssertEqual(snapshot!.averageTempLast10DaysC, 20, accuracy: 0.001, "forecast (future) days must never be included in a historical average")
    }

    func testRespectsACustomWindowDaysValue() {
        var days = (-6...0).map { day($0, meanTemp: 20, humidity: 70, precip: 1) } // most recent 7
        days += (-13...(-7)).map { day($0, meanTemp: 0, humidity: 0, precip: 0) } // older, excluded at windowDays: 7
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 7, asOf: today)
        XCTAssertEqual(snapshot!.averageTempLast10DaysC, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot!.totalPrecipitationLast10DaysMm, 7, accuracy: 0.001)
    }
}
