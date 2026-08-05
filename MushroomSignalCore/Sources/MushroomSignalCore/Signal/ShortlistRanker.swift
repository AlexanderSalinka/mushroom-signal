import Foundation

public enum ShortlistRanker {
    public static func topSpecies(from signals: [SpeciesSignal], limit: Int) -> [SpeciesSignal] {
        guard limit > 0 else { return [] }

        return signals
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.species.edibility != rhs.species.edibility {
                    return edibilityRank(lhs.species.edibility) < edibilityRank(rhs.species.edibility)
                }
                return lhs.species.commonNameSk < rhs.species.commonNameSk
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func edibilityRank(_ edibility: Edibility) -> Int {
        switch edibility {
        case .edible: return 0
        case .caution: return 1
        case .poisonous: return 2
        }
    }
}
