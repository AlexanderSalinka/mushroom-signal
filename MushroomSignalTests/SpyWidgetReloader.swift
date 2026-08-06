import XCTest
@testable import MushroomSignal

actor SpyWidgetReloader: WidgetReloading {
    private(set) var reloadCount = 0
    private let expectation: XCTestExpectation?

    init(expectation: XCTestExpectation? = nil) {
        self.expectation = expectation
    }

    func reloadAllTimelines() async {
        reloadCount += 1
        expectation?.fulfill()
    }
}
