// MushroomSignal/Views/PredpovedView.swift
import SwiftUI
import Charts
import MushroomSignalCore
import os

private let predpovedLogger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "PredpovedView")

struct PredpovedView: View {
    let regionId: String
    @ObservedObject var appState: AppState
    @StateObject private var weatherState = RegionWeatherState()
    @State private var allSpecies: [Species] = []
    @State private var photosBySpeciesID: [String: [SpeciesPhoto]] = [:]

    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }

    private var inSeasonSpecies: [Species] {
        let month = Calendar.current.component(.month, from: Date())
        return allSpecies
            .filter { $0.regionalAffinity.contains(regionId) }
            .filter { SignalAlgorithm.calendarFit(species: $0, month: month) > 0 }
            .sorted { $0.commonNameSk.localizedStandardCompare($1.commonNameSk) == .orderedAscending }
    }

    private var rankedInSeasonSpecies: [Species] {
        let scoreById = Dictionary(uniqueKeysWithValues: appState.signals.map { ($0.species.id, $0.score) })
        return inSeasonSpecies.sorted { (scoreById[$0.id] ?? 0) > (scoreById[$1.id] ?? 0) }
    }

    private var visibleTopSignals: [SpeciesSignal] {
        Array(appState.signals.filter { $0.score > 0 }.prefix(4))
    }

    private func slovakDayWord(_ count: Int) -> String {
        switch count {
        case 1: return "deň"
        case 2...4: return "dni"
        default: return "dní"
        }
    }

    private var upcomingRainEvent: RainEvent? {
        UpcomingRainDetector.nextTriggerEvent(in: weatherState.dailyWeather, asOf: Date())
    }

    private var nearMissInsight: NearMissRainInsight.Case? {
        guard upcomingRainEvent == nil else { return nil }
        return NearMissRainInsight.describe(in: weatherState.dailyWeather, asOf: Date())
    }

    private func nearMissText(for insight: NearMissRainInsight.Case) -> String {
        switch insight {
        case .rainWithoutHeat(let date, let precipitationMm, _):
            let daysUntil = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 1)
            return "O \(daysUntil) \(slovakDayWord(daysUntil)) mierny dážď (\(String(format: "%.0f", precipitationMm)) mm), ale bez dostatočného tepla na nárast rastu."
        case .heatWithoutRain(let date, _, let maxTempC):
            let daysUntil = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 1)
            return "O \(daysUntil) \(slovakDayWord(daysUntil)) teplo (\(Int(maxTempC.rounded()))°C), ale bez výraznejšieho dažďa."
        }
    }

    private var rainIncomingSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Blíži sa dážď")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if let event = upcomingRainEvent {
                let daysUntil = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: event.date)).day ?? 1)
                HStack(spacing: 11) {
                    DropletShape()
                        .stroke(DesignSystem.Colors.water, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DesignSystem.Colors.water.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("O \(daysUntil) \(slovakDayWord(daysUntil)) · \(String(format: "%.0f", event.precipitationMm)) mm dažďa a \(Int(event.maxTempC.rounded()))°C")
                            .font(.system(size: DesignSystem.captionSize * 0.65, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.cloud)
                        Text("Dážď aj teplo spolu — sleduj skóre o 4–9 dní")
                            .font(.system(size: DesignSystem.captionSize * 0.55))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.65))
                    }
                }
                .padding(11)
                .background(DesignSystem.Colors.water.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.55)
                        .stroke(DesignSystem.Colors.water.opacity(0.4), lineWidth: 1)
                )
            } else if weatherState.isLoading {
                Text("Načítavam predpoveď…")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else if weatherState.errorMessage != nil {
                Text("Predpoveď nie je k dispozícii.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else if let nearMiss = nearMissInsight {
                Text(nearMissText(for: nearMiss))
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else {
                Text("Žiadny výraznejší dážď v predpovedi.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                if let error = appState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(appState.isShowingStaleData ? DesignSystem.Colors.caution : DesignSystem.Colors.danger)
                }
                if let error = weatherState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(DesignSystem.Colors.danger)
                }

                heroSection
                ForestPanel { WeatherRainChartView(dailyWeather: weatherState.dailyWeather, today: Date()) }
                if !visibleTopSignals.isEmpty {
                    ForestPanel { topPicksSection }
                }
                ForestPanel { rainIncomingSection }
                ForestPanel { seasonCalendarSection }
                disclaimer
            }
            .padding(DesignSystem.spacingLarge)
        }
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
        .task {
            do {
                allSpecies = try SpeciesDatabase.loadAll()
            } catch {
                predpovedLogger.error("Failed to load species dataset: \(String(describing: error), privacy: .public)")
            }
        }
        .task {
            photosBySpeciesID = (try? SpeciesPhotoDatabase.loadAll()).map { Dictionary(grouping: $0, by: \.speciesId) } ?? [:]
        }
    }

    private var topPicksSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Odporúčané dnes")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: DesignSystem.compactCardSize, maximum: DesignSystem.compactCardSize), spacing: DesignSystem.spacingSmall)],
                spacing: DesignSystem.spacingSmall
            ) {
                ForEach(Array(visibleTopSignals.enumerated()), id: \.element.species.id) { index, signal in
                    CompactSpeciesCardView(species: signal.species, signal: signal, rank: index + 1, photo: photosBySpeciesID[signal.species.id]?.first)
                }
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            if let today = todayEntry {
                Text("\(Int(today.minTempC.rounded()))° / \(Int(today.maxTempC.rounded()))°")
                    .font(.system(size: DesignSystem.heroSize, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                HStack(spacing: 5) {
                    DropletShape()
                        .stroke(DesignSystem.Colors.water, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 12)
                    Text("Vlhkosť \(Int(today.humidityPercent.rounded()))% · Zrážky \(String(format: "%.1f", today.precipitationMm)) mm")
                        .font(.system(size: DesignSystem.bodySize))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                }
            } else if weatherState.isLoading {
                Text("Načítavam počasie…")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else if weatherState.errorMessage == nil {
                Text("Žiadne údaje o počasí pre dnešný deň.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
        }
    }

    private var seasonCalendarSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Sezóna tento mesiac")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if rankedInSeasonSpecies.isEmpty {
                VStack(spacing: 8) {
                    SporeShape()
                        .fill(DesignSystem.Colors.cloud.opacity(0.4))
                        .frame(width: 26, height: 26)
                    Text("Žiadne druhy nie sú aktuálne v sezóne.")
                        .font(.system(size: DesignSystem.bodySize))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.spacingSmall)
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                    ForEach(Array(rankedInSeasonSpecies.enumerated()), id: \.element.id) { index, species in
                        seasonRow(rank: index + 1, species: species)
                    }
                }
            }
        }
    }

    // Edible species get a moss swatch, matching the approved mockup's default chip. Caution
    // and poisonous species get their swatch recolored via the same `warningColor` policy used
    // everywhere else species appear (SpeciesCardView, topPicksSection), plus the same explicit
    // Slovak warning text — a color-only signal isn't sufficient for a foraging app's safety
    // info (colorblind accessibility, and this app never approximates safety-critical content).
    // The warning now sits inline on the row's trailing edge instead of stacking below the
    // name, so caution/poisonous rows are the same height as edible ones — the sign stays,
    // the extra line doesn't (2026-08-11 predpoved-beautify spec §5).
    private func seasonRow(rank: Int, species: Species) -> some View {
        let swatchColor = species.edibility == .edible ? DesignSystem.Colors.mossAccent : DesignSystem.warningColor(for: species.edibility)
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: DesignSystem.captionSize * 0.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.35))
                .frame(width: 16, alignment: .trailing)
            LeafShape()
                .stroke(swatchColor, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: DesignSystem.chipDotSize + 4, height: DesignSystem.chipDotSize + 4)
            Text(species.commonNameSk)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.cloud)
            Spacer(minLength: 8)
            if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                Text(warning)
                    .font(.system(size: DesignSystem.captionSize * 0.6, weight: .bold))
                    .foregroundStyle(swatchColor)
                    .lineLimit(1)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 14))
        .frame(minWidth: DesignSystem.seasonRowMinWidth, alignment: .leading)
        .background(swatchColor.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.seasonRowCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.seasonRowCornerRadius)
                .stroke(swatchColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var disclaimer: some View {
        Text("Tento zoznam je len orientačný odhad na základe počasia a sezóny. Pred zberom a konzumáciou húb si nález vždy overte s odborníkom alebo v spoľahlivom atlase húb.")
            .font(.system(size: DesignSystem.captionSize))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            .padding(.top, DesignSystem.spacingMedium)
    }
}
