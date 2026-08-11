// MushroomSignal/Views/CompactSpeciesCardView.swift
import SwiftUI
import MushroomSignalCore

/// The forest redesign's compact "glass button" species card — small, roughly square,
/// fixed size regardless of window/grid resize. Distinct from `SpeciesCardView`
/// (Zoznam/Mapa's larger photo-backed grid cards, unaffected by this redesign).
///
/// Deliberate exception to the app-wide 20pt text floor (`DesignSystem.captionSize`, see
/// DesignSystem.swift ~line 16-21): this card's rank badge, name, latin name, and warning
/// text all render below 20pt. Its 120×120pt footprint is locked to the approved mockup and
/// can't fit floor-sized text for all four elements at once. Accepted tradeoff, explicitly
/// approved by Alexander 2026-08-11 — not an oversight.
struct CompactSpeciesCardView: View {
    let species: Species
    let signal: SpeciesSignal?
    let rank: Int?
    let photo: SpeciesPhoto?

    private var isWarning: Bool { species.edibility != .edible }
    private var accentColor: Color {
        isWarning ? DesignSystem.warningColor(for: species.edibility) : DesignSystem.Colors.mossAccent
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CachedAsyncImage(url: photo?.imageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    DesignSystem.Colors.bark
                    Image(systemName: "photo")
                        .font(.system(size: DesignSystem.compactCardSize * 0.28))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
                }
            }
            .frame(width: DesignSystem.compactCardSize, height: DesignSystem.compactCardSize)
            .clipped()

            LinearGradient(
                colors: [.clear, DesignSystem.Colors.forestDeep.opacity(0.95)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: DesignSystem.compactCardSize, height: DesignSystem.compactCardSize)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    if let rank {
                        Text("\(rank)")
                            .font(.system(size: DesignSystem.captionSize * 0.6, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                            .frame(width: DesignSystem.compactCardBadgeSize, height: DesignSystem.compactCardBadgeSize)
                            .background(Circle().fill(accentColor.opacity(0.28)))
                    }
                    Spacer()
                    if signal?.flushTriggered == true {
                        SunriseShape()
                            .stroke(DesignSystem.Colors.caution, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .frame(width: 11, height: 11)
                            .frame(width: DesignSystem.compactCardBadgeSize, height: DesignSystem.compactCardBadgeSize)
                            .background(Circle().fill(DesignSystem.Colors.caution.opacity(0.22)))
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(species.commonNameSk)
                        .font(.system(size: DesignSystem.captionSize * 0.55, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                        .lineLimit(2)
                    Text(species.latinName)
                        .font(.system(size: DesignSystem.captionSize * 0.45).italic())
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.55))
                        .lineLimit(1)
                    if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                        Text(warning)
                            .font(.system(size: DesignSystem.captionSize * 0.5, weight: .bold))
                            .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                            .lineLimit(1)
                    }
                    if let signal {
                        ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize * 0.4)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: DesignSystem.compactCardSize, height: DesignSystem.compactCardSize)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.58))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.58)
                .stroke(isWarning ? DesignSystem.warningColor(for: species.edibility).opacity(0.4) : DesignSystem.Colors.cloud.opacity(0.16), lineWidth: 1)
        )
    }
}
