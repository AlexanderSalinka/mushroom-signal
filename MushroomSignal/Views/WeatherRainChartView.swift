// MushroomSignal/Views/WeatherRainChartView.swift
import SwiftUI
import Charts
import MushroomSignalCore

/// Predpoveď's daily weather chart — temperature line above rain bars, each with its own
/// honest y-axis (never a shared/dual-axis scale — see the 2026-08-11 predpoved-beautify
/// spec §1 for why: a dual-axis chart invents a correlation that isn't in the data).
struct WeatherRainChartView: View {
    let dailyWeather: [DailyWeather]
    let today: Date
    @State private var selectedRange: Int = 7

    private var visibleDays: [DailyWeather] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        let pastDays = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
            .suffix(selectedRange)
        let forecastDays = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) > todayStart }
            .sorted { $0.date < $1.date }
        return Array(pastDays) + forecastDays
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            HStack {
                Text("Posledných \(selectedRange) dní + predpoveď")
                    .font(.system(size: DesignSystem.captionSize, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                Spacer()
                Picker("Rozsah", selection: $selectedRange) {
                    Text("7").tag(7)
                    Text("14").tag(14)
                    Text("30").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .labelsHidden()
            }

            VStack(spacing: 0) {
                Chart(visibleDays, id: \.date) { day in
                    LineMark(
                        x: .value("Deň", day.date, unit: .day),
                        y: .value("Teplota", day.maxTempC)
                    )
                    .foregroundStyle(DesignSystem.Colors.caution)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .frame(height: DesignSystem.chartTempPanelHeight)
                .chartXAxis(.hidden)

                Chart(visibleDays, id: \.date) { day in
                    BarMark(
                        x: .value("Deň", day.date, unit: .day),
                        y: .value("Zrážky", day.precipitationMm)
                    )
                    .foregroundStyle(DesignSystem.Colors.water)
                    .cornerRadius(DesignSystem.chartBarCornerRadius * 0.5)
                }
                .frame(height: DesignSystem.chartRainPanelHeight)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Calendar.current.isDateInToday(date) ? "dnes" : date.formatted(.dateTime.day()))
                                    .font(.system(size: DesignSystem.chartAxisLabelSize))
                            }
                        }
                    }
                }
            }
        }
    }
}
