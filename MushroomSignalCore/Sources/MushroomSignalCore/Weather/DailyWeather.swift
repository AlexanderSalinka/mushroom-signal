import Foundation

public struct DailyWeather: Codable, Equatable, Sendable {
    public let date: Date
    public let meanTempC: Double
    public let maxTempC: Double
    public let precipitationMm: Double

    public init(date: Date, meanTempC: Double, maxTempC: Double, precipitationMm: Double) {
        self.date = date
        self.meanTempC = meanTempC
        self.maxTempC = maxTempC
        self.precipitationMm = precipitationMm
    }
}
