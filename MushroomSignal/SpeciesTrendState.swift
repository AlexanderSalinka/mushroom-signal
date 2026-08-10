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
            let dailyWeather = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 10, forecastDays: 4)
            points = SpeciesTrendCalculator.trend(species: species, dailyWeather: dailyWeather, regionId: regionId)
        } catch {
            points = []
            errorMessage = "Nepodarilo sa načítať trend."
        }
    }
}
