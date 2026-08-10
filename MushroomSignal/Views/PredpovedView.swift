// MushroomSignal/Views/PredpovedView.swift
import SwiftUI
import Charts
import MushroomSignalCore

struct PredpovedView: View {
    let regionId: String
    let topSignals: [SpeciesSignal]
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
            .sorted { $0.commonNameSk < $1.commonNameSk }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                if let error = weatherState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(DesignSystem.Colors.danger)
                }

                heroSection
                dailyStripSection
                if !topSignals.isEmpty {
                    topPicksSection
                }
                seasonCalendarSection
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
        .task {
            allSpecies = (try? SpeciesDatabase.loadAll()) ?? []
        }
    }

    private var topPicksSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Odporúčané dnes")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            ForEach(Array(topSignals.prefix(3).enumerated()), id: \.element.species.id) { index, signal in
                HStack(spacing: DesignSystem.spacingSmall) {
                    Text("\(index + 1)")
                        .font(.system(size: DesignSystem.captionSize, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(DesignSystem.Colors.mossAccent.opacity(0.3)))
                    VStack(alignment: .leading, spacing: DesignSystem.spacingTight / 2) {
                        Text(signal.species.commonNameSk)
                            .font(.system(size: DesignSystem.bodySize, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.cloud)
                        Text(signal.species.latinName)
                            .font(.system(size: DesignSystem.captionSize).italic())
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                    }
                    Spacer()
                    ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize)
                }
                .padding(DesignSystem.spacingSmall)
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
            } else {
                Text("Načítavam počasie…")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
        }
    }

    private var dailyStripSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Denný prehľad")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Chart(weatherState.dailyWeather, id: \.date) { day in
                BarMark(
                    x: .value("Deň", day.date, unit: .day),
                    yStart: .value("Min", day.minTempC),
                    yEnd: .value("Max", day.maxTempC)
                )
                // Cold-to-hot gradient per bar (caution at the top/max end, water at the
                // bottom/min end) — matches the approved mockup and gives `water` its first
                // real use anywhere in the app (previously defined, never consumed).
                .foregroundStyle(
                    LinearGradient(colors: [DesignSystem.Colors.caution, DesignSystem.Colors.water], startPoint: .top, endPoint: .bottom)
                        .opacity(isForecastDay(day) ? 0.5 : 1.0)
                )
                .cornerRadius(7)
            }
            .frame(height: DesignSystem.trendChartHeight)
        }
    }

    private func isForecastDay(_ day: DailyWeather) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: day.date) > calendar.startOfDay(for: Date())
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
                ForEach(inSeasonSpecies) { species in
                    Text(species.commonNameSk)
                        .font(.system(size: DesignSystem.bodySize))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                }
            }
        }
    }
}
