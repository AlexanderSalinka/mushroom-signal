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
        XCTAssertEqual(DesignSystem.warningLabelSk(for: .caution), "⚠️ Možná zámena")
        XCTAssertEqual(DesignSystem.warningLabelSk(for: .poisonous), "⚠️ Jedovatá")
    }

    func testWarningColorIsDistinctPerEdibilityLevel() {
        XCTAssertEqual(DesignSystem.warningColor(for: .edible), DesignSystem.Colors.cloud)
        XCTAssertEqual(DesignSystem.warningColor(for: .caution), DesignSystem.Colors.caution)
        XCTAssertEqual(DesignSystem.warningColor(for: .poisonous), DesignSystem.Colors.danger)
        XCTAssertNotEqual(DesignSystem.warningColor(for: .caution), DesignSystem.warningColor(for: .poisonous))
    }
}
