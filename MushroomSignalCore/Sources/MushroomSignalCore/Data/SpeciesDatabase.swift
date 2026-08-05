import Foundation

public enum SpeciesDatabaseError: Error, Equatable {
    case resourceNotFound
}

public enum SpeciesDatabase {
    public static func loadAll() throws -> [Species] {
        guard let url = Bundle.module.url(forResource: "species", withExtension: "json") else {
            throw SpeciesDatabaseError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Species].self, from: data)
    }
}
