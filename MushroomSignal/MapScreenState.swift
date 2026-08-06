import Foundation
import SwiftUI
import os
import MushroomSignalCore

@MainActor
final class MapScreenState: ObservableObject {
    @Published var activeSpeciesOrder: [String] = []
    @Published var snapshots: [String: WeatherSnapshot] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    let gridPoints: [GridPoint]
    let allSpecies: [Species]
    let photosBySpeciesID: [String: [SpeciesPhoto]]

    private let weatherClient: WeatherClient
    private let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "MapScreenState")

    init(weatherClient: WeatherClient = OpenMeteoClient()) {
        self.weatherClient = weatherClient
        self.gridPoints = SlovakiaGrid.generate()
        self.allSpecies = (try? SpeciesDatabase.loadAll()) ?? []
        let photos = (try? SpeciesPhotoDatabase.loadAll()) ?? []
        self.photosBySpeciesID = Dictionary(grouping: photos, by: \.speciesId)
    }

    func toggleSpecies(_ id: String) {
        if let index = activeSpeciesOrder.firstIndex(of: id) {
            activeSpeciesOrder.remove(at: index)
        } else {
            activeSpeciesOrder.append(id)
        }
    }

    func isActive(_ id: String) -> Bool {
        activeSpeciesOrder.contains(id)
    }

    func loadGrid() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            snapshots = try await weatherClient.fetchSnapshots(for: gridPoints)
        } catch {
            snapshots = [:]
            errorMessage = "Nepodarilo sa načítať mapu počasia. Skúste to znova."
            logger.error("Grid weather fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    func dominantSpecies(at pointID: String) -> Species? {
        guard let snapshot = snapshots[pointID] else { return nil }
        let active = allSpecies.filter { activeSpeciesOrder.contains($0.id) }
        guard !active.isEmpty else { return nil }
        let month = Calendar.current.component(.month, from: Date())
        return DominantSpeciesResolver.resolve(activeSpecies: active, weather: snapshot, month: month)
    }

    var speciesColors: [String: Color] {
        SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: activeSpeciesOrder)
    }
}
