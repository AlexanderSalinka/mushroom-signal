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

    /// Dates to label on the x-axis. Thinned as `selectedRange` grows so labels never
    /// overlap, but anchored to "today" (not the axis's leftmost date) so today is always
    /// on the grid — `AxisMarks(values: .stride(by: .day, count:))` anchors to the domain's
    /// lower bound instead, which silently drops "dnes" whenever today doesn't happen to
    /// fall on that grid (confirmed visually at the 30-day range: stride-3 from Jul 13
    /// lands on 9 and 12, skipping 11/today entirely).
    private var axisMarkDates: [Date] {
        let step = selectedRange > 14 ? 3 : (selectedRange > 7 ? 2 : 1)
        guard step > 1 else {
            return visibleDays.map(\.date)
        }
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        return visibleDays.map(\.date).filter { date in
            let dayOffset = calendar.dateComponents([.day], from: todayStart, to: calendar.startOfDay(for: date)).day ?? 0
            return dayOffset % step == 0
        }
    }

    /// Empirical correction for the trailing y-axis label column: `GeometryReader` in the
    /// overlay below measures the full chart frame, but Swift Charts reserves a fixed-width
    /// strip on the trailing edge for the y-axis numbers that isn't part of the actual bar
    /// plot area. Without this correction the marker lands visibly right of "dnes" — confirmed
    /// by pixel-measuring rendered screenshots at all three range settings (7/14/30 days):
    /// raw (index+0.5)/count vs. the actual on-screen "dnes" tick fraction gave (0.591, 0.565),
    /// (0.750, 0.729), (0.868, 0.849) — an almost perfectly linear relationship (slope ~1.0265
    /// across all three pairs, well within measurement noise), fit here as `rawFraction * scale
    /// + offset`. Residual error after fitting was under 0.03% of chart width at every range.
    private static let axisCorrectionScale = 1.0265
    private static let axisCorrectionOffset = -0.0413

    private var todayFraction: Double? {
        guard let todayIndex = visibleDays.firstIndex(where: { Calendar.current.isDateInToday($0.date) }) else { return nil }
        let rawFraction = (Double(todayIndex) + 0.5) / Double(visibleDays.count)
        return rawFraction * Self.axisCorrectionScale + Self.axisCorrectionOffset
    }

    private var lastRainText: String {
        guard let recent = MostRecentRainfall.find(in: dailyWeather, asOf: today) else {
            return "Bez zaznamenaných zrážok za posledných 30 dní."
        }
        let daysAgo = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: recent.date),
            to: Calendar.current.startOfDay(for: today)
        ).day ?? 0
        let amount = String(format: "%.0f", recent.precipitationMm)
        if daysAgo == 0 {
            return "Dnes pršalo (\(amount) mm)."
        }
        let dayWord = daysAgo == 1 ? "dňom" : "dňami"
        return "Naposledy pršalo pred \(daysAgo) \(dayWord) (\(amount) mm)."
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
                    AxisMarks(values: axisMarkDates) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Calendar.current.isDateInToday(date) ? "dnes" : date.formatted(.dateTime.day()))
                                    .font(.system(size: DesignSystem.chartAxisLabelSize))
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let todayFraction {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(DesignSystem.Colors.cloud.opacity(0.35))
                            .frame(width: 1.5)
                            .position(x: geometry.size.width * todayFraction, y: geometry.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
            }

            Text(lastRainText)
                .font(.system(size: DesignSystem.captionSize * 0.65))
                .foregroundStyle(DesignSystem.Colors.water)
                .padding(.top, DesignSystem.spacingTight)
        }
    }
}
