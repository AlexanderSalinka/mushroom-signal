import Foundation

/// Persists the last successful `WeatherSnapshot` per region so a transient network failure
/// can fall back to recent data instead of blanking the UI/widget entirely for a full
/// refresh cycle (see KNOWN_ISSUES.md's "No weather caching"). Shares the same App Group
/// UserDefaults suite as `RegionStore`, so the app and widget always see the same
/// last-known-good snapshot regardless of which process fetched it most recently.
public struct WeatherSnapshotCache {
    private let defaults: UserDefaults

    public init?(appGroupId: String = RegionStoreConstants.appGroupId) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        self.defaults = defaults
    }

    public func snapshot(for regionId: String) -> WeatherSnapshot? {
        guard let data = defaults.data(forKey: key(for: regionId)) else { return nil }
        return try? JSONDecoder().decode(WeatherSnapshot.self, from: data)
    }

    public func store(_ snapshot: WeatherSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(for: snapshot.regionId))
    }

    private func key(for regionId: String) -> String {
        "weatherCache.\(regionId)"
    }
}
