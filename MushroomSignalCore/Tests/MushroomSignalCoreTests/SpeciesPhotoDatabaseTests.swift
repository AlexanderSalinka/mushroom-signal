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

    func testLoadAllReturnsPhotosForCurrentBundledFile() throws {
        let photos = try SpeciesPhotoDatabase.loadAll()
        XCTAssertFalse(photos.isEmpty)
    }

    func testEveryEdibleSpeciesHasAtLeastOnePhoto() throws {
        let species = try SpeciesDatabase.loadAll()
        let photos = try SpeciesPhotoDatabase.loadAll()
        let speciesIdsWithPhotos = Set(photos.map(\.speciesId))
        let edibleSpeciesIds = Set(species.filter { $0.edibility == .edible }.map(\.id))

        let missing = edibleSpeciesIds.subtracting(speciesIdsWithPhotos)
        XCTAssertTrue(missing.isEmpty, "edible species missing a photo: \(missing.sorted())")
    }

    func testNoCautionOrPoisonousSpeciesHasAPhoto() throws {
        let species = try SpeciesDatabase.loadAll()
        let photos = try SpeciesPhotoDatabase.loadAll()
        let speciesIdsWithPhotos = Set(photos.map(\.speciesId))
        let nonEdibleSpeciesIds = Set(species.filter { $0.edibility != .edible }.map(\.id))

        let violating = nonEdibleSpeciesIds.intersection(speciesIdsWithPhotos)
        XCTAssertTrue(violating.isEmpty, "non-edible species should never have a sourced photo: \(violating.sorted())")
    }

    func testEveryPhotoReferencesARealSpecies() throws {
        let species = try SpeciesDatabase.loadAll()
        let speciesIds = Set(species.map(\.id))
        let photos = try SpeciesPhotoDatabase.loadAll()

        for photo in photos {
            XCTAssertTrue(speciesIds.contains(photo.speciesId), "\(photo.id) references unknown species \(photo.speciesId)")
        }
    }
}
