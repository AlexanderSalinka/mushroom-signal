import XCTest
@testable import MushroomSignalCore

final class SlovakiaGridTests: XCTestCase {
    func testGeneratePointCountLandsInExpectedRange() {
        let points = SlovakiaGrid.generate()
        XCTAssertGreaterThanOrEqual(points.count, 30)
        XCTAssertLessThanOrEqual(points.count, 50)
    }

    func testEveryPointFallsWithinBoundingBox() {
        let points = SlovakiaGrid.generate()
        for point in points {
            XCTAssertTrue(SlovakiaGrid.latitudeRange.contains(point.latitude), "lat \(point.latitude) out of range")
            XCTAssertTrue(SlovakiaGrid.longitudeRange.contains(point.longitude), "lon \(point.longitude) out of range")
        }
    }

    func testPointIDsAreUnique() {
        let points = SlovakiaGrid.generate()
        XCTAssertEqual(Set(points.map(\.id)).count, points.count)
    }
}
