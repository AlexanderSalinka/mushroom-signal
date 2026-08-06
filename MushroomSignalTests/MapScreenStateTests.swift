import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class MapScreenStateTests: XCTestCase {
    func testLoadGridPopulatesSnapshotsOnSuccess() async {
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let client = StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot])
        let state = MapScreenState(weatherClient: client)

        await state.loadGrid()

        XCTAssertEqual(state.snapshots["grid-00"], snapshot)
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isLoading)
    }

    func testLoadGridSetsErrorMessageOnFailure() async {
        let client = StubWeatherClient(snapshots: [nil], gridShouldThrow: true)
        let state = MapScreenState(weatherClient: client)

        await state.loadGrid()

        XCTAssertTrue(state.snapshots.isEmpty)
        XCTAssertNotNil(state.errorMessage)
    }

    func testToggleSpeciesTracksOnOffOrder() {
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil]))
        XCTAssertFalse(state.isActive("boletus-edulis"))

        state.toggleSpecies("boletus-edulis")
        XCTAssertTrue(state.isActive("boletus-edulis"))
        XCTAssertEqual(state.activeSpeciesOrder, ["boletus-edulis"])

        state.toggleSpecies("boletus-edulis")
        XCTAssertFalse(state.isActive("boletus-edulis"))
        XCTAssertEqual(state.activeSpeciesOrder, [])
    }

    func testDominantSpeciesReturnsNilWithNoActiveSpecies() async {
        // Load a real snapshot first so the assertion below exercises the "no active species"
        // path specifically, not the separate "no snapshot for this point" early-return.
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot]))
        await state.loadGrid()

        XCTAssertNil(state.dominantSpecies(at: "grid-00"))
    }

    func testDominantSpeciesReturnsNilWhenSnapshotMissing() {
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil]))
        state.toggleSpecies("boletus-edulis")
        XCTAssertNil(state.dominantSpecies(at: "grid-00"), "no snapshot was ever loaded for this point")
    }
}
