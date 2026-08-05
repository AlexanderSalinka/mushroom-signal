// MushroomSignal/Views/ShortlistView.swift
import SwiftUI
import MushroomSignalCore

struct ShortlistView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                if let error = appState.errorMessage {
                    Text(error).foregroundStyle(.red)
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
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall / 2) {
            HStack {
                Text(signal.species.commonNameSk)
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.cloud)
                Spacer()
                Text(String(repeating: "●", count: signal.score) + String(repeating: "○", count: 3 - signal.score))
                    .foregroundStyle(DesignSystem.Colors.mossAccent)
            }
            Text(signal.species.latinName)
                .font(.caption)
                .italic()
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if let reason = signal.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            }
            if signal.species.edibility == .poisonous {
                Text("⚠️ Jedovatá")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
            }
        }
        .padding(DesignSystem.spacingMedium)
        .background(DesignSystem.Colors.forestMid.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))
    }

    private var disclaimer: some View {
        Text("Tento zoznam je len orientačný odhad na základe počasia a sezóny. Pred zberom a konzumáciou húb si nález vždy overte s odborníkom alebo v spoľahlivom atlase húb.")
            .font(.caption2)
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            .padding(.top, DesignSystem.spacingMedium)
    }
}
