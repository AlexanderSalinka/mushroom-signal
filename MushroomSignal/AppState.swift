import Foundation
import os
import MushroomSignalCore

@MainActor
final class AppState: ObservableObject {
    @Published var selectedRegion: Region
    @Published var signals: [SpeciesSignal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store: RegionStore?
    private let weatherClient: WeatherClient
    private var currentRefreshID: UUID?
    private let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "AppState")

    init(store: RegionStore? = RegionStore(), weatherClient: WeatherClient = OpenMeteoClient()) {
        self.store = store
        self.weatherClient = weatherClient
        self.selectedRegion = store?.selectedRegion() ?? RegionDatabase.all[0]
    }

    func selectRegion(_ region: Region) {
        selectedRegion = region
        store?.setSelectedRegion(region)
        Task { await refresh() }
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
            let weather = try await weatherClient.fetchSnapshot(for: region)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let allSignals = allSpecies
                .filter { $0.regionalAffinity.contains(region.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            guard currentRefreshID == refreshID else { return }
            signals = ShortlistRanker.topSpecies(from: allSignals, limit: allSignals.count)
        } catch {
            guard currentRefreshID == refreshID else { return }
            signals = []
            errorMessage = "Nepodarilo sa načítať údaje o počasí. Skúste to znova."
            logger.error("Refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
