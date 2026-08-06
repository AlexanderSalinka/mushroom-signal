import Foundation

public enum SpeciesPhotoDatabaseError: Error, Equatable {
    case resourceNotFound
}

public enum SpeciesPhotoDatabase {
    public static func loadAll() throws -> [SpeciesPhoto] {
        guard let url = Bundle.module.url(forResource: "species-photos", withExtension: "json") else {
            throw SpeciesPhotoDatabaseError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([SpeciesPhoto].self, from: data)
    }
}
