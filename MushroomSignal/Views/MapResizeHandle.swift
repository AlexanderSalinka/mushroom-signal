// MushroomSignal/Views/MapResizeHandle.swift
import SwiftUI
import MushroomSignalCore

/// Drag handle between the map and the species library grid — lets the map's height be
/// resized freely (down to `mapMinimumHeight`, up to `mapMaximumHeight`, e.g. dragged roughly
/// square against the window's current width) instead of a fixed proportion of the window.
struct MapResizeHandle: View {
    @Binding var height: CGFloat
    @State private var isHovering = false
    @State private var dragStartHeight: CGFloat?

    var body: some View {
        RoundedRectangle(cornerRadius: DesignSystem.borderWidth)
            .fill(DesignSystem.Colors.cloud.opacity(isHovering ? 0.6 : 0.3))
            .frame(width: 48, height: DesignSystem.borderWidth * 2)
            .frame(maxWidth: .infinity)
            .frame(height: DesignSystem.spacingLarge)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                #if canImport(AppKit)
                if hovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
                #endif
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let base = dragStartHeight ?? height
                        dragStartHeight = base
                        let proposed = base + value.translation.height
                        height = min(max(proposed, DesignSystem.mapMinimumHeight), DesignSystem.mapMaximumHeight)
                    }
                    .onEnded { _ in
                        dragStartHeight = nil
                    }
            )
    }
}
