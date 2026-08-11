import Foundation

public struct SpeciesSignal: Equatable, Sendable {
    public let species: Species
    public let score: Int
    public let reason: String?
    public let flushTriggered: Bool

    public init(species: Species, score: Int, reason: String?, flushTriggered: Bool) {
        self.species = species
        self.score = score
        self.reason = reason
        self.flushTriggered = flushTriggered
    }
}
