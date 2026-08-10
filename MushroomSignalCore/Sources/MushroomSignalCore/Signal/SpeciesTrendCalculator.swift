import Foundation

public struct TrendPoint: Equatable, Sendable {
    public let date: Date
    public let score: Int
    public let isForecast: Bool

    public init(date: Date, score: Int, isForecast: Bool) {
        self.date = date
        self.score = score
        self.isForecast = isForecast
    }
}

/// Turns a daily-weather series into a per-day score series for one species, reusing
/// SignalAlgorithm.computeSignal via WeatherSnapshot.singleDay — no new scoring logic.
public enum SpeciesTrendCalculator {
    public static func trend(
        species: Species,
        dailyWeather: [DailyWeather],
        regionId: String,
        today: Date = Date()
    ) -> [TrendPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = calendar.startOfDay(for: today)

        return dailyWeather.map { day in
            let snapshot = WeatherSnapshot.singleDay(regionId: regionId, day: day)
            let month = calendar.component(.month, from: day.date)
            let flushTriggered = FlushTriggerDetector.triggered(in: dailyWeather, asOf: day.date, calendar: calendar)
            let signal = SignalAlgorithm.computeSignal(species: species, weather: snapshot, month: month, flushTriggered: flushTriggered)
            let dayStart = calendar.startOfDay(for: day.date)
            return TrendPoint(date: day.date, score: signal.score, isForecast: dayStart > todayStart)
        }
    }
}
