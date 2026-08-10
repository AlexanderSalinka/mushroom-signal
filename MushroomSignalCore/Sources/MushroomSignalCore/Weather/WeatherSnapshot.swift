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
    /// Builds a WeatherSnapshot from ONE day's readings, reusing SignalAlgorithm's existing
    /// fit functions for trend-chart scoring. Deliberate simplification, not a true 10-day
    /// rolling aggregate like every other WeatherSnapshot in this app — a trend dot may not
    /// exactly equal what the shortlist showed that historical day. The value here is
    /// direction (improving/fading), not exact historical reproduction. See
    /// docs/superpowers/specs/2026-08-10-sparkline-notifications-predpoved-design.md.
    static func singleDay(regionId: String, day: DailyWeather) -> WeatherSnapshot {
        WeatherSnapshot(
            regionId: regionId,
            averageTempLast10DaysC: day.meanTempC,
            averageHumidityLast10DaysPercent: day.humidityPercent,
            totalPrecipitationLast10DaysMm: day.precipitationMm,
            fetchedAt: day.date
        )
    }
}
