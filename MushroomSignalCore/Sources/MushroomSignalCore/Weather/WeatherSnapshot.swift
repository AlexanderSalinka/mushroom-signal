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
}
