import Foundation

/// Persists the last successful daily weather array per region — the array-shaped
/// counterpart to WeatherSnapshotCache, added so the chart/hero can fall back to stale
/// data the same way the shortlist already does via WeatherSnapshotCache. Deliberately a
/// separate cache, not a merged one: WeatherSnapshotCache is also read by the widget
/// (ShortlistProvider), which doesn't need the daily array — extending
/// WeatherSnapshotCache's shape would be a wider, riskier change for no benefit to that
/// consumer. Same App Group UserDefaults suite, same get/store/key pattern.
public struct DailyWeatherCache {
    private let defaults: UserDefaults

    public init?(appGroupId: String = RegionStoreConstants.appGroupId) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        self.defaults = defaults
    }

    public func dailyWeather(for regionId: String) -> [DailyWeather]? {
        guard let data = defaults.data(forKey: key(for: regionId)) else { return nil }
        return try? JSONDecoder().decode([DailyWeather].self, from: data)
    }

    public func store(_ dailyWeather: [DailyWeather], for regionId: String) {
        guard let data = try? JSONEncoder().encode(dailyWeather) else { return }
        defaults.set(data, forKey: key(for: regionId))
    }

    private func key(for regionId: String) -> String {
        "dailyWeatherCache.\(regionId)"
    }
}
