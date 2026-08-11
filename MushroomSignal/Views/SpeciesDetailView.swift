// MushroomSignal/Views/SpeciesDetailView.swift
import SwiftUI
import Charts
import MushroomSignalCore

struct SpeciesDetailView: View {
    let species: Species
    let photos: [SpeciesPhoto]
    let regionId: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingCredits = false
    @StateObject private var trendState = SpeciesTrendState()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                    if !photos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: DesignSystem.spacingSmall) {
                                ForEach(photos) { photo in
                                    CachedAsyncImage(url: photo.imageURL) { image in
                                        image.resizable().aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        DesignSystem.Colors.bark.opacity(0.4)
                                    }
                                    .frame(width: DesignSystem.detailPhotoWidth, height: DesignSystem.detailPhotoHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
                                }
                            }
                        }
                    }

                    Text(species.commonNameSk)
                        .font(.system(size: DesignSystem.heroSize, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                    Text(species.latinName)
                        .font(.system(size: DesignSystem.bodySize))
                        .italic()
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))

                    if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                        Text(warning)
                            .font(.system(size: DesignSystem.bodySize, weight: .bold))
                            .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                    }

                    if !trendState.points.isEmpty {
                        trendChart
                    }

                    detailRow(title: "Biotop", value: species.habitat)
                    if !species.lookAlikes.isEmpty {
                        detailRow(title: "Zámena s", value: species.lookAlikes.joined(separator: ", "))
                    }

                    if !photos.isEmpty {
                        Button("Zdroje fotografií") { showingCredits = true }
                            .font(.system(size: DesignSystem.captionSize))
                    }
                }
                .padding(DesignSystem.spacingLarge)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavrieť") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCredits) {
                PhotoCreditsView(photos: photos)
            }
        }
        .task { await trendState.load(species: species, regionId: regionId) }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Trend")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Chart(trendState.points, id: \.date) { point in
                LineMark(x: .value("Deň", point.date), y: .value("Skóre", point.score))
                    .foregroundStyle(DesignSystem.Colors.mossAccent)
                PointMark(x: .value("Deň", point.date), y: .value("Skóre", point.score))
                    .foregroundStyle(DesignSystem.Colors.mossAccent.opacity(point.isForecast ? 0.5 : 1.0))
            }
            .chartYScale(domain: 0...4)
            .frame(height: DesignSystem.trendChartHeight)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text(title)
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Text(value)
                .font(.system(size: DesignSystem.bodySize))
                .foregroundStyle(DesignSystem.Colors.cloud)
        }
    }
}
