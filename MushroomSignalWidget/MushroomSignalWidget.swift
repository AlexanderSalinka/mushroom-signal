import WidgetKit
import SwiftUI
import MushroomSignalCore
import os

private let widgetLogger = Logger(subsystem: "com.alexandersalinka.MushroomSignal.Widget", category: "TimelineProvider")

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
        let limit = context.family == .systemLarge ? 4 : 3
        Task {
            let entry = await buildEntry(limit: limit)
            let nextRefresh = Calendar.current.date(byAdding: .hour, value: 12, to: Date()) ?? Date().addingTimeInterval(12 * 3600)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func buildEntry(limit: Int) async -> ShortlistEntry {
        guard let store = RegionStore() else {
            widgetLogger.error("RegionStore unavailable — App Group entitlement missing or misconfigured; using default region")
            return await fetchEntry(region: RegionDatabase.all[0], limit: limit)
        }
        return await fetchEntry(region: store.selectedRegion(), limit: limit)
    }

    private func fetchEntry(region: Region, limit: Int) async -> ShortlistEntry {
        do {
            let weather = try await OpenMeteoClient().fetchSnapshot(for: region)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let signals = allSpecies
                .filter { $0.regionalAffinity.contains(region.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            let shortlist = ShortlistRanker.topSpecies(from: signals, limit: limit)
            return ShortlistEntry(date: Date(), region: region, signals: shortlist)
        } catch {
            widgetLogger.error("Timeline refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
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
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
