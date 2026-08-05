import Foundation

public struct SpeciesSignal: Equatable, Sendable {
    public let species: Species
    public let score: Int
    public let reason: String?

    public init(species: Species, score: Int, reason: String?) {
        self.species = species
        self.score = score
        self.reason = reason
    }
}
