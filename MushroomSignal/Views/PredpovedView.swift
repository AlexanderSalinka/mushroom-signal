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
                dailyStripSection
                if !visibleTopSignals.isEmpty {
                    topPicksSection
                }
                seasonCalendarSection
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
                Text("Vlhkosť \(Int(today.humidityPercent.rounded()))% · Zrážky \(String(format: "%.1f", today.precipitationMm)) mm")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
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

    private var pastTenDays: [DailyWeather] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        return weatherState.dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
    }

    private var dailyStripSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Posledných 10 dní")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            HStack(spacing: 12) {
                Text("teplo")
                    .font(.system(size: DesignSystem.captionSize * 0.6))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
                Text("dážď")
                    .font(.system(size: DesignSystem.captionSize * 0.6))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            }
            Chart(pastTenDays, id: \.date) { day in
                BarMark(
                    x: .value("Deň", day.date, unit: .day),
                    y: .value("Teplo", day.maxTempC)
                )
                .foregroundStyle(DesignSystem.Colors.caution)
                .cornerRadius(DesignSystem.chartBarCornerRadius * 0.5)
            }
            .frame(height: DesignSystem.rainHeatChartRowHeight)
            .chartYAxis(.hidden)

            Chart(pastTenDays, id: \.date) { day in
                BarMark(
                    x: .value("Deň", day.date, unit: .day),
                    y: .value("Dážď", day.precipitationMm)
                )
                .foregroundStyle(DesignSystem.Colors.water)
                .cornerRadius(DesignSystem.chartBarCornerRadius * 0.5)
            }
            .frame(height: DesignSystem.rainHeatChartRowHeight)
            .chartYAxis(.hidden)
        }
    }

    private var seasonCalendarSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Sezóna tento mesiac")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if inSeasonSpecies.isEmpty {
                Text("Žiadne druhy nie sú aktuálne v sezóne.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
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
                Circle()
                    .fill(swatchColor)
                    .frame(width: DesignSystem.chipDotSize, height: DesignSystem.chipDotSize)
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
