import SwiftUI
import MushroomSignalCore

struct MapScreenView: View {
    @StateObject private var mapState = MapScreenState()

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.spacingLarge) {
                InteractiveMapView(mapState: mapState)
                    .containerRelativeFrame(.vertical) { height, _ in
                        max(height * DesignSystem.mapDominantHeightFraction, DesignSystem.mapMinimumHeight)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))

                SpeciesLibraryView(mapState: mapState)
            }
            .padding(DesignSystem.spacingLarge)
        }
        .background(DesignSystem.Colors.forestDeep)
    }
}
