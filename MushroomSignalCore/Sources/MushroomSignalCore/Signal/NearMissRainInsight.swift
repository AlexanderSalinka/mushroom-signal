import Foundation

/// When `UpcomingRainDetector` finds no real trigger day in the forecast, this looks for a
/// near miss — rain without enough heat, or heat without enough rain — so "Blíži sa dážď"'s
/// empty state can say what IS coming instead of just "nothing." Reuses
/// `FlushTriggerDetector`'s exact thresholds, same one-source-of-truth pattern as
/// `UpcomingRainDetector`. Callers should only consult this after `UpcomingRainDetector
/// .nextTriggerEvent` returns nil — a real trigger day always takes priority.
public enum NearMissRainInsight {
    public enum Case: Equatable, Sendable {
        case rainWithoutHeat(date: Date, precipitationMm: Double, maxTempC: Double)
        case heatWithoutRain(date: Date, precipitationMm: Double, maxTempC: Double)
    }

    public static func describe(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> Case? {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        let forecastDays = dailyWeather
            .filter { $0.date > todayStart }
            .sorted { $0.date < $1.date }

        for day in forecastDays {
            let hasRain = day.precipitationMm >= FlushTriggerDetector.minTriggerPrecipitationMm
            let hasHeat = day.maxTempC >= FlushTriggerDetector.minTriggerMaxTempC
            if hasRain && !hasHeat {
                return .rainWithoutHeat(date: day.date, precipitationMm: day.precipitationMm, maxTempC: day.maxTempC)
            }
            if hasHeat && !hasRain {
                return .heatWithoutRain(date: day.date, precipitationMm: day.precipitationMm, maxTempC: day.maxTempC)
            }
        }
        return nil
    }
}
