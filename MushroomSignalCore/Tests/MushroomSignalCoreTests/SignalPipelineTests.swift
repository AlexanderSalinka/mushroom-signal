import XCTest
@testable import MushroomSignalCore

final class SignalPipelineTests: XCTestCase {
    private let warmWetWeather = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 16, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: .now)
    private let region = Region(id: "trenciansky", nameSk: "Trenčiansky kraj", latitude: 48.9, longitude: 18.0)

    private func species(id: String, name: String, edibility: Edibility = .edible, affinity: Set<String> = ["trenciansky"], months: Set<Int> = [6, 7, 8, 9]) -> Species {
        Species(id: id, commonNameSk: name, latinName: id, edibility: edibility, fruitingMonths: months, idealTempMinC: 10, idealTempMaxC: 20, idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90, rainfallSensitivity: .low, habitat: "test", regionalAffinity: affinity)
    }

    func testRegionOverloadFiltersByRegionalAffinity() {
        let inRegion = species(id: "a", name: "Alpha", affinity: ["trenciansky"])
        let outOfRegion = species(id: "b", name: "Beta", affinity: ["kosicky"])
        let ranked = SignalPipeline.rankedSignals(species: [inRegion, outOfRegion], region: region, weather: warmWetWeather, month: 7, flushTriggered: false)
        XCTAssertEqual(ranked.map { $0.species.id }, ["a"], "species without affinity for the region should be excluded, not scored")
    }

    func testRegionOverloadRespectsLimit() {
        let candidates = (0..<5).map { species(id: "\($0)", name: "Species\($0)") }
        let ranked = SignalPipeline.rankedSignals(species: candidates, region: region, weather: warmWetWeather, month: 7, flushTriggered: false, limit: 2)
        XCTAssertEqual(ranked.count, 2)
    }

    func testRegionOverloadDefaultsToAllMatchingCandidatesWhenLimitOmitted() {
        let candidates = (0..<5).map { species(id: "\($0)", name: "Species\($0)") }
        let ranked = SignalPipeline.rankedSignals(species: candidates, region: region, weather: warmWetWeather, month: 7, flushTriggered: false)
        XCTAssertEqual(ranked.count, 5)
    }

    func testCandidatesOverloadDoesNotFilterByRegion() {
        // The lower-level overload takes pre-filtered candidates directly (used by
        // DominantSpeciesResolver, whose "active species" list isn't region-derived).
        let candidate = species(id: "a", name: "Alpha", affinity: ["some-other-region"])
        let ranked = SignalPipeline.rankedSignals(candidates: [candidate], weather: warmWetWeather, month: 7, flushTriggered: false)
        XCTAssertEqual(ranked.map { $0.species.id }, ["a"])
    }

    func testFlushTriggeredIsPassedThroughToComputeSignal() {
        // high-sensitivity species, low rain (baseline 0.0), so the trigger bump is visible in the ranked order.
        let lowRainCandidate = species(id: "a", name: "Alpha", edibility: .edible)
        let weather = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 16, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 1, fetchedAt: .now)

        let withoutTrigger = SignalPipeline.rankedSignals(candidates: [lowRainCandidate], weather: weather, month: 7, flushTriggered: false)
        let withTrigger = SignalPipeline.rankedSignals(candidates: [lowRainCandidate], weather: weather, month: 7, flushTriggered: true)

        XCTAssertLessThan(withoutTrigger[0].score, withTrigger[0].score, "flushTriggered must actually reach computeSignal, not be silently dropped")
    }
}
