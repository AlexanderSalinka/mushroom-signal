import Foundation

public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]
    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather]
}

public extension WeatherClient {
    /// Preserves the pre-existing 2-arg call (`AppState.refresh`, `ShortlistProvider.fetchEntry`)
    /// unchanged — Swift doesn't allow default parameter values directly on protocol
    /// requirements, so the default lives here instead.
    func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
        try await fetchDailyBreakdown(for: region, pastDays: pastDays, forecastDays: 0)
    }
}
