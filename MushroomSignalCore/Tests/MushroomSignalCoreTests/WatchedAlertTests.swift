import XCTest
@testable import MushroomSignalCore

final class WatchedAlertTests: XCTestCase {
    func testIdCombinesSpeciesAndRegion() {
        let alert = WatchedAlert(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)
        XCTAssertEqual(alert.id, "boletus-edulis|zilinsky")
    }

    func testRoundTripsThroughJSON() throws {
        let alert = WatchedAlert(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3, lastKnownScore: 2)
        let data = try JSONEncoder().encode(alert)
        let decoded = try JSONDecoder().decode(WatchedAlert.self, from: data)
        XCTAssertEqual(decoded, alert)
    }
}
