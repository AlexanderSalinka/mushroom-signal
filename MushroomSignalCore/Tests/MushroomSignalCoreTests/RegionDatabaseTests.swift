import XCTest
@testable import MushroomSignalCore

final class RegionDatabaseTests: XCTestCase {
    func testContainsAllEightKraje() {
        XCTAssertEqual(RegionDatabase.all.count, 8)
    }

    func testAllIdsAreUnique() {
        let ids = Set(RegionDatabase.all.map(\.id))
        XCTAssertEqual(ids.count, RegionDatabase.all.count)
    }

    func testFindReturnsCorrectRegion() {
        let region = RegionDatabase.find(id: "zilinsky")
        XCTAssertEqual(region?.nameSk, "Žilinský kraj")
    }

    func testFindReturnsNilForUnknownId() {
        XCTAssertNil(RegionDatabase.find(id: "does-not-exist"))
    }
}
