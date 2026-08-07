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
        idealHumidityMinPercent: 60,
        idealHumidityMaxPercent: 90,
        rainfallSensitivity: .high,
        habitat: "smrekové lesy",
        regionalAffinity: ["zilinsky"]
    )

    func testPeakSeasonWithGoodTempHumidityAndRainScoresFour() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)

        XCTAssertEqual(signal.score, 4)
        XCTAssertNil(signal.reason)
    }

    func testOffSeasonScoresZeroRegardlessOfWeather() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        // January: not in fruitingMonths, not adjacent to them either.
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 1, flushTriggered: false)

        XCTAssertEqual(signal.score, 0)
        XCTAssertEqual(signal.reason, "mimo hlavnej sezóny")
    }

    func testOffSeasonScoresZeroEvenWithFlushTriggered() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 1, flushTriggered: true)

        XCTAssertEqual(signal.score, 0, "the out-of-season hard gate must override the flush trigger too — see spec §1's one exception to equal weighting")
    }

    func testDrySpellPenalizesHighRainfallSensitivitySpecies() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 1, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)

        XCTAssertEqual(signal.score, 3)
        XCTAssertEqual(signal.reason, "málo zrážok v poslednej dobe")
    }

    func testShoulderMonthContributesPartialCalendarScoreUnderEqualWeighting() {
        // 24°C is 2°C above idealTempMaxC (22) — within the 3°C tolerance band, so partial temp credit.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 24, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        // Month 11 is adjacent to fruitingMonths' last month (10) but not itself in season.
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 11, flushTriggered: false)

        // calendar 0.5 + temp 0.5 + humidity 1.0 + rain 1.0 = 3.0
        XCTAssertEqual(signal.score, 3)
        XCTAssertEqual(signal.reason, "teplota mimo ideálneho rozsahu")
    }

    func testHumidityOutOfRangeReducesScoreAndSetsReason() {
        // 30% humidity is far below idealHumidityMinPercent (60) — outside the 10-point tolerance.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 30, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)

        // calendar 1.0 + temp 1.0 + humidity 0.0 + rain 1.0 = 3.0
        XCTAssertEqual(signal.score, 3)
        XCTAssertEqual(signal.reason, "vlhkosť mimo ideálneho rozsahu")
    }

    func testHumidityWithinToleranceBandGetsPartialCredit() {
        // 95% humidity is 5 points above idealHumidityMaxPercent (90) — within the 10-point tolerance.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 95, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)

        // calendar 1.0 + temp 1.0 + humidity 0.5 + rain 1.0 = 3.5, rounds to 4
        XCTAssertEqual(signal.score, 4)
    }

    func testFlushTriggerBumpsRainfallScoreForHighSensitivitySpecies() {
        // temp 25 is 3°C above idealTempMaxC (22) — exactly at the tolerance boundary, partial credit.
        // precipitation 10mm with .high sensitivity is >=8 but <20 — partial baseline rain credit (0.5).
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 25, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: Date())

        let withoutTrigger = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)
        let withTrigger = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: true)

        // withoutTrigger: calendar 1.0 + temp 0.5 + humidity 1.0 + rain 0.5 = 3.0
        XCTAssertEqual(withoutTrigger.score, 3)
        XCTAssertEqual(withoutTrigger.reason, "málo zrážok v poslednej dobe")

        // withTrigger: rain bumped by 1.0 (high sensitivity), capped at 1.0 -> calendar 1.0 + temp 0.5 + humidity 1.0 + rain 1.0 = 3.5, rounds to 4
        XCTAssertEqual(withTrigger.score, 4)
        XCTAssertEqual(withTrigger.reason, "nedávno teplo a dážď — čoskoro môže prísť nová vlna")
    }

    func testFlushTriggerDoesNotAffectLowSensitivitySpecies() {
        let lowSensitivitySpecies = Species(
            id: "pleurotus-ostreatus",
            commonNameSk: "Hliva ustricovitá",
            latinName: "Pleurotus ostreatus",
            edibility: .edible,
            lookAlikes: [],
            fruitingMonths: [9, 10, 11],
            idealTempMinC: 2,
            idealTempMaxC: 15,
            idealHumidityMinPercent: 70,
            idealHumidityMaxPercent: 95,
            rainfallSensitivity: .low,
            habitat: "odumreté stromy",
            regionalAffinity: ["zilinsky"]
        )
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 10, averageHumidityLast10DaysPercent: 80, totalPrecipitationLast10DaysMm: 0, fetchedAt: Date())

        let withoutTrigger = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: weather, month: 10, flushTriggered: false)
        let withTrigger = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: weather, month: 10, flushTriggered: true)

        XCTAssertEqual(withoutTrigger.score, 4)
        XCTAssertEqual(withTrigger.score, 4)
        XCTAssertEqual(withoutTrigger.score, withTrigger.score, "low rainfall sensitivity gets no trigger bonus, since it never needed rain to score well")
    }

    func testLowRainfallSensitivitySpeciesScoreIsInvariantToRainfallWithPartialTempMatch() {
        let lowSensitivitySpecies = Species(
            id: "pleurotus-ostreatus",
            commonNameSk: "Hliva ustricovitá",
            latinName: "Pleurotus ostreatus",
            edibility: .edible,
            lookAlikes: [],
            fruitingMonths: [9, 10, 11],
            idealTempMinC: 2,
            idealTempMaxC: 15,
            idealHumidityMinPercent: 70,
            idealHumidityMaxPercent: 95,
            rainfallSensitivity: .low,
            habitat: "odumreté stromy",
            regionalAffinity: ["zilinsky"]
        )
        // 17°C is 2°C above idealTempMaxC (15) — within the 3°C tolerance band, so partial temp credit.
        let dryWeather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 80, totalPrecipitationLast10DaysMm: 0, fetchedAt: Date())
        let wetWeather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 80, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let drySignal = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: dryWeather, month: 10, flushTriggered: false)
        let wetSignal = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: wetWeather, month: 10, flushTriggered: false)

        XCTAssertEqual(drySignal.score, wetSignal.score, "low-sensitivity species score must not depend on rainfall")
        XCTAssertEqual(drySignal.score, 4)
        XCTAssertEqual(wetSignal.score, 4)
        XCTAssertEqual(drySignal.reason, "teplota mimo ideálneho rozsahu")
        XCTAssertEqual(wetSignal.reason, "teplota mimo ideálneho rozsahu")
    }

    func testScoreNeverExceedsFour() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: true)
        XCTAssertLessThanOrEqual(signal.score, 4)
    }

    func testRainfallBonusCapsAtOnePointZeroBelowTheOuterScoreClamp() {
        // Isolates the inner `min(1.0, baseScore + bonus)` cap in rainfallFit from the outer
        // 0-4 score clamp in computeSignal, which would otherwise mask a missing inner cap.
        // temp 30°C is 8°C above idealTempMaxC (22) — outside the 3°C tolerance band, so tempScore = 0.0.
        // humidity 40% is 20 points below idealHumidityMinPercent (60) — outside the 10-point tolerance, so humidityScore = 0.0.
        // precipitation 25mm with .high sensitivity is >=20 — baseScore = 1.0 before any bonus.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 30, averageHumidityLast10DaysPercent: 40, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: true)

        // calendar 1.0 + temp 0.0 + humidity 0.0 + rain capped-at-1.0 = 2.0
        // Without the cap, rain would be baseScore 1.0 + bonus 1.0 = 2.0, giving a total of
        // 3.0 (score 3) — still within the 0-4 clamp's range, so this genuinely distinguishes
        // capped from uncapped behavior instead of being hidden by it.
        XCTAssertEqual(signal.score, 2)
        XCTAssertEqual(signal.reason, "nedávno teplo a dážď — čoskoro môže prísť nová vlna")
    }

    func testMediumRainfallSensitivityScoresPartialCreditAndRespondsToFlushTrigger() {
        let mediumSensitivitySpecies = Species(
            id: "cantharellus-cibarius",
            commonNameSk: "Líška obyčajná",
            latinName: "Cantharellus cibarius",
            edibility: .edible,
            lookAlikes: [],
            fruitingMonths: [6, 7, 8, 9, 10],
            idealTempMinC: 10,
            idealTempMaxC: 20,
            idealHumidityMinPercent: 65,
            idealHumidityMaxPercent: 85,
            rainfallSensitivity: .medium,
            habitat: "listnaté lesy",
            regionalAffinity: ["zilinsky"]
        )
        // temp 23°C is 3°C above idealTempMaxC (20) — exactly at the tolerance boundary, partial credit (tempScore = 0.5).
        // humidity 75% is within [65, 85] — full credit (humidityScore = 1.0).
        // precipitation 5mm with .medium sensitivity is >=3 but <10 — partial baseline rain credit (baseScore = 0.5).
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 23, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 5, fetchedAt: Date())

        let withoutTrigger = SignalAlgorithm.computeSignal(species: mediumSensitivitySpecies, weather: weather, month: 8, flushTriggered: false)
        let withTrigger = SignalAlgorithm.computeSignal(species: mediumSensitivitySpecies, weather: weather, month: 8, flushTriggered: true)

        // withoutTrigger: calendar 1.0 + temp 0.5 + humidity 1.0 + rain 0.5 = 3.0
        XCTAssertEqual(withoutTrigger.score, 3)
        XCTAssertEqual(withoutTrigger.reason, "málo zrážok v poslednej dobe")

        // withTrigger: rain bumped by 0.5 (medium sensitivity) -> 0.5 + 0.5 = 1.0 -> calendar 1.0 + temp 0.5 + humidity 1.0 + rain 1.0 = 3.5, rounds to 4
        XCTAssertEqual(withTrigger.score, 4)
        XCTAssertEqual(withTrigger.reason, "nedávno teplo a dážď — čoskoro môže prísť nová vlna")
    }
}
