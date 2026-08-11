// MushroomSignal/Views/WeatherRainChartView.swift
import SwiftUI
import Charts
import MushroomSignalCore

/// Propagates the today-marker's resolved x position (in `WeatherRainChartView.chartCoordinateSpace`)
/// up from the rain chart's `.chartOverlay` to the two-chart `VStack`'s `.overlay`. A `PreferenceKey`
/// is used instead of `@State` + `.onAppear`/`.onChange` because the marker's inputs (`ChartProxy`,
/// `GeometryProxy`) depend on `dailyWeather`, which loads asynchronously — `.onAppear` fires once,
/// before that load completes, and a value computed then would go stale forever with nothing to
/// re-trigger it. A preference is recomputed on every body evaluation instead, so it can't go stale.
private struct TodayMarkerXPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

/// Predpoveď's daily weather chart — temperature line above rain bars, each with its own
/// honest y-axis (never a shared/dual-axis scale — see the 2026-08-11 predpoved-beautify
/// spec §1 for why: a dual-axis chart invents a correlation that isn't in the data).
struct WeatherRainChartView: View {
    let dailyWeather: [DailyWeather]
    let today: Date
    @State private var selectedRange: Int = 7
    @State private var todayMarkerX: CGFloat?

    /// Shared coordinate space for the two-chart `VStack`, so the today-marker's x position
    /// (resolved from the rain chart's own `ChartProxy`, which owns the visible x-axis) can be
    /// converted into a coordinate the outer `.overlay` can draw in — letting the marker still
    /// visually span both panels even though only the rain chart provides the real plot geometry.
    private static let chartCoordinateSpace = "weatherRainChartStack"

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

    /// Today's date within the visible range, if present. Feeds `ChartProxy.position(forX:)`
    /// in `body`'s `.chartOverlay` — the proxy queries the chart's actual rendered plot-area
    /// mapping (already accounting for the reserved trailing y-axis label strip), so no
    /// hand-fit correction constants are needed.
    private var todayDate: Date? {
        visibleDays.first(where: { Calendar.current.isDateInToday($0.date) })?.date
    }

    /// Resolves the today-marker's x position from the rain chart's `ChartProxy` and its own
    /// `GeometryReader`, converting the plot-relative x into `chartCoordinateSpace` (the two-chart
    /// `VStack`'s space) so the `.overlay` below can draw a marker that still spans both panels.
    /// Pure — no side effects — so it's safe to call on every body evaluation via `.preference`.
    private func resolvedTodayMarkerX(proxy: ChartProxy, geometry: GeometryProxy) -> CGFloat? {
        guard let todayDate,
              let plotRelativeX = proxy.position(forX: todayDate),
              let plotFrameAnchor = proxy.plotFrame else {
            return nil
        }
        let plotOriginInChart = geometry[plotFrameAnchor].origin
        let chartFrameInStack = geometry.frame(in: .named(Self.chartCoordinateSpace))
        return chartFrameInStack.minX + plotOriginInChart.x + plotRelativeX
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
                .chartYAxis(.hidden)
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
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: TodayMarkerXPreferenceKey.self,
                                value: resolvedTodayMarkerX(proxy: proxy, geometry: geometry)
                            )
                    }
                }
            }
            .coordinateSpace(.named(Self.chartCoordinateSpace))
            .onPreferenceChange(TodayMarkerXPreferenceKey.self) { todayMarkerX = $0 }
            .overlay(alignment: .topLeading) {
                if let todayMarkerX {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(DesignSystem.Colors.cloud.opacity(0.35))
                            .frame(width: 1.5)
                            .position(x: todayMarkerX, y: geometry.size.height / 2)
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
