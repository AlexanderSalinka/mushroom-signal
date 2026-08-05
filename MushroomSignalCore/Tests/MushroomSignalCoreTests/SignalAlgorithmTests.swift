import XCTest
@testable import MushroomSignalCore

final class SignalAlgorithmTests: XCTestCase {
    private let sampleSpecies = Species(
        id: "boletus-edulis",
        commonNameSk: "Hríb smrekový",
        latinName: "Boletus edulis",
        edibility: .edible,
        lookAlikes: [],
        fruitingMonths: [6, 7, 8, 9, 10],
        idealTempMinC: 12,
        idealTempMaxC: 22,
        rainfallSensitivity: .high,
        habitat: "smrekové lesy",
        regionalAffinity: ["zilinsky"]
    )

    func testPeakSeasonWithGoodTempAndRainScoresThree() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8)

        XCTAssertEqual(signal.score, 3)
        XCTAssertNil(signal.reason)
    }

    func testOffSeasonScoresZeroRegardlessOfWeather() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        // January: not in fruitingMonths, not adjacent to them either.
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 1)

        XCTAssertEqual(signal.score, 0)
        XCTAssertEqual(signal.reason, "mimo hlavnej sezóny")
    }

    func testDrySpellPenalizesHighRainfallSensitivitySpecies() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, totalPrecipitationLast10DaysMm: 1, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8)

        XCTAssertEqual(signal.score, 2)
        XCTAssertEqual(signal.reason, "málo zrážok v poslednej dobe")
    }

    func testShoulderMonthCapsScoreEvenWithGoodWeather() {
        // 24°C is 2°C above idealTempMaxC (22) — within the 3°C tolerance band, so partial temp credit.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 24, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        // Month 11 is adjacent to fruitingMonths' last month (10) but not itself in season.
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 11)

        XCTAssertEqual(signal.score, 2)
        XCTAssertEqual(signal.reason, "teplota mimo ideálneho rozsahu")
    }

    func testLowRainfallSensitivitySpeciesIsNotPenalizedByDrySpell() {
        let lowSensitivitySpecies = Species(
            id: "pleurotus-ostreatus",
            commonNameSk: "Hliva ustricovitá",
            latinName: "Pleurotus ostreatus",
            edibility: .edible,
            lookAlikes: [],
            fruitingMonths: [9, 10, 11],
            idealTempMinC: 2,
            idealTempMaxC: 15,
            rainfallSensitivity: .low,
            habitat: "odumreté stromy",
            regionalAffinity: ["zilinsky"]
        )
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 10, totalPrecipitationLast10DaysMm: 0, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: weather, month: 10)

        XCTAssertEqual(signal.score, 3)
        XCTAssertNil(signal.reason)
    }
}
