import Foundation
import MushroomSignalCore

@MainActor
final class RegionWeatherState: ObservableObject {
    @Published var dailyWeather: [DailyWeather] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let weatherClient: WeatherClient

    init(weatherClient: WeatherClient = OpenMeteoClient()) {
        self.weatherClient = weatherClient
    }

    func load(regionId: String) async {
        guard let region = RegionDatabase.find(id: regionId) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            dailyWeather = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 10, forecastDays: 5)
        } catch {
            dailyWeather = []
            errorMessage = "Nepodarilo sa načítať počasie."
        }
    }
}
