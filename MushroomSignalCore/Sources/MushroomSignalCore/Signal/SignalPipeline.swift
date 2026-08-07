import Foundation

/// The one shared score→rank path for turning candidate species into a ranked shortlist.
/// Used by the app's `AppState.refresh()`, the widget's `ShortlistProvider`, and (via
/// `DominantSpeciesResolver`) the map's per-point dominant-species resolution — previously
/// each reimplemented filter→score→rank independently (see KNOWN_ISSUES.md).
public enum SignalPipeline {
    /// Scores the given candidates against weather/month and returns them ranked
    /// (best score first, then edibility, then name — see `ShortlistRanker`).
    public static func rankedSignals(
        candidates: [Species],
        weather: WeatherSnapshot,
        month: Int,
        flushTriggered: Bool,
        limit: Int? = nil
    ) -> [SpeciesSignal] {
        let signals = candidates.map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month, flushTriggered: flushTriggered) }
        return ShortlistRanker.topSpecies(from: signals, limit: limit ?? signals.count)
    }

    /// Convenience for the common case: candidates are every species with affinity for
    /// `region`, scored and ranked. Used by the app's shortlist and the widget's timeline.
    public static func rankedSignals(
        species: [Species],
        region: Region,
        weather: WeatherSnapshot,
        month: Int,
        flushTriggered: Bool,
        limit: Int? = nil
    ) -> [SpeciesSignal] {
        rankedSignals(
            candidates: species.filter { $0.regionalAffinity.contains(region.id) },
            weather: weather,
            month: month,
            flushTriggered: flushTriggered,
            limit: limit
        )
    }
}
