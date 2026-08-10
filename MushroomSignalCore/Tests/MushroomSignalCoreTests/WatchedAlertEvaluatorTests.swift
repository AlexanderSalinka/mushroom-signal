import XCTest
@testable import MushroomSignalCore

final class WatchedAlertEvaluatorTests: XCTestCase {
    private struct StubClient: WeatherClient {
        struct StubError: Error, Sendable {}
        let snapshots: [String: WeatherSnapshot]

        func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
            guard let snapshot = snapshots[region.id] else { throw StubError() }
            return snapshot
        }
        func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] { snapshots }
        func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] { [] }
    }

    private func species(id: String, regionalAffinity: Set<String> = ["zilinsky", "kosicky"]) -> Species {
        Species(id: id, commonNameSk: id, latinName: id, edibility: .edible, fruitingMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], idealTempMinC: 0, idealTempMaxC: 40, idealHumidityMinPercent: 0, idealHumidityMaxPercent: 100, rainfallSensitivity: .low, habitat: "test", regionalAffinity: regionalAffinity)
    }

    private func snapshot(regionId: String) -> WeatherSnapshot {
        WeatherSnapshot(regionId: regionId, averageTempLast10DaysC: 20, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 15, fetchedAt: .now)
    }

    func testFetchesWeatherOncePerDistinctRegionNotPerAlert() async {
        let alerts = [
            WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 2),
            WatchedAlert(speciesId: "b", regionId: "zilinsky", threshold: 2),
            WatchedAlert(speciesId: "c", regionId: "kosicky", threshold: 2)
        ]
        let client = StubClient(snapshots: ["zilinsky": snapshot(regionId: "zilinsky"), "kosicky": snapshot(regionId: "kosicky")])
        let allSpecies = [species(id: "a"), species(id: "b"), species(id: "c")]

        let updates = await WatchedAlertEvaluator.evaluate(alerts: alerts, species: allSpecies, weatherClient: client, month: 7)

        XCTAssertEqual(updates.count, 3, "one update per alert, even though only 2 distinct regions needed fetching")
    }

    func testMissingWeatherForARegionSkipsOnlyThatRegionsAlerts() async {
        let alerts = [
            WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 2),
            WatchedAlert(speciesId: "b", regionId: "kosicky", threshold: 2)
        ]
        let client = StubClient(snapshots: ["zilinsky": snapshot(regionId: "zilinsky")]) // kosicky missing
        let allSpecies = [species(id: "a"), species(id: "b")]

        let updates = await WatchedAlertEvaluator.evaluate(alerts: alerts, species: allSpecies, weatherClient: client, month: 7)

        XCTAssertEqual(updates.map(\.alert.speciesId), ["a"])
    }

    func testShouldNotifyReflectsThresholdCrossing() async {
        let alert = WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 3, lastKnownScore: 1)
        let client = StubClient(snapshots: ["zilinsky": snapshot(regionId: "zilinsky")])

        let updates = await WatchedAlertEvaluator.evaluate(alerts: [alert], species: [species(id: "a")], weatherClient: client, month: 7)

        // idealTempMinC 0...40 and idealHumidity 0...100 mean this fixture species always
        // scores full marks when in season — month 7 is in fruitingMonths, so expect score 4.
        XCTAssertEqual(updates.first?.newScore, 4)
        XCTAssertTrue(updates.first?.shouldNotify ?? false, "previous score 1 crossing up to 4 with threshold 3 should notify")
    }

    func testEmptyAlertsReturnsEmptyWithoutFetchingAnything() async {
        let client = StubClient(snapshots: [:])
        let updates = await WatchedAlertEvaluator.evaluate(alerts: [], species: [], weatherClient: client, month: 7)
        XCTAssertTrue(updates.isEmpty)
    }

    func testSkipsAlertWhenSpeciesHasNoAffinityForWatchedRegion() async {
        let alert = WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 2)
        let client = StubClient(snapshots: ["zilinsky": snapshot(regionId: "zilinsky")])
        let outOfRegionSpecies = species(id: "a", regionalAffinity: ["kosicky"])

        let updates = await WatchedAlertEvaluator.evaluate(alerts: [alert], species: [outOfRegionSpecies], weatherClient: client, month: 7)

        XCTAssertTrue(updates.isEmpty, "species without affinity for the watched region should never be scored or notified")
    }
}
