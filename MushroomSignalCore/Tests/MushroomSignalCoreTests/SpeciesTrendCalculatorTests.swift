import XCTest
@testable import MushroomSignalCore

final class SpeciesTrendCalculatorTests: XCTestCase {
    private func species(fruitingMonths: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], rainfallSensitivity: RainfallSensitivity = .low) -> Species {
        Species(id: "test", commonNameSk: "Test", latinName: "Testus", edibility: .edible, fruitingMonths: fruitingMonths, idealTempMinC: 10, idealTempMaxC: 25, idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90, rainfallSensitivity: rainfallSensitivity, habitat: "test", regionalAffinity: [])
    }

    private func day(daysFromReference: Int, reference: Date, maxTempC: Double = 20, meanTempC: Double = 15, minTempC: Double = 10, precipitationMm: Double = 10, humidityPercent: Double = 75) -> DailyWeather {
        DailyWeather(date: reference.addingTimeInterval(Double(daysFromReference) * 86400), meanTempC: meanTempC, maxTempC: maxTempC, minTempC: minTempC, precipitationMm: precipitationMm, humidityPercent: humidityPercent)
    }

    // 2026-08-07 00:00:00 UTC — matches FlushTriggerDetectorTests' reference date, so day
    // boundaries line up cleanly with 86400s-multiple offsets.
    private let today = Date(timeIntervalSince1970: 1_754_524_800)

    func testTrendReturnsOnePointPerInputDay() {
        let days = (0..<10).map { day(daysFromReference: -$0, reference: today) }
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: days, regionId: "zilinsky", today: today)
        XCTAssertEqual(points.count, 10)
    }

    func testOffSeasonDayScoresZero() {
        let outOfSeason = species(fruitingMonths: [1]) // January only; "today" is August 2026
        let days = [day(daysFromReference: -1, reference: today)]
        let points = SpeciesTrendCalculator.trend(species: outOfSeason, dailyWeather: days, regionId: "zilinsky", today: today)
        XCTAssertEqual(points.first?.score, 0)
    }

    func testFlushTriggerBoostsScoreForHighSensitivitySpecies() {
        let highSensitivity = species(rainfallSensitivity: .high)

        // Baseline: no day in range qualifies (maxTempC 20 < the 26 threshold).
        let daysWithoutTrigger = (0..<10).map { day(daysFromReference: -$0, reference: today, precipitationMm: 10, humidityPercent: 95) }
        let pointsWithoutTrigger = SpeciesTrendCalculator.trend(species: highSensitivity, dailyWeather: daysWithoutTrigger, regionId: "zilinsky", today: today)

        // 5 days before "today" now qualifies (maxTempC >= 26, precip >= 5) — inside the
        // detector's 2-7 day lag window when evaluated as-of "today" (index 0).
        var daysWithTrigger = daysWithoutTrigger
        daysWithTrigger[5] = day(daysFromReference: -5, reference: today, maxTempC: 30, precipitationMm: 10, humidityPercent: 95)
        let pointsWithTrigger = SpeciesTrendCalculator.trend(species: highSensitivity, dailyWeather: daysWithTrigger, regionId: "zilinsky", today: today)

        XCTAssertGreaterThan(pointsWithTrigger[0].score, pointsWithoutTrigger[0].score, "a qualifying flush day in the window should raise today's trend score for a high-rainfall-sensitivity species")
    }

    func testDayAfterTodayIsMarkedAsForecast() {
        let forecastDay = day(daysFromReference: 1, reference: today)
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: [forecastDay], regionId: "zilinsky", today: today)
        XCTAssertEqual(points.first?.isForecast, true)
    }

    func testDayBeforeTodayIsNotMarkedAsForecast() {
        let pastDay = day(daysFromReference: -1, reference: today)
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: [pastDay], regionId: "zilinsky", today: today)
        XCTAssertEqual(points.first?.isForecast, false)
    }

    func testTodayItselfIsNotMarkedAsForecast() {
        let todayPoint = day(daysFromReference: 0, reference: today)
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: [todayPoint], regionId: "zilinsky", today: today)
        XCTAssertEqual(points.first?.isForecast, false)
    }
}
