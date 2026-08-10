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
///
/// Every displayed point requires a full trailing `rollingWindowDays`-day window of real
/// data behind it (including itself) — both to compute a real 10-day precipitation sum
/// (SignalAlgorithm's rainfall thresholds are calibrated as 10-day sums, not single-day
/// readings) and to give FlushTriggerDetector's 2-7-day lookback real data at every
/// displayed point, not just later ones. Days without a full window are consumed purely as
/// lookback context, never displayed — the caller (SpeciesTrendState) fetches extra history
/// specifically to make this possible. See the 2026-08-10 final review findings.
public enum SpeciesTrendCalculator {
    private static let rollingWindowDays = 10

    public static func trend(
        species: Species,
        dailyWeather: [DailyWeather],
        regionId: String,
        today: Date = Date()
    ) -> [TrendPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = calendar.startOfDay(for: today)

        let sorted = dailyWeather.sorted { $0.date < $1.date }
        guard sorted.count >= rollingWindowDays else { return [] }

        var points: [TrendPoint] = []
        for index in (rollingWindowDays - 1)..<sorted.count {
            let day = sorted[index]
            let window = sorted[(index - rollingWindowDays + 1)...index]
            let rollingPrecipitation = window.reduce(0.0) { $0 + $1.precipitationMm }
            let snapshot = WeatherSnapshot.singleDay(regionId: regionId, day: day, totalPrecipitationLast10DaysMm: rollingPrecipitation)
            let month = calendar.component(.month, from: day.date)
            let flushTriggered = FlushTriggerDetector.triggered(in: sorted, asOf: day.date, calendar: calendar)
            let signal = SignalAlgorithm.computeSignal(species: species, weather: snapshot, month: month, flushTriggered: flushTriggered)
            let dayStart = calendar.startOfDay(for: day.date)
            points.append(TrendPoint(date: day.date, score: signal.score, isForecast: dayStart > todayStart))
        }
        return points
    }
}
