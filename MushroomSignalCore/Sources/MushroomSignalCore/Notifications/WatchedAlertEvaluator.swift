import Foundation

public struct WatchedAlertUpdate: Sendable {
    public let alert: WatchedAlert
    public let newScore: Int
    public let shouldNotify: Bool
}

/// Scores each watched alert against current weather, reusing SignalPipeline — no new scoring
/// logic. Fetches weather once per DISTINCT watched region, not once per alert, since several
/// alerts commonly share a region. flushTriggered is always false, matching the same
/// simplification the map's DominantSpeciesResolver-era code used: evaluating the flush
/// trigger per watched region would need a second, batched daily-breakdown fetch, out of
/// scope for this pass.
public enum WatchedAlertEvaluator {
    public static func evaluate(
        alerts: [WatchedAlert],
        species: [Species],
        weatherClient: WeatherClient,
        month: Int
    ) async -> [WatchedAlertUpdate] {
        guard !alerts.isEmpty else { return [] }

        let speciesByID = Dictionary(uniqueKeysWithValues: species.map { ($0.id, $0) })
        let distinctRegionIds = Set(alerts.map(\.regionId))

        var snapshotsByRegion: [String: WeatherSnapshot] = [:]
        for regionId in distinctRegionIds {
            guard let region = RegionDatabase.find(id: regionId) else { continue }
            if let snapshot = try? await weatherClient.fetchSnapshot(for: region) {
                snapshotsByRegion[regionId] = snapshot
            }
        }

        var updates: [WatchedAlertUpdate] = []
        for alert in alerts {
            guard let speciesForAlert = speciesByID[alert.speciesId],
                  let snapshot = snapshotsByRegion[alert.regionId],
                  let signal = SignalPipeline.rankedSignals(candidates: [speciesForAlert], weather: snapshot, month: month, flushTriggered: false, limit: 1).first else { continue }
            let notify = NotificationThreshold.shouldNotify(previousScore: alert.lastKnownScore, newScore: signal.score, threshold: alert.threshold)
            updates.append(WatchedAlertUpdate(alert: alert, newScore: signal.score, shouldNotify: notify))
        }
        return updates
    }
}
