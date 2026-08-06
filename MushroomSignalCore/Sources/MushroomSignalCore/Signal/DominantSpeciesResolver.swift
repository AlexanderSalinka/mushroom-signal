import Foundation

/// Picks which active species "wins" the color at a single map grid point. Reuses the exact same
/// scoring (`SignalAlgorithm`) and tie-break (`ShortlistRanker`) as the shortlist — no new algorithm
/// (v2 spec §2).
public enum DominantSpeciesResolver {
    public static func resolve(activeSpecies: [Species], weather: WeatherSnapshot, month: Int) -> Species? {
        guard !activeSpecies.isEmpty else { return nil }
        let signals = activeSpecies.map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
        guard let top = ShortlistRanker.topSpecies(from: signals, limit: 1).first, top.score > 0 else {
            return nil
        }
        return top.species
    }
}
