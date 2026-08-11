import Foundation

/// Forward-looking counterpart to `FlushTriggerDetector`: instead of asking "did a trigger
/// day already happen in the last week" (which feeds today's score), this scans upcoming
/// forecast days for the same condition, so the app can tell the user a flush may be coming
/// before it shows up in the score. Reuses `FlushTriggerDetector`'s exact thresholds — one
/// source of truth, read in both directions.
public enum UpcomingRainDetector {
    public static func nextTriggerEvent(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> RainEvent? {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        let qualifying = dailyWeather
            .filter { $0.date > todayStart }
            .filter { $0.maxTempC >= FlushTriggerDetector.minTriggerMaxTempC && $0.precipitationMm >= FlushTriggerDetector.minTriggerPrecipitationMm }
            .sorted { $0.date < $1.date }

        guard let earliest = qualifying.first else { return nil }

        return RainEvent(
            date: earliest.date,
            precipitationMm: earliest.precipitationMm,
            maxTempC: earliest.maxTempC,
            flushWindowStart: earliest.date.addingTimeInterval(2 * 86400),
            flushWindowEnd: earliest.date.addingTimeInterval(7 * 86400)
        )
    }
}

public struct RainEvent: Equatable, Sendable {
    public let date: Date
    public let precipitationMm: Double
    public let maxTempC: Double
    public let flushWindowStart: Date
    public let flushWindowEnd: Date

    public init(date: Date, precipitationMm: Double, maxTempC: Double, flushWindowStart: Date, flushWindowEnd: Date) {
        self.date = date
        self.precipitationMm = precipitationMm
        self.maxTempC = maxTempC
        self.flushWindowStart = flushWindowStart
        self.flushWindowEnd = flushWindowEnd
    }
}
