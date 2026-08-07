// MushroomSignal/Views/ShortlistView.swift
import SwiftUI
import MushroomSignalCore

struct ShortlistView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                if let error = appState.errorMessage {
                    Text(error)
                        .foregroundStyle(appState.isShowingStaleData ? DesignSystem.Colors.caution : DesignSystem.Colors.danger)
                }

                ForEach(appState.signals, id: \.species.id) { signal in
                    signalRow(signal)
                }

                disclaimer
            }
            .padding(DesignSystem.spacingLarge)
        }
        .background(DesignSystem.Colors.forestDeep)
        .refreshable { await appState.refresh() }
    }

    private func signalRow(_ signal: SpeciesSignal) -> some View {
        let clampedScore = max(0, min(4, signal.score))
        return VStack(alignment: .leading, spacing: DesignSystem.spacingSmall / 2) {
            HStack {
                Text(signal.species.commonNameSk)
                    .font(.system(size: DesignSystem.titleSize, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                Spacer()
                Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 4 - clampedScore))
                    .foregroundStyle(DesignSystem.Colors.mossAccent)
            }
            Text(signal.species.latinName)
                .font(.system(size: DesignSystem.captionSize))
                .italic()
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if let reason = signal.reason {
                Text(reason)
                    .font(.system(size: DesignSystem.captionSize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            }
            if let warning = DesignSystem.warningLabelSk(for: signal.species.edibility) {
                Text(warning)
                    .font(.system(size: DesignSystem.captionSize, weight: .bold))
                    .foregroundStyle(DesignSystem.warningColor(for: signal.species.edibility))
            }
        }
        .padding(DesignSystem.spacingMedium)
        .background(DesignSystem.Colors.forestMid.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))
    }

    private var disclaimer: some View {
        Text("Tento zoznam je len orientačný odhad na základe počasia a sezóny. Pred zberom a konzumáciou húb si nález vždy overte s odborníkom alebo v spoľahlivom atlase húb.")
            .font(.system(size: DesignSystem.captionSize))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            .padding(.top, DesignSystem.spacingMedium)
    }
}
