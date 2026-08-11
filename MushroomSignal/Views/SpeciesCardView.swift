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
                    ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize)
                    if let reason = signal.reason {
                        HStack(alignment: .top, spacing: 4) {
                            if signal.flushTriggered {
                                SunriseShape()
                                    .stroke(DesignSystem.Colors.caution, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                    .frame(width: 12, height: 12)
                                    .padding(.top, 2)
                            }
                            Text(reason)
                                .font(.system(size: DesignSystem.captionSize))
                                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                                .lineLimit(2)
                        }
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
        // Explicit total-card height, not just the photo's — without this the ZStack's height
        // was inferred from its children, giving the grid an ambiguous answer to "how tall is
        // this cell?" that drifted between layout and hit-testing, misplacing tap regions
        // (confirmed present in both LazyVGrid and non-lazy Grid, so the grid wasn't the cause).
        .frame(height: DesignSystem.speciesCardPhotoHeight)
        .background(DesignSystem.Colors.forestMid)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2)
                .stroke(isActiveOnMap == true ? DesignSystem.Colors.mossAccent : .clear, lineWidth: DesignSystem.borderWidth)
        )
    }
}
