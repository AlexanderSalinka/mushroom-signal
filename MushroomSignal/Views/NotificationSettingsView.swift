import SwiftUI
import MushroomSignalCore

struct NotificationSettingsView: View {
    @StateObject private var state = NotificationSettingsState()
    @Environment(\.dismiss) private var dismiss
    @State private var allSpecies: [Species] = []
    @State private var selectedSpeciesId: String = ""
    @State private var selectedRegionId: String = RegionDatabase.all[0].id
    @State private var threshold: Int = 3

    var body: some View {
        NavigationStack {
            Form {
                if state.authorizationStatus != .authorized {
                    Section {
                        Text("Upozornenia nie sú povolené.")
                        Button("Povoliť upozornenia") {
                            Task { await state.requestAuthorizationIfNeeded() }
                        }
                    }
                }

                Section("Pridať sledovanie") {
                    Picker("Druh", selection: $selectedSpeciesId) {
                        ForEach(allSpecies) { species in
                            Text(species.commonNameSk).tag(species.id)
                        }
                    }
                    Picker("Kraj", selection: $selectedRegionId) {
                        ForEach(RegionDatabase.all) { region in
                            Text(region.nameSk).tag(region.id)
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
                }

                Section("Sledované druhy") {
                    ForEach(state.watchedAlerts) { alert in
                        HStack {
                            Text(allSpecies.first { $0.id == alert.speciesId }?.commonNameSk ?? alert.speciesId)
                            Spacer()
                            Text(RegionDatabase.find(id: alert.regionId)?.nameSk ?? alert.regionId)
                                .foregroundStyle(.secondary)
                            Text("≥\(alert.threshold)")
                                .foregroundStyle(.secondary)
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
                if let first = allSpecies.first, selectedSpeciesId.isEmpty {
                    selectedSpeciesId = first.id
                }
                await state.refreshAuthorizationStatus()
            }
        }
    }
}
