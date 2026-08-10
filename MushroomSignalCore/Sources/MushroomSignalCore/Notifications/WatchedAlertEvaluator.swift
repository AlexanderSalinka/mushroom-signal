import Foundation

public struct WatchedAlertUpdate: Sendable {
    public let alert: WatchedAlert
    public let newScore: Int
    public let shouldNotify: Bool
}

/// Scores each watched alert against current weather, reusing SignalPipeline — no new scoring
/// logic. Fetches weather for every DISTINCT watched region in a single batched request (not
/// once per alert, not one request per region), since several alerts commonly share a region
/// and this runs ahead of the widget's completion(timeline) call. Uses the region-aware
/// SignalPipeline overload so a species outside its regionalAffinity for the watched region is
/// never scored — the same filtering every other consumer (AppState, the widget's own
/// shortlist, the map) applies; an alert whose species has no affinity for its watched region
/// is skipped, matching how that combination can't occur anywhere else in the app.
/// flushTriggered is always false, matching the same simplification the map's
/// DominantSpeciesResolver-era code used: evaluating the flush trigger per watched region would
/// need a second, batched daily-breakdown fetch, out of scope for this pass (see
/// KNOWN_ISSUES.md).
public enum WatchedAlertEvaluator {
    public static func evaluate(
        alerts: [WatchedAlert],
        species: [Species],
        weatherClient: WeatherClient,
        month: Int
    ) async -> [WatchedAlertUpdate] {
        guard !alerts.isEmpty else { return [] }

        let speciesByID = Dictionary(uniqueKeysWithValues: species.map { ($0.id, $0) })
        let distinctRegions = Set(alerts.map(\.regionId)).compactMap { RegionDatabase.find(id: $0) }
        let points = distinctRegions.map { GridPoint(id: $0.id, latitude: $0.latitude, longitude: $0.longitude) }
        let snapshotsByRegion = (try? await weatherClient.fetchSnapshots(for: points)) ?? [:]

        var updates: [WatchedAlertUpdate] = []
        for alert in alerts {
            guard let speciesForAlert = speciesByID[alert.speciesId],
                  let region = RegionDatabase.find(id: alert.regionId),
                  let snapshot = snapshotsByRegion[alert.regionId],
                  let signal = SignalPipeline.rankedSignals(species: [speciesForAlert], region: region, weather: snapshot, month: month, flushTriggered: false, limit: 1).first else { continue }
            let notify = NotificationThreshold.shouldNotify(previousScore: alert.lastKnownScore, newScore: signal.score, threshold: alert.threshold)
            updates.append(WatchedAlertUpdate(alert: alert, newScore: signal.score, shouldNotify: notify))
        }
        return updates
    }
}
