import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class AppStateTests: XCTestCase {
    func testRefreshFallsBackToCachedWeatherOnFailureAfterASuccessfulLoad() async {
        let region = RegionDatabase.all[0]
        let day = DailyWeather(date: .now, meanTempC: 15, maxTempC: 20, minTempC: 10, precipitationMm: 5, humidityPercent: 75)
        let client = StubWeatherClient(snapshots: [nil], dailyWeatherSequence: [[day], nil])
        let suiteName = "test.suite.\(UUID().uuidString)"
        let weatherCache = WeatherSnapshotCache(appGroupId: suiteName)!
        let dailyCache = DailyWeatherCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let appState = AppState(store: nil, weatherCache: weatherCache, dailyWeatherCache: dailyCache, weatherClient: client)

        await appState.refresh()
        XCTAssertFalse(appState.signals.isEmpty, "precondition: first refresh should have loaded signals")
        XCTAssertEqual(appState.dailyWeather, [day], "a successful refresh must publish the fetched daily array, not just signals")

        await appState.refresh()

        XCTAssertFalse(appState.signals.isEmpty, "a failed refresh must fall back to the cached snapshot instead of blanking the list")
        XCTAssertFalse(appState.dailyWeather.isEmpty, "the daily array must also fall back to its cache, not just signals")
        XCTAssertTrue(appState.isShowingStaleData, "the fallback must be flagged as stale so the UI can indicate it, not present it as fresh")
        XCTAssertNotNil(appState.errorMessage)
    }

    func testRefreshClearsSignalsOnFailureWhenNoCachedSnapshotExists() async {
        let client = StubWeatherClient(snapshots: [nil], dailyWeatherSequence: [nil])
        let suiteName = "test.suite.\(UUID().uuidString)"
        let weatherCache = WeatherSnapshotCache(appGroupId: suiteName)!
        let dailyCache = DailyWeatherCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let appState = AppState(store: nil, weatherCache: weatherCache, dailyWeatherCache: dailyCache, weatherClient: client)

        await appState.refresh()

        XCTAssertTrue(appState.signals.isEmpty, "with nothing cached yet, a failed refresh has nothing to fall back to")
        XCTAssertTrue(appState.dailyWeather.isEmpty)
        XCTAssertFalse(appState.isShowingStaleData)
        XCTAssertNotNil(appState.errorMessage)
    }

    func testOverlappingRefreshesApplyLastStartedWinsOrdering() async {
        let client = DelayedWeatherClient()
        let appState = AppState(store: nil, weatherCache: nil, dailyWeatherCache: nil, weatherClient: client)

        async let first: Void = appState.refresh()
        try? await Task.sleep(for: .milliseconds(20))
        async let second: Void = appState.refresh()
        _ = await (first, second)

        XCTAssertNil(appState.errorMessage, "the second (later-started, faster) refresh succeeded and must not be overwritten when the slower first call fails after it")
        XCTAssertFalse(appState.signals.isEmpty)
    }

    func testOverlappingRefreshesDiscardLateArrivingSuccessFromEarlierStartedRefresh() async {
        let client = ReversedOrderWeatherClient()
        let appState = AppState(store: nil, weatherCache: nil, dailyWeatherCache: nil, weatherClient: client)

        async let first: Void = appState.refresh()
        try? await Task.sleep(for: .milliseconds(20))
        async let second: Void = appState.refresh()
        _ = await (first, second)

        XCTAssertEqual(appState.dailyWeather.first?.precipitationMm, 99, "the later-started refresh's success must win even though the earlier-started refresh's success arrives after it")
    }

    func testSelectRegionReloadsWidgetTimelines() async {
        let reloadedExpectation = XCTestExpectation(description: "widget timelines reloaded")
        let reloader = SpyWidgetReloader(expectation: reloadedExpectation)
        let appState = AppState(store: nil, weatherCache: nil, dailyWeatherCache: nil, weatherClient: StubWeatherClient(snapshots: [nil]), widgetReloader: reloader)

        appState.selectRegion(RegionDatabase.all[1])
        await fulfillment(of: [reloadedExpectation], timeout: 2)

        let count = await reloader.reloadCount
        XCTAssertEqual(count, 1, "selecting a new region must trigger an immediate widget timeline reload, not wait for the next scheduled 12h refresh")
    }

    func testRefreshAppliesFlushTriggerFromDailyBreakdown() async {
        // Pinned to August so this test doesn't depend on the real current month: in
        // January/February the only in-season real species is pleurotus-ostreatus, which is
        // .low rainfall sensitivity and can structurally never show the trigger reason.
        let fixedDate = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 15))!

        struct TriggeringWeatherClient: WeatherClient {
            struct StubError: Error, Sendable {}
            let referenceDate: Date
            func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
                // Never called: AppState.refresh() derives its snapshot from fetchDailyBreakdown
                // (post weather-fetch-consolidation, Task 4). Throws so a future accidental call
                // fails loudly instead of silently succeeding with numbers this test doesn't use.
                throw StubError()
            }
            func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] { [:] }
            func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
                // 3 days before the injected "now" so it always lands inside the detector's
                // 2-7 day lag window, regardless of when the test actually runs.
                [DailyWeather(date: referenceDate.addingTimeInterval(-3 * 86400), meanTempC: 22, maxTempC: 27, minTempC: 17, precipitationMm: 5, humidityPercent: 70)]
            }
        }

        let appState = AppState(store: nil, weatherCache: nil, dailyWeatherCache: nil, weatherClient: TriggeringWeatherClient(referenceDate: fixedDate), now: { fixedDate })
        await appState.refresh()

        XCTAssertFalse(appState.signals.isEmpty, "precondition: some species should be in season and scoring")
        XCTAssertTrue(appState.signals.contains { $0.reason == "nedávno teplo a dážď — čoskoro môže prísť nová vlna" }, "a high/medium rainfall-sensitivity species in low-rain conditions should show the trigger reason once a qualifying day is in the daily breakdown")
    }

    func testRefreshRequestsThirtyDaysOfHistoryAndFiveDayForecast() async {
        let client = RecordingWeatherClient()
        let appState = AppState(store: nil, weatherCache: nil, dailyWeatherCache: nil, weatherClient: client)

        await appState.refresh()

        let pastDays = await client.capturedPastDays
        let forecastDays = await client.capturedForecastDays
        XCTAssertEqual(pastDays, 30, "WeatherRainChartView's 30-day range toggle depends on the full 30-day history already being fetched")
        XCTAssertEqual(forecastDays, 5, "the forecast strip depends on a 5-day-ahead fetch")
    }
}
