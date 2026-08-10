import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class NotificationSettingsStateTests: XCTestCase {
    private func makePreferences() -> (NotificationPreferences, String) {
        let suiteName = "test.suite.\(UUID().uuidString)"
        return (NotificationPreferences(appGroupId: suiteName)!, suiteName)
    }

    func testAddWatchPersistsToPreferences() {
        let (prefs, suiteName) = makePreferences()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let state = NotificationSettingsState(preferences: prefs)

        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)

        XCTAssertEqual(state.watchedAlerts.count, 1)
        XCTAssertEqual(prefs.watchedAlerts().count, 1)
    }

    func testAddingSameSpeciesRegionUpdatesInsteadOfDuplicating() {
        let (prefs, suiteName) = makePreferences()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let state = NotificationSettingsState(preferences: prefs)

        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 2)
        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 4)

        XCTAssertEqual(state.watchedAlerts.count, 1)
        XCTAssertEqual(state.watchedAlerts.first?.threshold, 4)
    }

    func testRemoveWatchPersists() {
        let (prefs, suiteName) = makePreferences()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let state = NotificationSettingsState(preferences: prefs)
        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)

        state.removeWatch(state.watchedAlerts[0])

        XCTAssertTrue(state.watchedAlerts.isEmpty)
        XCTAssertTrue(prefs.watchedAlerts().isEmpty)
    }
}
