import XCTest
@testable import MushroomSignal
import MushroomSignalCore

/// A per-region stub that can delay one region's response independently of another's — needed
/// to prove the generation-token guard actually discards a late-arriving stale result, which
/// the shared `StubWeatherClient` can't exercise (it ignores the region and returns one fixed
/// array for every call, so a "stale" and a "fresh" load are indistinguishable through it).
private actor OrderedRegionStub: WeatherClient {
    struct StubError: Error, Sendable {}
    private let dataByRegionID: [String: [DailyWeather]]
    private let delayByRegionID: [String: Duration]

    init(dataByRegionID: [String: [DailyWeather]], delayByRegionID: [String: Duration] = [:]) {
        self.dataByRegionID = dataByRegionID
        self.delayByRegionID = delayByRegionID
    }

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot { throw StubError() }
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] { [:] }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        if let delay = delayByRegionID[region.id] {
            try? await Task.sleep(for: delay)
        }
        return dataByRegionID[region.id] ?? []
    }
}

@MainActor
final class RegionWeatherStateTests: XCTestCase {
    func testLoadPopulatesDailyWeatherOnSuccess() async {
        let day = DailyWeather(date: .now, meanTempC: 15, maxTempC: 20, minTempC: 10, precipitationMm: 5, humidityPercent: 70)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [day])
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")

        XCTAssertEqual(state.dailyWeather.count, 1)
        XCTAssertNil(state.errorMessage)
    }

    func testLoadClearsDailyWeatherAndSetsErrorOnFailure() async {
        let client = StubWeatherClient(snapshots: [nil], dailyShouldThrow: true)
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")

        XCTAssertTrue(state.dailyWeather.isEmpty)
        XCTAssertNotNil(state.errorMessage)
    }

    func testLoadWithUnknownRegionIdLeavesExistingDataUntouched() async {
        let day = DailyWeather(date: .now, meanTempC: 12, maxTempC: 18, minTempC: 6, precipitationMm: 2, humidityPercent: 60)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [day])
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")
        XCTAssertEqual(state.dailyWeather.count, 1)

        await state.load(regionId: "not-a-real-region")

        XCTAssertEqual(state.dailyWeather.count, 1, "an unknown region id must not clear data left over from a previously successful load")
    }

    func testStaleLoadDoesNotOverwriteNewerData() async {
        let staleDay = DailyWeather(date: .now, meanTempC: 5, maxTempC: 8, minTempC: 2, precipitationMm: 0, humidityPercent: 40)
        let freshDay = DailyWeather(date: .now, meanTempC: 20, maxTempC: 25, minTempC: 15, precipitationMm: 1, humidityPercent: 55)
        // zilinsky's response is deliberately delayed so it lands AFTER kosicky's, even
        // though zilinsky's load starts first — simulates a fast region switch where the
        // first (now-stale) request's network response arrives last. Without the
        // generation-token guard, this stale response would overwrite kosicky's already-
        // current data.
        let client = OrderedRegionStub(
            dataByRegionID: ["zilinsky": [staleDay], "kosicky": [freshDay]],
            delayByRegionID: ["zilinsky": .milliseconds(50)]
        )
        let state = RegionWeatherState(weatherClient: client)

        async let first: Void = state.load(regionId: "zilinsky")
        async let second: Void = state.load(regionId: "kosicky")
        _ = await (first, second)

        XCTAssertEqual(state.dailyWeather, [freshDay], "the stale zilinsky load must not overwrite kosicky's already-current data, even though it finishes later")
    }

    func testLoadingANewRegionReplacesRatherThanAppendsPreviousData() async {
        let day = DailyWeather(date: .now, meanTempC: 10, maxTempC: 15, minTempC: 5, precipitationMm: 0, humidityPercent: 50)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [day])
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")
        XCTAssertEqual(state.dailyWeather.count, 1)

        await state.load(regionId: "kosicky")
        XCTAssertEqual(state.dailyWeather.count, 1, "still one day from the same stub client — proves load() replaces rather than appends")
    }
}
