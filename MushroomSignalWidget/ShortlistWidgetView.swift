// MushroomSignalWidget/ShortlistWidgetView.swift
import SwiftUI
import WidgetKit
import MushroomSignalCore

struct ShortlistWidgetView: View {
    let entry: ShortlistEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            Text(entry.region.nameSk)
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))

            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals, id: \.species.id) { signal in
                    let clampedScore = max(0, min(3, signal.score))
                    let hasWarning = signal.species.edibility != .edible
                    let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
                    HStack {
                        Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
                            .lineLimit(1)
                        Spacer()
                        Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.mossAccent)
                    }
                }
                if entry.signals.isEmpty {
                    Text("Žiadne údaje")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                }
            }

            Spacer(minLength: 0)

            if entry.signals.contains(where: { $0.species.edibility == .poisonous }) {
                Text("⚠️ obsahuje jedovaté")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.danger)
                    .lineLimit(1)
            } else {
                Text(entry.date, style: .time)
                    .font(.system(size: 8))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            }
        }
        .padding(DesignSystem.spacingMedium)
        .containerBackground(for: .widget) {
            DesignSystem.Colors.cardBackground
        }
    }
}

#Preview(as: .systemSmall) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [])
}
