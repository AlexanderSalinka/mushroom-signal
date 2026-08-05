import XCTest
@testable import MushroomSignalCore

final class SpeciesDataTests: XCTestCase {
    func testLoadsAtLeastTwentyFiveSpecies() throws {
        let species = try SpeciesDatabase.loadAll()
        XCTAssertGreaterThanOrEqual(species.count, 25)
    }

    func testAllIdsAreUnique() throws {
        let species = try SpeciesDatabase.loadAll()
        let ids = Set(species.map(\.id))
        XCTAssertEqual(ids.count, species.count)
    }

    func testAllLookAlikeReferencesResolve() throws {
        let species = try SpeciesDatabase.loadAll()
        let ids = Set(species.map(\.id))
        for s in species {
            for lookAlikeId in s.lookAlikes {
                XCTAssertTrue(ids.contains(lookAlikeId), "\(s.id) references unknown look-alike \(lookAlikeId)")
            }
        }
    }

    func testAllRegionalAffinityReferencesAreKnownRegions() throws {
        let species = try SpeciesDatabase.loadAll()
        let regionIds = Set(RegionDatabase.all.map(\.id))
        for s in species {
            for regionId in s.regionalAffinity {
                XCTAssertTrue(regionIds.contains(regionId), "\(s.id) references unknown region \(regionId)")
            }
        }
    }

    func testFruitingMonthsAreValidCalendarMonths() throws {
        let species = try SpeciesDatabase.loadAll()
        for s in species {
            for month in s.fruitingMonths {
                XCTAssertTrue((1...12).contains(month), "\(s.id) has invalid month \(month)")
            }
        }
    }

    func testContainsAtLeastOnePoisonousEntryForSafetyTesting() throws {
        let species = try SpeciesDatabase.loadAll()
        XCTAssertTrue(species.contains { $0.edibility == .poisonous })
    }
}
