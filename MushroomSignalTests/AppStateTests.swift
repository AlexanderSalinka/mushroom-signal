import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class AppStateTests: XCTestCase {
    func testRefreshClearsStaleSignalsOnFailureAfterASuccessfulLoad() async {
        let region = RegionDatabase.all[0]
        let snapshot = WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
        let client = StubWeatherClient(snapshots: [snapshot, nil])
        let appState = AppState(store: nil, weatherClient: client)

        await appState.refresh()
        XCTAssertFalse(appState.signals.isEmpty, "precondition: first refresh should have loaded signals")

        await appState.refresh()

        XCTAssertTrue(appState.signals.isEmpty, "a failed refresh must clear the previous region's stale signals")
        XCTAssertNotNil(appState.errorMessage)
    }

    func testOverlappingRefreshesApplyLastStartedWinsOrdering() async {
        let client = DelayedWeatherClient()
        let appState = AppState(store: nil, weatherClient: client)

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
        let appState = AppState(store: nil, weatherClient: StubWeatherClient(snapshots: [nil]), widgetReloader: reloader)

        appState.selectRegion(RegionDatabase.all[1])
        await fulfillment(of: [reloadedExpectation], timeout: 2)

        let count = await reloader.reloadCount
        XCTAssertEqual(count, 1, "selecting a new region must trigger an immediate widget timeline reload, not wait for the next scheduled 12h refresh")
    }
}
