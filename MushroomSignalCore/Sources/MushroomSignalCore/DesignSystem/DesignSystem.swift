import SwiftUI

public enum DesignSystem {
    public static let goldenRatio: Double = 1.618

    private static let spacingUnit: Double = 8
    public static let spacingSmall: Double = spacingUnit
    public static let spacingMedium: Double = spacingSmall * goldenRatio
    public static let spacingLarge: Double = spacingMedium * goldenRatio
    public static let spacingExtraLarge: Double = spacingLarge * goldenRatio

    public static let cardCornerRadius: Double = 24

    public enum Colors {
        public static let forestDeep = Color(red: 0.11, green: 0.16, blue: 0.11)
        public static let forestMid = Color(red: 0.18, green: 0.25, blue: 0.16)
        public static let bark = Color(red: 0.29, green: 0.20, blue: 0.13)
        public static let water = Color(red: 0.30, green: 0.48, blue: 0.52)
        public static let cloud = Color(red: 0.94, green: 0.92, blue: 0.87)
        public static let mossAccent = Color(red: 0.42, green: 0.56, blue: 0.30)
        public static let danger = Color(red: 0.72, green: 0.24, blue: 0.20)
        public static let caution = Color(red: 0.85, green: 0.60, blue: 0.13)

        public static let cardBackground = LinearGradient(
            colors: [forestMid, forestDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The Slovak warning label for a species' edibility, or nil when no warning applies.
    public static func warningLabelSk(for edibility: Edibility) -> String? {
        switch edibility {
        case .edible: return nil
        case .caution: return "⚠️ Opatrne"
        case .poisonous: return "⚠️ Jedovatá"
        }
    }

    /// The color a warning label/highlight should use for a species' edibility.
    public static func warningColor(for edibility: Edibility) -> Color {
        switch edibility {
        case .edible: return Colors.cloud
        case .caution: return Colors.caution
        case .poisonous: return Colors.danger
        }
    }
}
