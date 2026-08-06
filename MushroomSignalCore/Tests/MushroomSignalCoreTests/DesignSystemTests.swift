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

    func testTypographyRatiosApproximateGoldenRatio() {
        let ratio1 = DesignSystem.bodySize / DesignSystem.captionSize
        let ratio2 = DesignSystem.titleSize / DesignSystem.bodySize
        let ratio3 = DesignSystem.heroSize / DesignSystem.titleSize
        XCTAssertEqual(ratio1, DesignSystem.goldenRatio, accuracy: 0.001)
        XCTAssertEqual(ratio2, DesignSystem.goldenRatio, accuracy: 0.001)
        XCTAssertEqual(ratio3, DesignSystem.goldenRatio, accuracy: 0.001)
    }
}
