import XCTest
@testable import MushroomSignalCore

final class DesignSystemTests: XCTestCase {
    func testSpacingScaleIsIncreasing() {
        XCTAssertLessThan(DesignSystem.spacingSmall, DesignSystem.spacingMedium)
        XCTAssertLessThan(DesignSystem.spacingMedium, DesignSystem.spacingLarge)
        XCTAssertLessThan(DesignSystem.spacingLarge, DesignSystem.spacingExtraLarge)
    }

    func testSpacingRatiosApproximateGoldenRatio() {
        let ratio1 = DesignSystem.spacingMedium / DesignSystem.spacingSmall
        let ratio2 = DesignSystem.spacingLarge / DesignSystem.spacingMedium
        XCTAssertEqual(ratio1, DesignSystem.goldenRatio, accuracy: 0.001)
        XCTAssertEqual(ratio2, DesignSystem.goldenRatio, accuracy: 0.001)
    }

    func testWarningLabelSkIsNilOnlyForEdible() {
        XCTAssertNil(DesignSystem.warningLabelSk(for: .edible))
        XCTAssertEqual(DesignSystem.warningLabelSk(for: .caution), "⚠️ Opatrne")
        XCTAssertEqual(DesignSystem.warningLabelSk(for: .poisonous), "⚠️ Jedovatá")
    }

    func testWarningColorIsDistinctPerEdibilityLevel() {
        XCTAssertEqual(DesignSystem.warningColor(for: .edible), DesignSystem.Colors.cloud)
        XCTAssertEqual(DesignSystem.warningColor(for: .caution), DesignSystem.Colors.caution)
        XCTAssertEqual(DesignSystem.warningColor(for: .poisonous), DesignSystem.Colors.danger)
        XCTAssertNotEqual(DesignSystem.warningColor(for: .caution), DesignSystem.warningColor(for: .poisonous))
    }

    func testTypographyScaleIsIncreasing() {
        XCTAssertLessThan(DesignSystem.captionSize, DesignSystem.bodySize)
        XCTAssertLessThan(DesignSystem.bodySize, DesignSystem.titleSize)
        XCTAssertLessThan(DesignSystem.titleSize, DesignSystem.heroSize)
    }

    func testTypographyScaleMeetsThe20ptFloor() {
        // 2026-08-08: the typography scale deliberately abandoned the golden-ratio
        // relationship (mechanically reapplying it from a 20pt floor would push heroSize to
        // ~85pt) in favor of a gentler progression that still clears the floor everywhere.
        XCTAssertGreaterThanOrEqual(DesignSystem.captionSize, 20)
        XCTAssertGreaterThanOrEqual(DesignSystem.bodySize, 20)
        XCTAssertGreaterThanOrEqual(DesignSystem.titleSize, 20)
        XCTAssertGreaterThanOrEqual(DesignSystem.heroSize, 20)
    }

    func testPanelOpacitiesAreValidRange() {
        XCTAssertGreaterThan(DesignSystem.panelFillOpacity, 0)
        XCTAssertLessThanOrEqual(DesignSystem.panelFillOpacity, 1)
        XCTAssertGreaterThan(DesignSystem.panelBorderOpacity, 0)
        XCTAssertLessThanOrEqual(DesignSystem.panelBorderOpacity, 1)
    }

    func testSeasonRowMinWidthMeetsMobileWidthFloor() {
        XCTAssertGreaterThanOrEqual(DesignSystem.seasonRowMinWidth, 375)
    }
}
