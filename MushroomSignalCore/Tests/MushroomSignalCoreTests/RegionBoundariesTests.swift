import XCTest
@testable import MushroomSignalCore

final class RegionBoundariesTests: XCTestCase {
    func testEveryRegionHasAPolygon() {
        for region in RegionDatabase.all {
            let polygon = RegionBoundaries.polygon(for: region.id)
            XCTAssertNotNil(polygon, "\(region.id) has no boundary polygon")
            XCTAssertGreaterThanOrEqual(polygon?.count ?? 0, 3, "\(region.id)'s polygon needs at least 3 points to be a real shape")
        }
    }

    func testEveryPolygonPointFallsWithinSlovakiaGridBounds() {
        for region in RegionDatabase.all {
            guard let polygon = RegionBoundaries.polygon(for: region.id) else { continue }
            for point in polygon {
                XCTAssertTrue(SlovakiaGrid.latitudeRange.contains(point.latitude), "\(region.id) has a point outside the expected latitude range: \(point.latitude)")
                XCTAssertTrue(SlovakiaGrid.longitudeRange.contains(point.longitude), "\(region.id) has a point outside the expected longitude range: \(point.longitude)")
            }
        }
    }

    func testUnknownRegionIdReturnsNil() {
        XCTAssertNil(RegionBoundaries.polygon(for: "not-a-real-region"))
    }
}
