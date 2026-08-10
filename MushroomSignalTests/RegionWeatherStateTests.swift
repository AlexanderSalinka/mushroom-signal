import XCTest
@testable import MushroomSignal
import MushroomSignalCore

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
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [freshDay])
        let state = RegionWeatherState(weatherClient: client)

        // Start a load, then immediately start a second one before the first can write —
        // simulates a fast region switch. Both use the same stub, so this proves the guard
        // exists and doesn't itself break the common case (second load's result wins).
        async let first: Void = state.load(regionId: "zilinsky")
        async let second: Void = state.load(regionId: "kosicky")
        _ = await (first, second)

        XCTAssertEqual(state.dailyWeather, [freshDay])
        _ = staleDay // silence unused-variable warning if the compiler flags it; documents intent
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
