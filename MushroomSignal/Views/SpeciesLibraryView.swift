// MushroomSignal/Views/SpeciesLibraryView.swift
import SwiftUI
import MushroomSignalCore

struct SpeciesLibraryView: View {
    @ObservedObject var mapState: MapScreenState
    @State private var columnCount = 3
    @State private var detailSpecies: Species?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DesignSystem.spacingSmall), count: columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            HStack {
                Text("Knižnica druhov")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.cloud)
                Spacer()
                Stepper("Stĺpce: \(columnCount)", value: $columnCount, in: 2...4)
                    .fixedSize()
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.8))
            }

            LazyVGrid(columns: columns, spacing: DesignSystem.spacingSmall) {
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

        return VStack(spacing: DesignSystem.spacingTight * 2) {
            ZStack(alignment: .topTrailing) {
                photoThumbnail(photo)
                Button {
                    detailSpecies = species
                } label: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.cloud)
                        .background(Circle().fill(DesignSystem.Colors.forestDeep.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(4)
            }

            Text(species.commonNameSk)
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.cloud)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.spacingSmall)
        .background(active ? DesignSystem.Colors.mossAccent.opacity(0.35) : DesignSystem.Colors.forestMid.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3)
                .stroke(active ? DesignSystem.Colors.mossAccent : .clear, lineWidth: 2)
        )
        .onTapGesture { mapState.toggleSpecies(species.id) }
    }

    @ViewBuilder
    private func photoThumbnail(_ photo: SpeciesPhoto?) -> some View {
        if let photo {
            AsyncImage(url: photo.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 4))
        } else {
            placeholder.frame(height: 70)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 4)
            .fill(DesignSystem.Colors.bark.opacity(0.4))
            .overlay(Image(systemName: "photo").foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5)))
    }
}
