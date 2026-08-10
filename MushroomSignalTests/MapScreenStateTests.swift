import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class MapScreenStateTests: XCTestCase {
    func testLoadGridPopulatesSnapshotsOnSuccess() async {
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
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

    func testDominantSignalReturnsNilWithNoActiveSpecies() async {
        // Load a real snapshot first so the assertion below exercises the "no active species"
        // path specifically, not the separate "no snapshot for this point" early-return.
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot]))
        await state.loadGrid()

        XCTAssertNil(state.dominantSignal(at: "grid-00"))
    }

    func testDominantSignalReturnsNilWhenSnapshotMissing() {
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil]))
        state.toggleSpecies("boletus-edulis")
        XCTAssertNil(state.dominantSignal(at: "grid-00"), "no snapshot was ever loaded for this point")
    }

    func testDominantSignalReturnsNilWhenActiveSpeciesScoresZero() async {
        // Uses the real bundled species dataset (MapScreenState.allSpecies isn't injectable) and
        // picks whichever species is genuinely out of season for "today" (calendarFit == 0 is the
        // only way SignalAlgorithm.computeSignal can resolve to a hard score of 0), rather than
        // hardcoding a month/species pair that would only hold on some calendar dates.
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot]))
        await state.loadGrid()

        let month = Calendar.current.component(.month, from: Date())
        let previousMonth = month == 1 ? 12 : month - 1
        let nextMonth = month == 12 ? 1 : month + 1
        guard let outOfSeasonSpecies = state.allSpecies.first(where: {
            !$0.fruitingMonths.contains(month) && !$0.fruitingMonths.contains(previousMonth) && !$0.fruitingMonths.contains(nextMonth)
        }) else {
            XCTFail("expected at least one species in the real dataset out of season for the current month")
            return
        }

        state.toggleSpecies(outOfSeasonSpecies.id)
        XCTAssertNil(state.dominantSignal(at: "grid-00"))
    }
}
