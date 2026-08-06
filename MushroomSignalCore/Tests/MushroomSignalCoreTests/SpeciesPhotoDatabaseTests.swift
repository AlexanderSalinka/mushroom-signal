import XCTest
@testable import MushroomSignalCore

final class SpeciesPhotoDatabaseTests: XCTestCase {
    func testSpeciesPhotoDecodesFromJSON() throws {
        let json = """
        {
          "id": "boletus-edulis-1",
          "speciesId": "boletus-edulis",
          "imageURL": "https://upload.wikimedia.org/wikipedia/commons/example.jpg",
          "photographer": "Jane Doe",
          "license": "CC BY-SA 4.0",
          "sourceURL": "https://commons.wikimedia.org/wiki/File:example.jpg"
        }
        """.data(using: .utf8)!

        let photo = try JSONDecoder().decode(SpeciesPhoto.self, from: json)

        XCTAssertEqual(photo.speciesId, "boletus-edulis")
        XCTAssertEqual(photo.license, "CC BY-SA 4.0")
        XCTAssertEqual(photo.imageURL, URL(string: "https://upload.wikimedia.org/wikipedia/commons/example.jpg"))
    }

    func testLoadAllReturnsEmptyArrayForCurrentBundledFile() throws {
        // species-photos.json ships empty pending manual curation — this proves the loader
        // handles the zero-photos case cleanly rather than throwing.
        let photos = try SpeciesPhotoDatabase.loadAll()
        XCTAssertEqual(photos, [])
    }
}
