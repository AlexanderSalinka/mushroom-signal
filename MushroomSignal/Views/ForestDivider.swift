import SwiftUI
import MushroomSignalCore

/// A 1pt bark-toned divider, replacing ad hoc separators between PredpovedView's sections.
struct ForestDivider: View {
    var body: some View {
        LinearGradient(
            colors: [DesignSystem.Colors.bark, .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .opacity(DesignSystem.forestDividerOpacity)
    }
}
