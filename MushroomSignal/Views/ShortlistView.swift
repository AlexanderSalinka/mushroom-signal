// MushroomSignal/Views/ShortlistView.swift
import SwiftUI
import MushroomSignalCore

struct ShortlistView: View {
    @ObservedObject var appState: AppState
    @State private var detailSpecies: Species?
    @State private var photosBySpeciesID: [String: [SpeciesPhoto]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                if let error = appState.errorMessage {
                    Text(error)
                        .foregroundStyle(appState.isShowingStaleData ? DesignSystem.Colors.caution : DesignSystem.Colors.danger)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: DesignSystem.speciesCardMinWidth), spacing: DesignSystem.spacingSmall)], spacing: DesignSystem.spacingSmall) {
                    ForEach(appState.signals, id: \.species.id) { signal in
                        Button {
                            detailSpecies = signal.species
                        } label: {
                            SpeciesCardView(species: signal.species, photo: photosBySpeciesID[signal.species.id]?.first, signal: signal, isActiveOnMap: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }

                disclaimer
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .refreshable { await appState.refresh() }
        .task {
            photosBySpeciesID = (try? SpeciesPhotoDatabase.loadAll()).map { Dictionary(grouping: $0, by: \.speciesId) } ?? [:]
        }
        .sheet(item: $detailSpecies) { species in
            SpeciesDetailView(species: species, photos: photosBySpeciesID[species.id] ?? [], regionId: appState.selectedRegion.id)
        }
    }

    private var disclaimer: some View {
        Text("Tento zoznam je len orientačný odhad na základe počasia a sezóny. Pred zberom a konzumáciou húb si nález vždy overte s odborníkom alebo v spoľahlivom atlase húb.")
            .font(.system(size: DesignSystem.captionSize))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            .padding(.top, DesignSystem.spacingMedium)
    }
}
