import Foundation
import MushroomSignalCore

@MainActor
final class AppState: ObservableObject {
    @Published var selectedRegion: Region
    @Published var signals: [SpeciesSignal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store: RegionStore?
    private let weatherClient: WeatherClient

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
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let weather = try await weatherClient.fetchSnapshot(for: selectedRegion)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let allSignals = allSpecies
                .filter { $0.regionalAffinity.contains(selectedRegion.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            signals = ShortlistRanker.topSpecies(from: allSignals, limit: allSignals.count)
        } catch {
            errorMessage = "Nepodarilo sa načítať údaje o počasí. Skúste to znova."
        }
    }
}
