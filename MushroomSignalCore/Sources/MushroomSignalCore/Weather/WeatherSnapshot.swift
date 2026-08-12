import Foundation

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public let regionId: String
    public let averageTempLast10DaysC: Double
    public let averageHumidityLast10DaysPercent: Double
    public let totalPrecipitationLast10DaysMm: Double
    public let fetchedAt: Date

    public init(regionId: String, averageTempLast10DaysC: Double, averageHumidityLast10DaysPercent: Double, totalPrecipitationLast10DaysMm: Double, fetchedAt: Date) {
        self.regionId = regionId
        self.averageTempLast10DaysC = averageTempLast10DaysC
        self.averageHumidityLast10DaysPercent = averageHumidityLast10DaysPercent
        self.totalPrecipitationLast10DaysMm = totalPrecipitationLast10DaysMm
        self.fetchedAt = fetchedAt
    }
}

public extension WeatherSnapshot {
    /// Builds a WeatherSnapshot for `day`, reusing SignalAlgorithm's existing fit functions
    /// for trend-chart scoring. Temp/humidity use `day`'s own single-day mean — a deliberate,
    /// still-accurate simplification since both are already means at both scales (single-day
    /// vs 10-day). Precipitation is NOT single-day: `SignalAlgorithm.rainfallFit`'s thresholds
    /// are calibrated as 10-day SUMS, so `totalPrecipitationLast10DaysMm` must be passed in
    /// as a real trailing sum computed by the caller (see `SpeciesTrendCalculator`), not
    /// `day.precipitationMm` alone — that was a real bug (2026-08-10 final review), not a
    /// deliberate simplification like the temp/humidity one above.
    static func singleDay(regionId: String, day: DailyWeather, totalPrecipitationLast10DaysMm: Double) -> WeatherSnapshot {
        WeatherSnapshot(
            regionId: regionId,
            averageTempLast10DaysC: day.meanTempC,
            averageHumidityLast10DaysPercent: day.humidityPercent,
            totalPrecipitationLast10DaysMm: totalPrecipitationLast10DaysMm,
            fetchedAt: day.date
        )
    }

    /// Derives a WeatherSnapshot from an already-fetched daily array — replaces the old
    /// dedicated fetchSnapshot network call (see the weather-fetch-consolidation design,
    /// 2026-08-12). Averages/sums the most recent `windowDays` calendar days up to and
    /// including `asOf` (never forecast days), matching the same past-day filtering
    /// RecentWeatherWindow and WeatherRainChartView.visibleDays already use elsewhere in
    /// this codebase. Returns nil if no historical data is available.
    static func derive(regionId: String, from dailyWeather: [DailyWeather], windowDays: Int = 10, asOf today: Date, calendar: Calendar = .current) -> WeatherSnapshot? {
        let todayStart = calendar.startOfDay(for: today)
        let window = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
            .suffix(windowDays)
        guard !window.isEmpty else { return nil }

        let temps = window.map(\.meanTempC)
        let humidity = window.map(\.humidityPercent)
        let precipitation = window.map(\.precipitationMm)

        return WeatherSnapshot(
            regionId: regionId,
            averageTempLast10DaysC: temps.reduce(0, +) / Double(temps.count),
            averageHumidityLast10DaysPercent: humidity.reduce(0, +) / Double(humidity.count),
            totalPrecipitationLast10DaysMm: precipitation.reduce(0, +),
            fetchedAt: today
        )
    }
}
