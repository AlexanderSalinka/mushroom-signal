import Foundation

/// A fixed 7-day-back + all-forecast window over daily weather — the minimal,
/// non-toggleable counterpart to `WeatherRainChartView`'s own `visibleDays` (which
/// supports a user-facing 7/14/30-day range toggle via private `@State`, not something a
/// sibling view can call into). `MushroomSignalHeroMiniChart` uses this to stay a pure
/// view over the same shared `RegionWeatherState.dailyWeather` the full chart already
/// loads, without a second fetch or a dependency on the full chart's internal state.
public enum RecentWeatherWindow {
    public static func lastSevenDaysPlusForecast(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> [DailyWeather] {
        let todayStart = calendar.startOfDay(for: today)
        let pastDays = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
            .suffix(7)
        let forecastDays = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) > todayStart }
            .sorted { $0.date < $1.date }
        return Array(pastDays) + forecastDays
    }
}
