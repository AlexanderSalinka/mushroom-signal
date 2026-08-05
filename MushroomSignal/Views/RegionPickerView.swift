import SwiftUI
import MushroomSignalCore

struct RegionPickerView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Picker("Kraj", selection: Binding(
            get: { appState.selectedRegion },
            set: { appState.selectRegion($0) }
        )) {
            ForEach(RegionDatabase.all) { region in
                Text(region.nameSk).tag(region)
            }
        }
        .pickerStyle(.menu)
    }
}
