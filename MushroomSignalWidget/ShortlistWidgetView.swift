// MushroomSignalWidget/ShortlistWidgetView.swift
import SwiftUI
import WidgetKit
import MushroomSignalCore

struct ShortlistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShortlistEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            case .systemLarge:
                largeBody
            default:
                smallBody
            }
        }
        .padding(DesignSystem.spacingMedium)
        .containerBackground(for: .widget) {
            DesignSystem.Colors.cardBackground
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            regionHeader
            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals, id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.bodySize, weight: .semibold), showLatin: false)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            regionHeader
            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals, id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.bodySize, weight: .semibold), showLatin: false, inlineLatin: true)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
            regionHeader
            if let hero = entry.signals.first {
                heroRow(for: hero)
            }
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                ForEach(entry.signals.dropFirst(), id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.titleSize, weight: .semibold), showLatin: true)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var regionHeader: some View {
        Text(entry.region.nameSk)
            .font(.caption2)
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
    }

    @ViewBuilder
    private var emptyStateIfNeeded: some View {
        if entry.signals.isEmpty {
            Text("Žiadne údaje")
                .font(.system(size: DesignSystem.bodySize))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
        }
    }

    private var footer: some View {
        Group {
            if entry.signals.contains(where: { $0.species.edibility == .poisonous }) {
                Text("⚠️ obsahuje jedovaté")
                    .font(.system(size: DesignSystem.captionSize, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.danger)
                    .lineLimit(1)
            } else {
                Text(entry.date, style: .time)
                    .font(.system(size: DesignSystem.captionSize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            }
        }
    }

    /// - Parameter inlineLatin: When true (medium layout only), the latin name is appended inline after
    ///   the common name on the same line, using medium's extra width instead of a second line of height.
    ///   Mutually exclusive with `showLatin` (large's two-line form) in practice, but not enforced structurally.
    private func row(for signal: SpeciesSignal, nameFont: Font, showLatin: Bool, inlineLatin: Bool = false) -> some View {
        let clampedScore = max(0, min(3, signal.score))
        let hasWarning = signal.species.edibility != .edible
        let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
        let nameText = Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
            .font(nameFont)
            .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
        let latinText = Text(" · " + signal.species.latinName)
            .font(.system(size: DesignSystem.captionSize).italic())
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
        return HStack {
            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                if inlineLatin {
                    (nameText + latinText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    nameText
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if showLatin {
                        Text(signal.species.latinName)
                            .font(.system(size: DesignSystem.captionSize).italic())
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            Spacer()
            Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
                .font(.system(size: DesignSystem.captionSize))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
    }

    private func heroRow(for signal: SpeciesSignal) -> some View {
        let clampedScore = max(0, min(3, signal.score))
        let hasWarning = signal.species.edibility != .edible
        let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
        return VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                .font(.system(size: DesignSystem.heroSize, weight: .bold))
                .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(signal.species.latinName)
                .font(.system(size: DesignSystem.bodySize).italic())
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
                .font(.system(size: DesignSystem.titleSize))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
    }
}

private func previewSignal(name: String, latin: String, edibility: Edibility, score: Int) -> SpeciesSignal {
    SpeciesSignal(
        species: Species(
            id: name,
            commonNameSk: name,
            latinName: latin,
            edibility: edibility,
            fruitingMonths: [8, 9, 10],
            idealTempMinC: 8,
            idealTempMaxC: 18,
            idealHumidityMinPercent: 60,
            idealHumidityMaxPercent: 90,
            rainfallSensitivity: .medium,
            habitat: "listnatý les",
            regionalAffinity: [RegionDatabase.all[4].id]
        ),
        score: score,
        reason: nil
    )
}

#Preview("Small", as: .systemSmall) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ])
}

#Preview("Medium", as: .systemMedium) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ])
}

#Preview("Large", as: .systemLarge) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Plávka zelenkastá", latin: "Russula virescens", edibility: .caution, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ])
}
