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

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $cameraPosition) {
                // Always-visible kraj borders, no fill — per
                // docs/superpowers/specs/2026-08-08-map-region-scoping-design.md §3. The
                // region-scoped fill (only the selected kraj filled with the dominant
                // species color) is separate, still-pending work — this is just the
                // permanent administrative-context layer. Each kraj gets its own distinct
                // outline color (DesignSystem.Colors.regionPalette) so regions are
                // identifiable by border color alone, at a glance.
                ForEach(Array(RegionDatabase.all.enumerated()), id: \.element.id) { index, region in
                    if let boundary = RegionBoundaries.polygon(for: region.id) {
                        MapPolygon(coordinates: boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                            .foregroundStyle(.clear)
                            .stroke(DesignSystem.Colors.regionPalette[index % DesignSystem.Colors.regionPalette.count], lineWidth: 1.5)
                    }
                }

                ForEach(mapState.gridPoints) { point in
                    if let signal = mapState.dominantSignal(at: point.id), let color = mapState.speciesColors[signal.species.id] {
                        Annotation(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)) {
                            ScoreDotsView(score: signal.score, color: color, dotSize: DesignSystem.mapMarkerDotSize)
                                .padding(.horizontal, DesignSystem.spacingTight)
                                .padding(.vertical, DesignSystem.spacingTight / 2)
                                .background(Capsule().fill(DesignSystem.Colors.forestDeep.opacity(0.85)))
                        } label: { EmptyView() }
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
