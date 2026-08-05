import XCTest
@testable import MushroomSignalCore

final class ModelDecodingTests: XCTestCase {
    func testSpeciesDecodesFromJSON() throws {
        let json = """
        {
          "id": "boletus-edulis",
          "commonNameSk": "Hríb smrekový",
          "latinName": "Boletus edulis",
          "edibility": "edible",
          "lookAlikes": ["tylopilus-felleus"],
          "fruitingMonths": [6,7,8,9,10],
          "idealTempMinC": 12,
          "idealTempMaxC": 22,
          "rainfallSensitivity": "high",
          "habitat": "smrekové a borovicové lesy",
          "regionalAffinity": ["zilinsky", "presovsky"]
        }
        """.data(using: .utf8)!

        let species = try JSONDecoder().decode(Species.self, from: json)

        XCTAssertEqual(species.id, "boletus-edulis")
        XCTAssertEqual(species.commonNameSk, "Hríb smrekový")
        XCTAssertEqual(species.edibility, .edible)
        XCTAssertEqual(species.fruitingMonths, [6, 7, 8, 9, 10])
        XCTAssertEqual(species.rainfallSensitivity, .high)
        XCTAssertEqual(species.regionalAffinity, ["zilinsky", "presovsky"])
    }

    func testRegionDecodesFromJSON() throws {
        let json = """
        { "id": "zilinsky", "nameSk": "Žilinský kraj", "latitude": 49.2231, "longitude": 18.7394 }
        """.data(using: .utf8)!

        let region = try JSONDecoder().decode(Region.self, from: json)

        XCTAssertEqual(region.id, "zilinsky")
        XCTAssertEqual(region.latitude, 49.2231, accuracy: 0.0001)
    }
}
