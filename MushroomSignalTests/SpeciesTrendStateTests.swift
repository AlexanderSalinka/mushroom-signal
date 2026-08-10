import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class SpeciesTrendStateTests: XCTestCase {
    private func species() -> Species {
        Species(id: "test", commonNameSk: "Test", latinName: "Testus", edibility: .edible, fruitingMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], idealTempMinC: 0, idealTempMaxC: 40, idealHumidityMinPercent: 0, idealHumidityMaxPercent: 100, rainfallSensitivity: .low, habitat: "test", regionalAffinity: [])
    }

    func testLoadPopulatesPointsOnSuccess() async {
        let day = DailyWeather(date: .now, meanTempC: 15, maxTempC: 20, minTempC: 10, precipitationMm: 5, humidityPercent: 70)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [day])
        let state = SpeciesTrendState(weatherClient: client)

        await state.load(species: species(), regionId: "zilinsky")

        XCTAssertEqual(state.points.count, 1)
        XCTAssertNil(state.errorMessage)
    }

    func testLoadClearsPointsAndSetsErrorOnFailure() async {
        let client = StubWeatherClient(snapshots: [nil], dailyShouldThrow: true)
        let state = SpeciesTrendState(weatherClient: client)

        await state.load(species: species(), regionId: "zilinsky")

        XCTAssertTrue(state.points.isEmpty)
        XCTAssertNotNil(state.errorMessage)
    }

    func testLoadWithUnknownRegionIdLeavesPointsEmpty() async {
        let client = StubWeatherClient(snapshots: [nil])
        let state = SpeciesTrendState(weatherClient: client)

        await state.load(species: species(), regionId: "not-a-real-region")

        XCTAssertTrue(state.points.isEmpty)
    }
}
