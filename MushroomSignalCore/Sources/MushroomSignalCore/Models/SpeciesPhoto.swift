import Foundation

public struct SpeciesPhoto: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let speciesId: String
    public let imageURL: URL
    public let photographer: String
    public let license: String
    public let sourceURL: URL

    public init(id: String, speciesId: String, imageURL: URL, photographer: String, license: String, sourceURL: URL) {
        self.id = id
        self.speciesId = speciesId
        self.imageURL = imageURL
        self.photographer = photographer
        self.license = license
        self.sourceURL = sourceURL
    }
}
