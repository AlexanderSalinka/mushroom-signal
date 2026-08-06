// MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift
import XCTest
@testable import MushroomSignalCore

final class DominantSpeciesResolverTests: XCTestCase {
    private let warmWetWeather = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 16, totalPrecipitationLast10DaysMm: 25, fetchedAt: .now)

    private func species(id: String, name: String, edibility: Edibility, minC: Double, maxC: Double, months: Set<Int> = [6, 7, 8, 9]) -> Species {
        Species(id: id, commonNameSk: name, latinName: id, edibility: edibility, fruitingMonths: months, idealTempMinC: minC, idealTempMaxC: maxC, rainfallSensitivity: .low, habitat: "test", regionalAffinity: [])
    }

    func testResolvesHighestScoringActiveSpecies() {
        let strongMatch = species(id: "a", name: "Alpha", edibility: .edible, minC: 10, maxC: 20)
        let weakMatch = species(id: "b", name: "Beta", edibility: .edible, minC: 30, maxC: 35)
        let result = DominantSpeciesResolver.resolve(activeSpecies: [strongMatch, weakMatch], weather: warmWetWeather, month: 7)
        XCTAssertEqual(result?.id, "a")
    }

    func testReturnsNilWhenNoActiveSpecies() {
        let result = DominantSpeciesResolver.resolve(activeSpecies: [], weather: warmWetWeather, month: 7)
        XCTAssertNil(result)
    }

    func testReturnsNilWhenEveryActiveSpeciesScoresZero() {
        let outOfSeason = species(id: "a", name: "Alpha", edibility: .edible, minC: 10, maxC: 20, months: [1])
        let result = DominantSpeciesResolver.resolve(activeSpecies: [outOfSeason], weather: warmWetWeather, month: 7)
        XCTAssertNil(result)
    }

    func testTiesBreakByEdibilityThenName() {
        let poisonousA = species(id: "a", name: "Zeta", edibility: .poisonous, minC: 10, maxC: 20)
        let edibleB = species(id: "b", name: "Alpha", edibility: .edible, minC: 10, maxC: 20)
        let result = DominantSpeciesResolver.resolve(activeSpecies: [poisonousA, edibleB], weather: warmWetWeather, month: 7)
        XCTAssertEqual(result?.id, "b", "edible should win the tie over poisonous regardless of name order")
    }
}
