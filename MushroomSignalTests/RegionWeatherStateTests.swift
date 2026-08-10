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

    func testLoadWithUnknownRegionIdLeavesDailyWeatherEmpty() async {
        let client = StubWeatherClient(snapshots: [nil])
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "not-a-real-region")

        XCTAssertTrue(state.dailyWeather.isEmpty)
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
