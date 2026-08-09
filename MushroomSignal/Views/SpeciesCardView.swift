// MushroomSignal/Views/SpeciesCardView.swift
import SwiftUI
import MushroomSignalCore

/// One shared card, used by both Zoznam's shortlist grid and Mapa's species library grid —
/// same visual identity everywhere. `signal` carries score/reason for Zoznam's forecast
/// context; pass `nil` for library-context cards where only identity (name, photo, active
/// state) matters, not a live forecast.
struct SpeciesCardView: View {
    let species: Species
    let photo: SpeciesPhoto?
    let signal: SpeciesSignal?
    let isActiveOnMap: Bool?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: photo?.imageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    DesignSystem.Colors.bark.opacity(0.4)
                    Image(systemName: "photo")
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
                }
            }
            .frame(height: DesignSystem.speciesCardPhotoHeight)
            .clipped()

            LinearGradient(
                colors: [.clear, DesignSystem.Colors.forestDeep.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                Text(species.commonNameSk)
                    .font(.system(size: DesignSystem.bodySize, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                    .lineLimit(1)
                Text(species.latinName)
                    .font(.system(size: DesignSystem.captionSize).italic())
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                    .lineLimit(1)

                if let signal {
                    let clampedScore = max(0, min(4, signal.score))
                    Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 4 - clampedScore))
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(DesignSystem.Colors.mossAccent)
                    if let reason = signal.reason {
                        Text(reason)
                            .font(.system(size: DesignSystem.captionSize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            .lineLimit(2)
                    }
                }

                if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                    Text(warning)
                        .font(.system(size: DesignSystem.captionSize, weight: .bold))
                        .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                }
            }
            .padding(DesignSystem.spacingSmall)
        }
        .background(DesignSystem.Colors.forestMid)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2)
                .stroke(isActiveOnMap == true ? DesignSystem.Colors.mossAccent : .clear, lineWidth: DesignSystem.borderWidth)
        )
    }
}
