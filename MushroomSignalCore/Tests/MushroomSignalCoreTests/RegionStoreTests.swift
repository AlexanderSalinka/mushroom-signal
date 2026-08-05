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
}
