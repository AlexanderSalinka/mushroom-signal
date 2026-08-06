import SwiftUI

public enum DesignSystem {
    public static let goldenRatio: Double = 1.618

    private static let spacingUnit: Double = 8
    public static let spacingSmall: Double = spacingUnit
    public static let spacingMedium: Double = spacingSmall * goldenRatio
    public static let spacingLarge: Double = spacingMedium * goldenRatio
    public static let spacingExtraLarge: Double = spacingLarge * goldenRatio
    /// A tighter-than-`spacingSmall` gap for compact stacked text (e.g. a name directly above its subtitle).
    /// Below the smallest deliberate step in the golden-ratio scale, so it's defined as a fraction of
    /// `spacingSmall` rather than extending the scale downward.
    public static let spacingTight: Double = spacingSmall / 4

    private static let typographyUnit: Double = 8
    public static let captionSize: Double = typographyUnit
    public static let bodySize: Double = captionSize * goldenRatio
    public static let titleSize: Double = bodySize * goldenRatio
    public static let heroSize: Double = titleSize * goldenRatio

    public static let cardCornerRadius: Double = 24
    public static let thumbnailHeight: Double = 70
    public static let borderWidth: Double = 2
    public static let iconButtonPadding: Double = 4
    public static let mapDominantHeightFraction: Double = 0.5
    /// Floor for InteractiveMapView's height so its legend/loading overlay stays legible even if the
    /// window is resized right down to ContentView's declared minHeight.
    public static let mapMinimumHeight: Double = 220

    public enum Colors {
        public static let forestDeep = Color(red: 0.11, green: 0.16, blue: 0.11)
        public static let forestMid = Color(red: 0.18, green: 0.25, blue: 0.16)
        public static let bark = Color(red: 0.29, green: 0.20, blue: 0.13)
        public static let water = Color(red: 0.30, green: 0.48, blue: 0.52)
        public static let cloud = Color(red: 0.94, green: 0.92, blue: 0.87)
        public static let mossAccent = Color(red: 0.42, green: 0.56, blue: 0.30)
        public static let danger = Color(red: 0.72, green: 0.24, blue: 0.20)
        public static let caution = Color(red: 0.85, green: 0.60, blue: 0.13)
        public static let speciesPalette: [Color] = [
            Color(red: 0.90, green: 0.49, blue: 0.13), // amber
            Color(red: 0.36, green: 0.61, blue: 0.84), // sky blue
            Color(red: 0.80, green: 0.36, blue: 0.62), // magenta
            Color(red: 0.95, green: 0.82, blue: 0.25), // gold
            Color(red: 0.42, green: 0.75, blue: 0.70), // teal
            Color(red: 0.65, green: 0.44, blue: 0.86), // violet
            Color(red: 0.85, green: 0.35, blue: 0.32), // coral red
            Color(red: 0.55, green: 0.70, blue: 0.30)  // lime
        ]

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
