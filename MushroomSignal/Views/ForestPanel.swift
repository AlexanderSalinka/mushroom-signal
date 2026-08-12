// MushroomSignal/Views/ForestPanel.swift
import SwiftUI
import MushroomSignalCore

/// A frosted-glass section container — wraps each PredpovedView section (chart, top picks,
/// rain alert, season calendar) in a translucent, bordered, shadowed panel, replacing the
/// prior bare-VStack-plus-ForestDivider separation. Modeled on macOS System Settings' pane
/// grouping (approved mockup, style 3 — see
/// docs/superpowers/specs/mockups/2026-08-11-predpoved-beautify/container-style.html).
struct ForestPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(DesignSystem.spacingSmall)
            .background(DesignSystem.Colors.forestDeep.opacity(DesignSystem.panelFillOpacity))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius)
                    .stroke(DesignSystem.Colors.cloud.opacity(DesignSystem.panelBorderOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: DesignSystem.panelShadowRadius, y: 4)
    }
}
