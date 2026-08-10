// MushroomSignal/Views/SpeciesLibraryView.swift
import SwiftUI
import MushroomSignalCore

struct SpeciesLibraryView: View {
    @ObservedObject var mapState: MapScreenState
    @State private var detailSpecies: Species?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            Text("Knižnica druhov")
                .font(.system(size: DesignSystem.titleSize, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.cloud)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: DesignSystem.speciesCardMinWidth), spacing: DesignSystem.spacingSmall)], spacing: DesignSystem.spacingSmall) {
                ForEach(mapState.allSpecies) { species in
                    speciesCard(species)
                }
            }
        }
        .sheet(item: $detailSpecies) { species in
            SpeciesDetailView(species: species, photos: mapState.photosBySpeciesID[species.id] ?? [])
        }
    }

    private func speciesCard(_ species: Species) -> some View {
        let active = mapState.isActive(species.id)
        let photo = mapState.photosBySpeciesID[species.id]?.first

        return Button {
            mapState.toggleSpecies(species.id)
        } label: {
            SpeciesCardView(species: species, photo: photo, signal: nil, isActiveOnMap: active)
                .overlay(alignment: .topTrailing) {
                    Button {
                        detailSpecies = species
                    } label: {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(DesignSystem.Colors.cloud)
                            .background(Circle().fill(DesignSystem.Colors.forestDeep.opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .padding(DesignSystem.iconButtonPadding)
                }
        }
        .buttonStyle(.plain)
    }
}
