import SwiftUI
import MushroomSignalCore

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var selectedTab: Tab = .shortlist
    @State private var showingNotificationSettings = false

    enum Tab {
        case shortlist
        case map
        case forecast
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                ShortlistView(appState: appState)
                    .tabItem { Label("Zoznam", systemImage: "list.bullet") }
                    .tag(Tab.shortlist)

                MapScreenView(regionId: appState.selectedRegion.id)
                    .tabItem { Label("Mapa", systemImage: "map") }
                    .tag(Tab.map)

                PredpovedView(regionId: appState.selectedRegion.id, appState: appState)
                    .tabItem { Label("Predpoveď", systemImage: "cloud.sun") }
                    .tag(Tab.forecast)
            }
            .navigationTitle("Mushroom Signal")
            .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    RegionPickerView(appState: appState)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        Label("Obnoviť", systemImage: "arrow.clockwise")
                    }
                    .disabled(appState.isLoading)
                    .help("Obnoviť údaje o počasí")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingNotificationSettings = true
                    } label: {
                        Label("Upozornenia", systemImage: "gearshape")
                    }
                    .help("Nastavenia upozornení")
                }
            }
        }
        .task { await appState.refresh() }
        .frame(minWidth: 420, minHeight: 480)
        .background(WindowTransparencyConfigurator())
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView()
        }
    }
}
