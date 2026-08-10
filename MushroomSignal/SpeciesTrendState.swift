import Foundation
import MushroomSignalCore

@MainActor
final class SpeciesTrendState: ObservableObject {
    @Published var points: [TrendPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let weatherClient: WeatherClient

    init(weatherClient: WeatherClient = OpenMeteoClient()) {
        self.weatherClient = weatherClient
    }

    func load(species: Species, regionId: String) async {
        guard let region = RegionDatabase.find(id: regionId) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // 20 past days, not 10 — SpeciesTrendCalculator needs a full 10-day trailing
            // window of real data behind EVERY displayed point (for both the rolling
            // precipitation sum and the flush-trigger's 7-day lookback), so ~10 of these 20
            // fetched days are consumed as lookback context, leaving ~10 real displayed
            // points plus the forecast days. See the 2026-08-10 final review findings.
            let dailyWeather = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 20, forecastDays: 4)
            points = SpeciesTrendCalculator.trend(species: species, dailyWeather: dailyWeather, regionId: regionId)
        } catch {
            points = []
            errorMessage = "Nepodarilo sa načítať trend."
        }
    }
}
