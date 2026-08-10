import XCTest
@testable import MushroomSignalCore

final class SpeciesTrendCalculatorTests: XCTestCase {
    private func species(fruitingMonths: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], rainfallSensitivity: RainfallSensitivity = .low) -> Species {
        Species(id: "test", commonNameSk: "Test", latinName: "Testus", edibility: .edible, fruitingMonths: fruitingMonths, idealTempMinC: 10, idealTempMaxC: 25, idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90, rainfallSensitivity: rainfallSensitivity, habitat: "test", regionalAffinity: [])
    }

    private func day(daysFromReference: Int, reference: Date, maxTempC: Double = 20, meanTempC: Double = 15, minTempC: Double = 10, precipitationMm: Double = 1, humidityPercent: Double = 75) -> DailyWeather {
        DailyWeather(date: reference.addingTimeInterval(Double(daysFromReference) * 86400), meanTempC: meanTempC, maxTempC: maxTempC, minTempC: minTempC, precipitationMm: precipitationMm, humidityPercent: humidityPercent)
    }

    // 2026-08-07 00:00:00 UTC — matches FlushTriggerDetectorTests' reference (that comment
    // is itself off by one year against the real epoch date, a pre-existing harmless slip;
    // only the month matters for these tests either way).
    private let today = Date(timeIntervalSince1970: 1_754_524_800)

    /// 19 days, -18...0, chronologically ascending: 9 pure-lookback days (-18...-10) plus
    /// 10 displayable days (-9...0) once SpeciesTrendCalculator's 10-day window requirement
    /// consumes the first 9. Mirrors SpeciesTrendState's real fetch (pastDays: 20, with margin).
    private func nineteenDayHistory(precipitationMm: Double = 1) -> [DailyWeather] {
        (-18...0).map { day(daysFromReference: $0, reference: today, precipitationMm: precipitationMm) }
    }

    func testTrendReturnsOnePointPerDisplayableDayNotPerInputDay() {
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: nineteenDayHistory(), regionId: "zilinsky", today: today)
        XCTAssertEqual(points.count, 10, "19 input days, first 9 consumed as pure rolling-window/flush-lookback context")
    }

    func testFewerThanTenDaysOfInputReturnsNoPoints() {
        let shortHistory = (-5...0).map { day(daysFromReference: $0, reference: today) }
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: shortHistory, regionId: "zilinsky", today: today)
        XCTAssertTrue(points.isEmpty, "fewer than 10 days can't form one complete rolling window — no point should be manufactured from a partial one")
    }

    func testOffSeasonDayScoresZero() {
        let outOfSeason = species(fruitingMonths: [1]) // January only; "today" is August
        let points = SpeciesTrendCalculator.trend(species: outOfSeason, dailyWeather: nineteenDayHistory(), regionId: "zilinsky", today: today)
        XCTAssertEqual(points.last?.score, 0, "the most recent displayed point (today) should score 0 out of season")
    }

    func testRollingPrecipitationSumMatchesTrailingTenDaysNotSingleDay() {
        // Every day has 1mm except one 15mm spike 3 days before "today." A single-day read
        // of "today" would see 1mm; the correct 10-day trailing SUM including the spike is
        // 15 + 9*1 = 24mm (high sensitivity: baseScore 1.0 at >=20mm). This is exactly the
        // bug the fix addresses.
        var days = nineteenDayHistory(precipitationMm: 1)
        days[days.count - 1 - 3] = day(daysFromReference: -3, reference: today, precipitationMm: 15)
        let highSensitivity = species(rainfallSensitivity: .high)
        let points = SpeciesTrendCalculator.trend(species: highSensitivity, dailyWeather: days, regionId: "zilinsky", today: today)
        // calendarScore 1.0 + tempScore 1.0 + humidityScore 1.0 + rainScore 1.0 (10-day sum
        // 24mm >= 20mm) = 4.0. A single-day read (1mm on "today") would instead give
        // rainScore 0.0 (< 8mm) => total 3.0 => score 3 — this assertion only passes under
        // the corrected rolling-sum behavior.
        XCTAssertEqual(points.last?.score, 4)
    }

    func testFlushTriggerAppliesToTheOldestDisplayedPointNotJustLaterOnes() {
        // The oldest displayed point is -9 days from today. Put a qualifying flush day at
        // -16 (7 days before -9, the very edge of that point's 2-7-day lookback window) —
        // only reachable if the fetch window includes lookback days before the display
        // window, which is exactly the left-edge-truncation bug this fix addresses.
        //
        // Baseline precipitation is 0.5mm/day, not 1mm/day: at 1mm/day the 10-day rolling
        // sum (10mm) alone already lands high-sensitivity rainfall in its 0.5 band, which
        // combined with the other three dimensions at 1.0 each totals 3.5 — and Swift's
        // `.rounded()` rounds 3.5 UP to 4, the same ceiling score the trigger case produces
        // (rainScore is capped at min(1.0, ...)). Both branches would silently round to the
        // same integer score and the assertion would falsely fail. At 0.5mm/day the baseline
        // rolling sum (5mm) stays under the 8mm band entirely, so the trigger's effect is
        // visible in the final integer score (3 -> 4) instead of being masked by rounding.
        var days = nineteenDayHistory(precipitationMm: 0.5)
        days[days.count - 1 - 16] = day(daysFromReference: -16, reference: today, maxTempC: 30, precipitationMm: 10)
        let highSensitivity = species(rainfallSensitivity: .high)

        let pointsWithTrigger = SpeciesTrendCalculator.trend(species: highSensitivity, dailyWeather: days, regionId: "zilinsky", today: today)
        let pointsWithoutTrigger = SpeciesTrendCalculator.trend(species: highSensitivity, dailyWeather: nineteenDayHistory(precipitationMm: 0.5), regionId: "zilinsky", today: today)

        XCTAssertGreaterThan(pointsWithTrigger.first?.score ?? 0, pointsWithoutTrigger.first?.score ?? 0, "the oldest displayed point (-9 days) must still see a flush day 7 days before it")
    }

    func testDayAfterTodayIsMarkedAsForecast() {
        var days = nineteenDayHistory()
        days.append(day(daysFromReference: 1, reference: today))
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: days, regionId: "zilinsky", today: today)
        XCTAssertEqual(points.last?.isForecast, true)
    }

    func testTodayItselfIsNotMarkedAsForecast() {
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: nineteenDayHistory(), regionId: "zilinsky", today: today)
        XCTAssertEqual(points.last?.isForecast, false)
    }

    func testUnsortedInputIsHandledCorrectly() {
        let shuffled = nineteenDayHistory().shuffled()
        let sorted = nineteenDayHistory()
        let pointsFromShuffled = SpeciesTrendCalculator.trend(species: species(), dailyWeather: shuffled, regionId: "zilinsky", today: today)
        let pointsFromSorted = SpeciesTrendCalculator.trend(species: species(), dailyWeather: sorted, regionId: "zilinsky", today: today)
        XCTAssertEqual(pointsFromShuffled, pointsFromSorted, "trend() must sort its input internally, not assume caller ordering")
    }
}
