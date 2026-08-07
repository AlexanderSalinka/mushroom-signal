import SwiftUI
import MapKit
import MushroomSignalCore

struct InteractiveMapView: View {
    @ObservedObject var mapState: MapScreenState

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.65, longitude: 19.7),
            span: MKCoordinateSpan(latitudeDelta: 2.6, longitudeDelta: 6.6)
        )
    )

    /// Circle radius chosen so ~39 grid points visually tile Slovakia without large gaps.
    private let gridPointRadiusMeters: CLLocationDistance = 18000

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $cameraPosition) {
                ForEach(mapState.gridPoints) { point in
                    MapCircle(center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), radius: gridPointRadiusMeters)
                        .foregroundStyle(color(for: point))
                        .stroke(.clear)
                }
                // Always-visible kraj borders, no fill — per
                // docs/superpowers/specs/2026-08-08-map-region-scoping-design.md §3. The
                // region-scoped fill (only the selected kraj filled with the dominant
                // species color) is separate, still-pending work — this is just the
                // permanent administrative-context layer.
                ForEach(RegionDatabase.all) { region in
                    if let boundary = RegionBoundaries.polygon(for: region.id) {
                        MapPolygon(coordinates: boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                            .foregroundStyle(.clear)
                            .stroke(DesignSystem.Colors.cloud.opacity(0.6), lineWidth: 1.25)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))

            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                if mapState.isLoading {
                    ProgressView().padding(DesignSystem.spacingSmall)
                }
                if let error = mapState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(DesignSystem.Colors.danger)
                        .padding(DesignSystem.spacingSmall)
                        .background(DesignSystem.Colors.forestDeep.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
                }
                legend
            }
            .padding(DesignSystem.spacingMedium)
        }
        .task { await mapState.loadGrid() }
    }

    private func color(for point: GridPoint) -> Color {
        guard let dominant = mapState.dominantSpecies(at: point.id), let assigned = mapState.speciesColors[dominant.id] else {
            return DesignSystem.Colors.bark.opacity(0.3)
        }
        return assigned.opacity(0.75)
    }

    @ViewBuilder
    private var legend: some View {
        if !mapState.activeSpeciesOrder.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                ForEach(mapState.activeSpeciesOrder, id: \.self) { id in
                    if let species = mapState.allSpecies.first(where: { $0.id == id }), let color = mapState.speciesColors[id] {
                        HStack(spacing: DesignSystem.spacingTight * 2) {
                            Circle().fill(color).frame(width: DesignSystem.legendDotSize, height: DesignSystem.legendDotSize)
                            Text(species.commonNameSk)
                                .font(.system(size: DesignSystem.captionSize))
                                .foregroundStyle(DesignSystem.Colors.cloud)
                        }
                    }
                }
            }
            .padding(DesignSystem.spacingSmall)
            .background(DesignSystem.Colors.forestDeep.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
        }
    }
}
