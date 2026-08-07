// MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift
import XCTest
@testable import MushroomSignalCore

final class ShortlistRankerTests: XCTestCase {
    private func makeSpecies(id: String, name: String, edibility: Edibility) -> Species {
        Species(
            id: id,
            commonNameSk: name,
            latinName: name,
            edibility: edibility,
            lookAlikes: [],
            fruitingMonths: [8],
            idealTempMinC: 10,
            idealTempMaxC: 20,
            idealHumidityMinPercent: 60,
            idealHumidityMaxPercent: 90,
            rainfallSensitivity: .medium,
            habitat: "test",
            regionalAffinity: ["zilinsky"]
        )
    }

    func testReturnsTopNSortedByScoreDescending() {
        let signals = [
            SpeciesSignal(species: makeSpecies(id: "a", name: "A", edibility: .edible), score: 1, reason: nil),
            SpeciesSignal(species: makeSpecies(id: "b", name: "B", edibility: .edible), score: 3, reason: nil),
            SpeciesSignal(species: makeSpecies(id: "c", name: "C", edibility: .edible), score: 2, reason: nil)
        ]

        let top = ShortlistRanker.topSpecies(from: signals, limit: 3)

        XCTAssertEqual(top.map { $0.species.id }, ["b", "c", "a"])
    }

    func testLimitsResultCount() {
        let signals = (0..<5).map {
            SpeciesSignal(species: makeSpecies(id: "s\($0)", name: "S\($0)", edibility: .edible), score: $0, reason: nil)
        }

        let top = ShortlistRanker.topSpecies(from: signals, limit: 3)

        XCTAssertEqual(top.count, 3)
    }

    func testTiesBreakByEdibilityThenName() {
        let signals = [
            SpeciesSignal(species: makeSpecies(id: "poison", name: "Z Poison", edibility: .poisonous), score: 2, reason: nil),
            SpeciesSignal(species: makeSpecies(id: "edible", name: "A Edible", edibility: .edible), score: 2, reason: nil)
        ]

        let top = ShortlistRanker.topSpecies(from: signals, limit: 2)

        XCTAssertEqual(top.first?.species.id, "edible")
    }

    func testTiesBreakByNameWhenScoreAndEdibilityEqual() {
        let signals = [
            SpeciesSignal(species: makeSpecies(id: "z", name: "Zebra", edibility: .edible), score: 5, reason: nil),
            SpeciesSignal(species: makeSpecies(id: "a", name: "Apple", edibility: .edible), score: 5, reason: nil)
        ]

        let top = ShortlistRanker.topSpecies(from: signals, limit: 2)

        XCTAssertEqual(top.first?.species.id, "a")
    }

    func testReturnsEmptyArrayForZeroLimit() {
        let signals = [
            SpeciesSignal(species: makeSpecies(id: "a", name: "A", edibility: .edible), score: 10, reason: nil)
        ]

        let top = ShortlistRanker.topSpecies(from: signals, limit: 0)

        XCTAssertEqual(top, [])
    }
}
