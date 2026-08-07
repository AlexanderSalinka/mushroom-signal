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
