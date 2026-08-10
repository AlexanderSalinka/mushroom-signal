import XCTest
@testable import MushroomSignalCore

final class NotificationPreferencesTests: XCTestCase {
    func testReturnsEmptyWhenNothingStored() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let prefs = NotificationPreferences(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(prefs.watchedAlerts().isEmpty)
    }

    func testStoreThenRetrieveRoundTripsAlerts() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let prefs = NotificationPreferences(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let alert = WatchedAlert(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)
        prefs.setWatchedAlerts([alert])

        XCTAssertEqual(prefs.watchedAlerts(), [alert])
    }

    func testSetWatchedAlertsFullyReplacesPreviousValue() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let prefs = NotificationPreferences(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        prefs.setWatchedAlerts([WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 2)])
        prefs.setWatchedAlerts([WatchedAlert(speciesId: "b", regionId: "kosicky", threshold: 4)])

        XCTAssertEqual(prefs.watchedAlerts().map(\.speciesId), ["b"])
    }
}
