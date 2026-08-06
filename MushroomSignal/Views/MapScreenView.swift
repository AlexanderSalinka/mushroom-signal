import SwiftUI
import MushroomSignalCore

struct MapScreenView: View {
    @StateObject private var mapState = MapScreenState()

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.spacingLarge) {
                InteractiveMapView(mapState: mapState)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))

                SpeciesLibraryView(mapState: mapState)
            }
            .padding(DesignSystem.spacingLarge)
        }
        .background(DesignSystem.Colors.forestDeep)
    }
}
