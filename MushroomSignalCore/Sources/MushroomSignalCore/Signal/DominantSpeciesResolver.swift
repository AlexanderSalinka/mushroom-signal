import Foundation

/// Picks which active species "wins" the color at a single map grid point. Reuses the exact same
/// scoring (`SignalAlgorithm`) and tie-break (`ShortlistRanker`) as the shortlist, via the shared
/// `SignalPipeline` — no new algorithm (v2 spec §2).
public enum DominantSpeciesResolver {
    public static func resolve(activeSpecies: [Species], weather: WeatherSnapshot, month: Int) -> Species? {
        guard !activeSpecies.isEmpty else { return nil }
        guard let top = SignalPipeline.rankedSignals(candidates: activeSpecies, weather: weather, month: month, limit: 1).first,
              top.score > 0 else {
            return nil
        }
        return top.species
    }
}
