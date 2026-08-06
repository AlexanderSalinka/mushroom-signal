import SwiftUI
import MushroomSignalCore
import os

struct RegionMapView: View {
    @ObservedObject var appState: AppState
    @State private var regionScores: [String: Int] = [:]
    @State private var isLoading = false

    private static let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "RegionMapView")

    // Approximate relative layout of Slovakia's 8 kraje (schematic, not geographically precise).
    private let layout: [[String?]] = [
        ["zilinsky", "zilinsky", "presovsky", "presovsky"],
        ["trenciansky", "banskobystricky", "banskobystricky", "kosicky"],
        ["bratislavsky", "trnavsky", "nitriansky", "kosicky"]
    ]

    var body: some View {
        VStack(spacing: DesignSystem.spacingMedium) {
            Text("Podmienky podľa kraja")
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.cloud)

            VStack(spacing: DesignSystem.spacingSmall / 2) {
                ForEach(0..<layout.count, id: \.self) { row in
                    HStack(spacing: DesignSystem.spacingSmall / 2) {
                        ForEach(0..<layout[row].count, id: \.self) { col in
                            regionCell(id: layout[row][col])
                        }
                    }
                }
            }

            if isLoading {
                ProgressView()
            }

            legend
        }
        .padding(DesignSystem.spacingLarge)
        .background(DesignSystem.Colors.forestDeep)
        .task { await loadAllRegionScores() }
    }

    @ViewBuilder
    private func regionCell(id: String?) -> some View {
        if let id, let region = RegionDatabase.find(id: id) {
            let score = regionScores[id] ?? 0
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3)
                .fill(color(for: score))
                .overlay(
                    Text(region.nameSk.replacingOccurrences(of: " kraj", with: ""))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(4)
                )
                .frame(minWidth: 60, minHeight: 44)
                .onTapGesture { appState.selectRegion(region) }
        } else {
            Color.clear.frame(minWidth: 60, minHeight: 44)
        }
    }

    private func color(for score: Int) -> Color {
        switch score {
        case 3: return DesignSystem.Colors.mossAccent
        case 2: return DesignSystem.Colors.mossAccent.opacity(0.55)
        case 1: return DesignSystem.Colors.bark.opacity(0.6)
        default: return DesignSystem.Colors.bark.opacity(0.3)
        }
    }

    private var legend: some View {
        HStack(spacing: DesignSystem.spacingMedium) {
            legendItem(color: DesignSystem.Colors.mossAccent, label: "Vysoká šanca")
            legendItem(color: DesignSystem.Colors.bark.opacity(0.6), label: "Nízka šanca")
        }
        .font(.caption2)
        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private func loadAllRegionScores() async {
        isLoading = true
        defer { isLoading = false }
        let client = OpenMeteoClient()
        let month = Calendar.current.component(.month, from: Date())
        guard let allSpecies = try? SpeciesDatabase.loadAll() else {
            Self.logger.error("Failed to load species dataset — region map will show no data for any kraj")
            return
        }

        await withTaskGroup(of: (String, Int).self) { group in
            for region in RegionDatabase.all {
                group.addTask {
                    guard let weather = try? await client.fetchSnapshot(for: region) else {
                        Self.logger.error("Weather fetch failed for region \(region.id, privacy: .public)")
                        return (region.id, 0)
                    }
                    let signals = allSpecies
                        .filter { $0.regionalAffinity.contains(region.id) }
                        .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
                    return (region.id, signals.map(\.score).max() ?? 0)
                }
            }
            for await (id, score) in group {
                regionScores[id] = score
            }
        }
    }
}
