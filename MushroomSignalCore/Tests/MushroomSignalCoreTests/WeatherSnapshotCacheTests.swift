import XCTest
@testable import MushroomSignalCore

final class WeatherSnapshotCacheTests: XCTestCase {
    func testReturnsNilWhenNothingCachedForRegion() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let cache = WeatherSnapshotCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(cache.snapshot(for: "zilinsky"))
    }

    func testStoreThenRetrieveRoundTripsTheSnapshot() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let cache = WeatherSnapshotCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let snapshot = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 14.5, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 22, fetchedAt: .now)
        cache.store(snapshot)

        XCTAssertEqual(cache.snapshot(for: "zilinsky"), snapshot)
    }

    func testCachesPerRegionIndependently() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let cache = WeatherSnapshotCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let a = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 14.5, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 22, fetchedAt: .now)
        let b = WeatherSnapshot(regionId: "kosicky", averageTempLast10DaysC: 18, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 5, fetchedAt: .now)
        cache.store(a)
        cache.store(b)

        XCTAssertEqual(cache.snapshot(for: "zilinsky"), a)
        XCTAssertEqual(cache.snapshot(for: "kosicky"), b)
    }

    func testNewerStoreForSameRegionOverwritesOlder() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let cache = WeatherSnapshotCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let older = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 10, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 1, fetchedAt: Date(timeIntervalSince1970: 0))
        let newer = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 20, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 2, fetchedAt: Date(timeIntervalSince1970: 1000))
        cache.store(older)
        cache.store(newer)

        XCTAssertEqual(cache.snapshot(for: "zilinsky"), newer)
    }
}
