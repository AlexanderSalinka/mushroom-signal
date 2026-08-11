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
        .mushroomGlassBackground()
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
                    CompactSpeciesCardView(species: signal.species, signal: signal, rank: index + 1, photo: nil)
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
            if inSeasonSpecies.isEmpty {
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DesignSystem.spacingSmall)], spacing: DesignSystem.spacingSmall) {
                    ForEach(inSeasonSpecies) { species in
                        seasonChip(for: species)
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
    private func seasonChip(for species: Species) -> some View {
        let swatchColor = species.edibility == .edible ? DesignSystem.Colors.mossAccent : DesignSystem.warningColor(for: species.edibility)
        return VStack(alignment: .leading, spacing: DesignSystem.spacingTight / 2) {
            HStack(spacing: 7) {
                LeafShape()
                    .stroke(swatchColor, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: DesignSystem.chipDotSize + 4, height: DesignSystem.chipDotSize + 4)
                Text(species.commonNameSk)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                Text(warning)
                    .font(.system(size: DesignSystem.captionSize, weight: .bold))
                    .foregroundStyle(swatchColor)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 14))
        .background(swatchColor.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius)
                .stroke(swatchColor.opacity(0.45), lineWidth: 1)
        )
    }

    private var disclaimer: some View {
        Text("Tento zoznam je len orientačný odhad na základe počasia a sezóny. Pred zberom a konzumáciou húb si nález vždy overte s odborníkom alebo v spoľahlivom atlase húb.")
            .font(.system(size: DesignSystem.captionSize))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            .padding(.top, DesignSystem.spacingMedium)
    }
}
