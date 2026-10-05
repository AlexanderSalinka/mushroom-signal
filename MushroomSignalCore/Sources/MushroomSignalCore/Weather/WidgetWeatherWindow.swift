/// The daily-weather window the widget requests from Open-Meteo.
///
/// It must include today (`forecastDays >= 1`) — the temperature tile shows today's min/max —
/// and a few days ahead, so `UpcomingRainDetector` can find rain coming. All consumers
/// (`WeatherSnapshot.derive`, `MostRecentRainfall`, `FlushTriggerDetector`) already filter by
/// "as of today", so the extra forecast rows never leak into the past-weather numbers.
/// Mirrors what the app itself requests (`AppState`: 30 past + 5 forecast days).
public enum WidgetWeatherWindow {
    public static let pastDays = 10
    public static let forecastDays = 5
}
