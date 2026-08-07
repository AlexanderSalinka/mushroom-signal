import Foundation

/// A day 2-7 days ago with a maximum temperature of at least 26°C and measurable rain
/// reliably precedes a mushroom flush within about a week — a real foraging pattern, not
/// an arbitrary rule. See the roadmap spec §1.
public enum FlushTriggerDetector {
    public static func triggered(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> Bool {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        return dailyWeather.contains { day in
            let dayStart = utcCalendar.startOfDay(for: day.date)
            guard let daysAgo = utcCalendar.dateComponents([.day], from: dayStart, to: todayStart).day else { return false }
            guard (2...7).contains(daysAgo) else { return false }
            return day.maxTempC >= 26.0 && day.precipitationMm >= 5.0
        }
    }
}
