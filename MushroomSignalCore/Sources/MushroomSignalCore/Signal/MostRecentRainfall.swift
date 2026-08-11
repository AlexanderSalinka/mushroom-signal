import Foundation

/// Answers "when did it last actually rain" from already-loaded weather data — the fact behind
/// `WeatherRainChartView`'s "Naposledy pršalo" callout. Deliberately independent of
/// `FlushTriggerDetector`'s thresholds: any measurable rain counts here, not just a flush-
/// triggering amount.
public enum MostRecentRainfall {
    public static func find(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> (date: Date, precipitationMm: Double)? {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        let mostRecent = dailyWeather
            .filter { utcCalendar.startOfDay(for: $0.date) <= todayStart }
            .filter { $0.precipitationMm > 0 }
            .sorted { $0.date > $1.date }
            .first

        guard let mostRecent else { return nil }
        return (date: mostRecent.date, precipitationMm: mostRecent.precipitationMm)
    }
}
