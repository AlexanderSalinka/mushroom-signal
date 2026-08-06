import XCTest
import SwiftUI
@testable import MushroomSignalCore

final class SpeciesColorAssignerTests: XCTestCase {
    func testAssignsDistinctColorsInToggleOrder() {
        let result = SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: ["a", "b", "c"])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result["a"], DesignSystem.Colors.speciesPalette[0])
        XCTAssertEqual(result["b"], DesignSystem.Colors.speciesPalette[1])
        XCTAssertEqual(result["c"], DesignSystem.Colors.speciesPalette[2])
    }

    func testCyclesPaletteWhenMoreSpeciesThanColors() {
        let paletteSize = DesignSystem.Colors.speciesPalette.count
        let ids = (0..<(paletteSize + 2)).map { "species-\($0)" }
        let result = SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: ids)
        XCTAssertEqual(result[ids[0]], result[ids[paletteSize]], "should wrap back to the first color")
    }

    func testEmptyInputReturnsEmptyMapping() {
        XCTAssertTrue(SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: []).isEmpty)
    }
}
