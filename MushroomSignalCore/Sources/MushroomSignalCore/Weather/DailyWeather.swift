import Foundation

public struct DailyWeather: Codable, Equatable, Sendable {
    public let date: Date
    public let meanTempC: Double
    public let maxTempC: Double
    public let minTempC: Double
    public let precipitationMm: Double
    public let humidityPercent: Double

    public init(date: Date, meanTempC: Double, maxTempC: Double, minTempC: Double, precipitationMm: Double, humidityPercent: Double) {
        self.date = date
        self.meanTempC = meanTempC
        self.maxTempC = maxTempC
        self.minTempC = minTempC
        self.precipitationMm = precipitationMm
        self.humidityPercent = humidityPercent
    }
}
