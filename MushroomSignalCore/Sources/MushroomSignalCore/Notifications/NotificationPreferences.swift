import Foundation

/// Persists watched-species alerts, App-Group-scoped so the widget (which performs the actual
/// threshold checks) and the app (where alerts are configured) always see the same list.
/// Mirrors `WeatherSnapshotCache`'s pattern — JSON round-trip via Data, not a primitive-value
/// store, since this persists a structured, Codable array.
public struct NotificationPreferences {
    private let defaults: UserDefaults
    private static let key = "notificationPreferences.watchedAlerts"

    public init?(appGroupId: String = RegionStoreConstants.appGroupId) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        self.defaults = defaults
    }

    public func watchedAlerts() -> [WatchedAlert] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([WatchedAlert].self, from: data)) ?? []
    }

    /// Full replace — the caller is responsible for merging with the existing list first if
    /// it wants to upsert rather than overwrite.
    public func setWatchedAlerts(_ alerts: [WatchedAlert]) {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
