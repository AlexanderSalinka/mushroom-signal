import WidgetKit
import SwiftUI
import MushroomSignalCore

struct ShortlistEntry: TimelineEntry {
    let date: Date
    let region: Region
    let signals: [SpeciesSignal]
}

struct ShortlistProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShortlistEntry {
        ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ShortlistEntry) -> Void) {
        completion(ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: []))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortlistEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            let nextRefresh = Calendar.current.date(byAdding: .hour, value: 12, to: Date()) ?? Date().addingTimeInterval(12 * 3600)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func buildEntry() async -> ShortlistEntry {
        let region = RegionStore()?.selectedRegion() ?? RegionDatabase.all[0]

        do {
            let weather = try await OpenMeteoClient().fetchSnapshot(for: region)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let signals = allSpecies
                .filter { $0.regionalAffinity.contains(region.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            let shortlist = ShortlistRanker.topSpecies(from: signals, limit: 3)
            return ShortlistEntry(date: Date(), region: region, signals: shortlist)
        } catch {
            return ShortlistEntry(date: Date(), region: region, signals: [])
        }
    }
}

struct MushroomSignalWidget: Widget {
    let kind: String = "MushroomSignalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShortlistProvider()) { entry in
            ShortlistWidgetView(entry: entry)
        }
        .configurationDisplayName("Mushroom Signal")
        .description("Aktuálne huby vo vašom kraji")
        .supportedFamilies([.systemSmall])
    }
}
