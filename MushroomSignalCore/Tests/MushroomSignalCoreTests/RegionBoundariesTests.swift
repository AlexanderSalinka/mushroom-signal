import XCTest
@testable import MushroomSignalCore

final class RegionBoundariesTests: XCTestCase {
    func testEveryRegionHasAPolygon() {
        for region in RegionDatabase.all {
            let polygon = RegionBoundaries.polygon(for: region.id)
            XCTAssertNotNil(polygon, "\(region.id) has no boundary polygon")
            XCTAssertGreaterThanOrEqual(polygon?.count ?? 0, 35, "\(region.id)'s polygon needs at least 35 points per the 2026-08-08 density requirement")
        }
    }

    func testAdjacentRegionsShareBorderPoints() {
        // Mirrors real Slovak kraj adjacency. Borders are built from a shared node graph
        // (see the generation notes in RegionBoundaries.swift) specifically so adjacent
        // regions provably touch — this asserts that construction actually holds, not just
        // that it was intended to.
        let adjacentPairs: [(String, String)] = [
            ("bratislavsky", "trnavsky"), ("trnavsky", "trenciansky"), ("trnavsky", "nitriansky"),
            ("trenciansky", "nitriansky"), ("trenciansky", "zilinsky"), ("trenciansky", "banskobystricky"),
            ("nitriansky", "banskobystricky"), ("zilinsky", "banskobystricky"), ("zilinsky", "presovsky"),
            ("banskobystricky", "presovsky"), ("banskobystricky", "kosicky"), ("presovsky", "kosicky"),
        ]

        for (a, b) in adjacentPairs {
            guard let polygonA = RegionBoundaries.polygon(for: a), let polygonB = RegionBoundaries.polygon(for: b) else {
                XCTFail("missing polygon for \(a) or \(b)")
                continue
            }
            let pointsA = Set(polygonA.map { "\($0.latitude),\($0.longitude)" })
            let pointsB = Set(polygonB.map { "\($0.latitude),\($0.longitude)" })
            XCTAssertFalse(pointsA.isDisjoint(with: pointsB), "\(a) and \(b) are adjacent but share no border points")
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
