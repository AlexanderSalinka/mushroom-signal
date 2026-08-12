import XCTest
@testable import MushroomSignalCore

final class DailyWeatherCacheTests: XCTestCase {
    private func makeCache() -> (DailyWeatherCache, String) {
        let suiteName = "test.suite.\(UUID().uuidString)"
        return (DailyWeatherCache(appGroupId: suiteName)!, suiteName)
    }

    private func sampleDay(temp: Double) -> DailyWeather {
        DailyWeather(date: .now, meanTempC: temp, maxTempC: temp + 5, minTempC: temp - 5, precipitationMm: 2, humidityPercent: 65)
    }

    func testReturnsNilWhenNothingCachedForRegion() {
        let (cache, suiteName) = makeCache()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(cache.dailyWeather(for: "zilinsky"))
    }

    func testStoreThenRetrieveRoundTripsTheArray() {
        let (cache, suiteName) = makeCache()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let days = [sampleDay(temp: 15), sampleDay(temp: 20)]

        cache.store(days, for: "zilinsky")

        XCTAssertEqual(cache.dailyWeather(for: "zilinsky"), days)
    }

    func testNewerStoreForSameRegionOverwritesOlder() {
        let (cache, suiteName) = makeCache()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        cache.store([sampleDay(temp: 10)], for: "zilinsky")
        cache.store([sampleDay(temp: 25)], for: "zilinsky")

        XCTAssertEqual(cache.dailyWeather(for: "zilinsky")?.first?.meanTempC, 25)
    }

    func testCachesPerRegionIndependently() {
        let (cache, suiteName) = makeCache()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        cache.store([sampleDay(temp: 10)], for: "zilinsky")
        cache.store([sampleDay(temp: 30)], for: "kosicky")

        XCTAssertEqual(cache.dailyWeather(for: "zilinsky")?.first?.meanTempC, 10)
        XCTAssertEqual(cache.dailyWeather(for: "kosicky")?.first?.meanTempC, 30)
    }
}
