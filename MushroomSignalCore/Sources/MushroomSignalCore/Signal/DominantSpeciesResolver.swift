import Foundation

/// Picks which active species "wins" the color at a single map grid point. Reuses the exact same
/// scoring (`SignalAlgorithm`) and tie-break (`ShortlistRanker`) as the shortlist, via the shared
/// `SignalPipeline` — no new algorithm (v2 spec §2).
///
/// Always passes `flushTriggered: false` — the map's per-grid-point coloring intentionally does not
/// evaluate the warm-day+rain flush trigger. Doing so would need a batched per-point daily-breakdown
/// fetch, which is out of scope; see the 2026-08-07 roadmap spec §1, which also directs that the map
/// itself stay untouched in this phase.
public enum DominantSpeciesResolver {
    public static func resolve(activeSpecies: [Species], weather: WeatherSnapshot, month: Int) -> Species? {
        guard !activeSpecies.isEmpty else { return nil }
        guard let top = SignalPipeline.rankedSignals(candidates: activeSpecies, weather: weather, month: month, flushTriggered: false, limit: 1).first,
              top.score > 0 else {
            return nil
        }
        return top.species
    }
}
