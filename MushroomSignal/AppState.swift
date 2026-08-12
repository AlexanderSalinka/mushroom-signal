import Foundation
import os
import MushroomSignalCore

@MainActor
final class AppState: ObservableObject {
    @Published var selectedRegion: Region
    @Published var signals: [SpeciesSignal] = []
    @Published var dailyWeather: [DailyWeather] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isShowingStaleData = false

    private let store: RegionStore?
    private let weatherCache: WeatherSnapshotCache?
    private let dailyWeatherCache: DailyWeatherCache?
    private let weatherClient: WeatherClient
    private let widgetReloader: WidgetReloading
    private let now: () -> Date
    private var currentRefreshID: UUID?
    private let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "AppState")

    private static let staleTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    init(
        store: RegionStore? = RegionStore(),
        weatherCache: WeatherSnapshotCache? = WeatherSnapshotCache(),
        dailyWeatherCache: DailyWeatherCache? = DailyWeatherCache(),
        weatherClient: WeatherClient = OpenMeteoClient(),
        widgetReloader: WidgetReloading = SystemWidgetCenter(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.weatherCache = weatherCache
        self.dailyWeatherCache = dailyWeatherCache
        self.weatherClient = weatherClient
        self.widgetReloader = widgetReloader
        self.now = now
        self.selectedRegion = store?.selectedRegion() ?? RegionDatabase.all[0]
        if store == nil {
            logger.error("RegionStore init failed — region selection will not persist across launches or sync to the widget")
        }
    }

    func selectRegion(_ region: Region) {
        selectedRegion = region
        store?.setSelectedRegion(region)
        Task {
            await widgetReloader.reloadAllTimelines()
            await refresh()
        }
    }

    func refresh() async {
        let refreshID = UUID()
        currentRefreshID = refreshID
        isLoading = true
        errorMessage = nil
        defer {
            if currentRefreshID == refreshID {
                isLoading = false
            }
        }

        let region = selectedRegion
        do {
            let daily = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 30, forecastDays: 5)
            guard let weather = WeatherSnapshot.derive(regionId: region.id, from: daily, asOf: now()) else {
                throw WeatherClientError.emptyDailyData
            }
            weatherCache?.store(weather)
            dailyWeatherCache?.store(daily, for: region.id)
            let flushTriggered = FlushTriggerDetector.triggered(in: daily, asOf: now())
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: now())
            let ranked = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: weather, month: month, flushTriggered: flushTriggered)
            guard currentRefreshID == refreshID else { return }
            signals = ranked
            dailyWeather = daily
            isShowingStaleData = false
        } catch {
            guard currentRefreshID == refreshID else { return }
            if let cachedSnapshot = weatherCache?.snapshot(for: region.id),
               let cachedDaily = dailyWeatherCache?.dailyWeather(for: region.id),
               let allSpecies = try? SpeciesDatabase.loadAll() {
                let month = Calendar.current.component(.month, from: now())
                signals = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: cachedSnapshot, month: month, flushTriggered: false)
                dailyWeather = cachedDaily
                isShowingStaleData = true
                errorMessage = "Zobrazujú sa staršie údaje z \(Self.staleTimeFormatter.string(from: cachedSnapshot.fetchedAt))."
            } else {
                signals = []
                dailyWeather = []
                isShowingStaleData = false
                errorMessage = "Nepodarilo sa načítať údaje o počasí. Skúste to znova."
            }
            logger.error("Refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
