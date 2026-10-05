import XCTest
@testable import MushroomSignalCore

/// Regression guard (2026-10-05): the widget asked Open-Meteo for `forecast_days=0`, which
/// returns only days up to yesterday — so the temperature tile never found "today" and always
/// showed "—", and the upcoming-rain headline could never fire.
final class WidgetWeatherWindowTests: XCTestCase {
    func testWindowIncludesToday() {
        XCTAssertGreaterThanOrEqual(WidgetWeatherWindow.forecastDays, 1, "forecast_days=0 excludes today")
    }

    func testWindowIncludesDaysAheadForUpcomingRain() {
        XCTAssertGreaterThanOrEqual(WidgetWeatherWindow.forecastDays, 2, "UpcomingRainDetector only looks at days after today")
    }

    func testWindowCoversTheSevenDayAverage() {
        XCTAssertGreaterThanOrEqual(WidgetWeatherWindow.pastDays, 7, "the tile's weekly average needs 7 past days")
    }
}
