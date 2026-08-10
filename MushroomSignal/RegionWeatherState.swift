import Foundation
import MushroomSignalCore
import os

@MainActor
final class RegionWeatherState: ObservableObject {
    @Published var dailyWeather: [DailyWeather] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let weatherClient: WeatherClient
    private var currentLoadID: UUID?
    private let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "RegionWeatherState")

    init(weatherClient: WeatherClient = OpenMeteoClient()) {
        self.weatherClient = weatherClient
    }

    func load(regionId: String) async {
        guard let region = RegionDatabase.find(id: regionId) else { return }
        let loadID = UUID()
        currentLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer {
            if currentLoadID == loadID {
                isLoading = false
            }
        }
        do {
            let result = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 10, forecastDays: 5)
            guard currentLoadID == loadID else { return }
            dailyWeather = result
        } catch {
            guard currentLoadID == loadID else { return }
            dailyWeather = []
            errorMessage = "Nepodarilo sa načítať počasie."
            logger.error("Daily breakdown fetch failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
