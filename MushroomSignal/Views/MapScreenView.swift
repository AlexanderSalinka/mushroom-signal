import SwiftUI
import MushroomSignalCore

struct MapScreenView: View {
    let regionId: String
    @StateObject private var mapState = MapScreenState()
    @State private var mapHeight: CGFloat = DesignSystem.mapDefaultHeight

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.spacingSmall) {
                InteractiveMapView(mapState: mapState)
                    .frame(height: mapHeight)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))

                MapResizeHandle(height: $mapHeight)

                SpeciesLibraryView(mapState: mapState, regionId: regionId)
                    .padding(.top, DesignSystem.spacingMedium - DesignSystem.spacingSmall)
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
    }
}
