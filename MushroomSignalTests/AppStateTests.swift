import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class AppStateTests: XCTestCase {
    func testRefreshFallsBackToCachedWeatherOnFailureAfterASuccessfulLoad() async {
        let region = RegionDatabase.all[0]
        let snapshot = WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
        let client = StubWeatherClient(snapshots: [snapshot, nil])
        let suiteName = "test.suite.\(UUID().uuidString)"
        let cache = WeatherSnapshotCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let appState = AppState(store: nil, weatherCache: cache, weatherClient: client)

        await appState.refresh()
        XCTAssertFalse(appState.signals.isEmpty, "precondition: first refresh should have loaded signals")

        await appState.refresh()

        XCTAssertFalse(appState.signals.isEmpty, "a failed refresh must fall back to the cached snapshot instead of blanking the list")
        XCTAssertTrue(appState.isShowingStaleData, "the fallback must be flagged as stale so the UI can indicate it, not present it as fresh")
        XCTAssertNotNil(appState.errorMessage)
    }

    func testRefreshClearsSignalsOnFailureWhenNoCachedSnapshotExists() async {
        let client = StubWeatherClient(snapshots: [nil])
        let suiteName = "test.suite.\(UUID().uuidString)"
        let cache = WeatherSnapshotCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let appState = AppState(store: nil, weatherCache: cache, weatherClient: client)

        await appState.refresh()

        XCTAssertTrue(appState.signals.isEmpty, "with nothing cached yet, a failed refresh has nothing to fall back to")
        XCTAssertFalse(appState.isShowingStaleData)
        XCTAssertNotNil(appState.errorMessage)
    }

    func testOverlappingRefreshesApplyLastStartedWinsOrdering() async {
        let client = DelayedWeatherClient()
        let appState = AppState(store: nil, weatherCache: nil, weatherClient: client)

        async let first: Void = appState.refresh()
        try? await Task.sleep(for: .milliseconds(20))
        async let second: Void = appState.refresh()
        _ = await (first, second)

        XCTAssertNil(appState.errorMessage, "the second (later-started, faster) refresh succeeded and must not be overwritten when the slower first call fails after it")
        XCTAssertFalse(appState.signals.isEmpty)
    }

    func testSelectRegionReloadsWidgetTimelines() async {
        let reloadedExpectation = XCTestExpectation(description: "widget timelines reloaded")
        let reloader = SpyWidgetReloader(expectation: reloadedExpectation)
        let appState = AppState(store: nil, weatherCache: nil, weatherClient: StubWeatherClient(snapshots: [nil]), widgetReloader: reloader)

        appState.selectRegion(RegionDatabase.all[1])
        await fulfillment(of: [reloadedExpectation], timeout: 2)

        let count = await reloader.reloadCount
        XCTAssertEqual(count, 1, "selecting a new region must trigger an immediate widget timeline reload, not wait for the next scheduled 12h refresh")
    }
}
