import XCTest
@testable import MushroomSignalCore

final class RegionStoreTests: XCTestCase {
    func testDefaultsToZilinskyWhenNothingStored() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let store = RegionStore(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(store.selectedRegion().id, "zilinsky")
    }

    func testPersistsSelectedRegion() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let store = RegionStore(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let kosice = RegionDatabase.find(id: "kosicky")!
        store.setSelectedRegion(kosice)

        XCTAssertEqual(store.selectedRegion().id, "kosicky")
    }

    func testFallsBackToDefaultWhenStoredIdIsUnrecognized() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let store = RegionStore(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        // Simulate corrupted/stale data by directly writing an unknown id
        UserDefaults(suiteName: suiteName)?.set("unknown-region-id", forKey: RegionStoreConstants.selectedRegionKey)

        // Should fall back to declared default (zilinsky), not to bratislavsky (all[0])
        XCTAssertEqual(store.selectedRegion().id, "zilinsky")
    }

    func testResolvedAppGroupIdPrefixesTeamIdentifierWhenPresent() {
        XCTAssertEqual(
            RegionStoreConstants.resolvedAppGroupId(teamIdentifier: "T78DK947F3"),
            "T78DK947F3.group.com.alexandersalinka.MushroomSignal"
        )
    }

    func testResolvedAppGroupIdFallsBackToBareSuffixWhenTeamIdentifierUnavailable() {
        XCTAssertEqual(
            RegionStoreConstants.resolvedAppGroupId(teamIdentifier: nil),
            "group.com.alexandersalinka.MushroomSignal"
        )
    }
}
