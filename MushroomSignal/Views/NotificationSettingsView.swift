import SwiftUI
import MushroomSignalCore

struct NotificationSettingsView: View {
    @StateObject private var state = NotificationSettingsState()
    @Environment(\.dismiss) private var dismiss
    @State private var allSpecies: [Species] = []
    @State private var selectedSpeciesId: String = ""
    @State private var selectedRegionId: String = RegionStore()?.selectedRegion().id ?? RegionStoreConstants.defaultRegionId
    @State private var threshold: Int = 3

    private var filteredSpecies: [Species] {
        allSpecies.filter { $0.regionalAffinity.contains(selectedRegionId) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if state.authorizationStatus != .authorized {
                    Section {
                        Text(state.authorizationStatus == .denied ? "Upozornenia sú zakázané. Povoľte ich v Nastaveniach systému." : "Upozornenia nie sú povolené.")
                            .font(.system(size: DesignSystem.captionSize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.8))
                        if state.authorizationStatus == .notDetermined {
                            Button("Povoliť upozornenia") {
                                Task { await state.requestAuthorizationIfNeeded() }
                            }
                            .tint(DesignSystem.Colors.mossAccent)
                        }
                    }
                }

                Section("Pridať sledovanie") {
                    Picker("Kraj", selection: $selectedRegionId) {
                        ForEach(RegionDatabase.all) { region in
                            Text(region.nameSk).tag(region.id)
                        }
                    }
                    Picker("Druh", selection: $selectedSpeciesId) {
                        ForEach(filteredSpecies) { species in
                            Text(species.commonNameSk).tag(species.id)
                        }
                    }
                    Picker("Prah", selection: $threshold) {
                        ForEach(1...4, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Button("Pridať") {
                        guard !selectedSpeciesId.isEmpty else { return }
                        state.addOrUpdateWatch(speciesId: selectedSpeciesId, regionId: selectedRegionId, threshold: threshold)
                    }
                    .tint(DesignSystem.Colors.mossAccent)
                }

                Section("Sledované druhy") {
                    ForEach(state.watchedAlerts) { alert in
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                                Text(allSpecies.first { $0.id == alert.speciesId }?.commonNameSk ?? alert.speciesId)
                                    .font(.system(size: DesignSystem.bodySize))
                                Text(RegionDatabase.find(id: alert.regionId)?.nameSk ?? alert.regionId)
                                    .font(.system(size: DesignSystem.captionSize))
                                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            }
                            Spacer()
                            Text("≥\(alert.threshold)")
                                .font(.system(size: DesignSystem.captionSize))
                                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            Button {
                                state.removeWatch(alert)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .tint(DesignSystem.Colors.danger)
                            .help("Odstrániť sledovanie")
                        }
                        .swipeActions {
                            Button("Odstrániť", role: .destructive) {
                                state.removeWatch(alert)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upozornenia")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavrieť") { dismiss() }
                }
            }
            .task {
                allSpecies = (try? SpeciesDatabase.loadAll()) ?? []
                if selectedSpeciesId.isEmpty {
                    selectedSpeciesId = filteredSpecies.first?.id ?? ""
                }
                await state.refreshAuthorizationStatus()
            }
            .onChange(of: selectedRegionId) { _, _ in
                if !filteredSpecies.contains(where: { $0.id == selectedSpeciesId }) {
                    selectedSpeciesId = filteredSpecies.first?.id ?? ""
                }
            }
        }
    }
}
