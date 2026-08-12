import XCTest
@testable import MushroomSignalCore

final class MushroomSignalHeroStateTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private let sampleSpecies = Species(
        id: "boletus-edulis",
        commonNameSk: "Hríb smrekový",
        latinName: "Boletus edulis",
        edibility: .edible,
        lookAlikes: [],
        fruitingMonths: [6, 7, 8, 9, 10],
        idealTempMinC: 12,
        idealTempMaxC: 22,
        idealHumidityMinPercent: 60,
        idealHumidityMaxPercent: 90,
        rainfallSensitivity: .high,
        habitat: "smrekové lesy",
        regionalAffinity: ["zilinsky"]
    )

    private func signal(score: Int, flushTriggered: Bool) -> SpeciesSignal {
        SpeciesSignal(species: sampleSpecies, score: score, reason: nil, flushTriggered: flushTriggered)
    }

    private func daysFromNow(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, minTempC: maxTempC - 10, precipitationMm: precipitationMm, humidityPercent: 70)
    }

    func testFlushHappeningRequiresBothTriggerAndMaxedScore() {
        let signals = [signal(score: 4, flushTriggered: true)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: [], asOf: today)
        XCTAssertEqual(result, .flushHappening)
    }

    func testTriggeredWithoutAnyMaxedScoreIsNotFlushHappening() {
        let signals = [signal(score: 3, flushTriggered: true)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: [], asOf: today)
        XCTAssertEqual(result, .noRain)
    }

    func testMaxedScoreWithoutTriggerIsNotFlushHappening() {
        let signals = [signal(score: 4, flushTriggered: false)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: [], asOf: today)
        XCTAssertEqual(result, .noRain)
    }

    func testFlushHappeningWinsOverRainIncomingOnTheSameDay() {
        let signals = [signal(score: 4, flushTriggered: true)]
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: days, asOf: today)
        XCTAssertEqual(result, .flushHappening)
    }

    func testRainIncomingWhenNoFlushButForecastQualifies() {
        let signals = [signal(score: 2, flushTriggered: false)]
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: days, asOf: today)
        guard case .rainIncoming(let event) = result else {
            return XCTFail("expected rainIncoming, got \(result)")
        }
        XCTAssertEqual(event.precipitationMm, 11.0)
    }

    func testNearMissWhenNoFlushAndNoFullRainEvent() {
        let signals = [signal(score: 1, flushTriggered: false)]
        let days = [daysFromNow(2, maxTempC: 29.0, precipitationMm: 0.0)] // heat without rain
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: days, asOf: today)
        XCTAssertEqual(result, .nearMiss(.heatWithoutRain(date: days[0].date, precipitationMm: 0.0, maxTempC: 29.0)))
    }

    func testNoRainWhenEverythingIsFlat() {
        let signals = [signal(score: 1, flushTriggered: false)]
        let days = [daysFromNow(1, maxTempC: 18.0, precipitationMm: 0.0)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: days, asOf: today)
        XCTAssertEqual(result, .noRain)
    }

    func testEmptySignalsAndEmptyWeatherResolvesToNoRain() {
        let result = MushroomSignalHeroState.resolve(signals: [], dailyWeather: [], asOf: today)
        XCTAssertEqual(result, .noRain)
    }
}
