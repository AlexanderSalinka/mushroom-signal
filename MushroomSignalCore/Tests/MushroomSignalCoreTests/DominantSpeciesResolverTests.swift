// MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift
import XCTest
@testable import MushroomSignalCore

final class DominantSpeciesResolverTests: XCTestCase {
    private let warmWetWeather = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 16, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: .now)

    private func species(id: String, name: String, edibility: Edibility, minC: Double, maxC: Double, months: Set<Int> = [6, 7, 8, 9]) -> Species {
        Species(id: id, commonNameSk: name, latinName: id, edibility: edibility, fruitingMonths: months, idealTempMinC: minC, idealTempMaxC: maxC, idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90, rainfallSensitivity: .low, habitat: "test", regionalAffinity: [])
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

    func testTiesBreakByEdibilityWhenScoreMatches() {
        let poisonousA = species(id: "a", name: "Zeta", edibility: .poisonous, minC: 10, maxC: 20)
        let edibleB = species(id: "b", name: "Alpha", edibility: .edible, minC: 10, maxC: 20)
        let result = DominantSpeciesResolver.resolve(activeSpecies: [poisonousA, edibleB], weather: warmWetWeather, month: 7)
        XCTAssertEqual(result?.id, "b", "when scores match, edible beats poisonous")
    }

    func testTiesBreakByNameWhenEdibilityMatches() {
        let zeta = species(id: "a", name: "Zeta", edibility: .edible, minC: 10, maxC: 20)
        let alpha = species(id: "b", name: "Alpha", edibility: .edible, minC: 10, maxC: 20)
        let result = DominantSpeciesResolver.resolve(activeSpecies: [zeta, alpha], weather: warmWetWeather, month: 7)
        XCTAssertEqual(result?.id, "b", "when score and edibility match, alphabetical name order (Alpha < Zeta) wins")
    }
}
