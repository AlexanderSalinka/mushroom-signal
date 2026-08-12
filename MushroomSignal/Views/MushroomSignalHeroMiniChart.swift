// MushroomSignal/Views/MushroomSignalHeroMiniChart.swift
import SwiftUI
import Charts
import MushroomSignalCore

/// The hero panel's condensed temp+rain preview (loud states only) — same `LineMark`/
/// `BarMark` pattern as `WeatherRainChartView`, fixed at a 7-day-back + forecast window
/// via `RecentWeatherWindow` (not the full chart's user-toggleable range), no axis
/// labels. A pure view over the caller-supplied `dailyWeather` — no independent fetch.
struct MushroomSignalHeroMiniChart: View {
    let dailyWeather: [DailyWeather]
    let today: Date

    private var visibleDays: [DailyWeather] {
        RecentWeatherWindow.lastSevenDaysPlusForecast(in: dailyWeather, asOf: today)
    }

    var body: some View {
        VStack(spacing: 2) {
            Chart(visibleDays, id: \.date) { day in
                LineMark(
                    x: .value("Deň", day.date, unit: .day),
                    y: .value("Teplota", day.maxTempC)
                )
                .foregroundStyle(DesignSystem.Colors.caution)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            .frame(height: DesignSystem.heroSparklineTempHeight)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)

            Chart(visibleDays, id: \.date) { day in
                BarMark(
                    x: .value("Deň", day.date, unit: .day),
                    y: .value("Zrážky", day.precipitationMm)
                )
                .foregroundStyle(DesignSystem.Colors.water)
                .cornerRadius(DesignSystem.chartBarCornerRadius * 0.4)
            }
            .frame(height: DesignSystem.heroSparklineRainHeight)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }
}
