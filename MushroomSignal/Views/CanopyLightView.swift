// MushroomSignal/Views/CanopyLightView.swift
import SwiftUI
import AppKit
import MushroomSignalCore

/// The forest redesign's signature move: 2-3 soft, irregularly-shaped, warm-toned light
/// blobs layered under the glass vibrancy — like sunlight breaking through leaves, replacing
/// a flat tint. Drift animation is skipped entirely when the system requests reduced motion;
/// the glow itself still renders, just static.
struct CanopyLightView: View {
    @State private var animate = false

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                blob(cx: 0.2, cy: 0.05, w: 0.6, h: 0.4, driftX: 14, driftY: 10, rotation: 4)
                blob(cx: 0.85, cy: 0.75, w: 0.42, h: 0.34, driftX: -10, driftY: -12, rotation: -3, opacity: 0.75)
                blob(cx: 0.05, cy: 0.5, w: 0.3, h: 0.22, driftX: 9, driftY: -6, rotation: 3, opacity: 0.55)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            guard !reduceMotion else { return }
            animate = true
        }
        .allowsHitTesting(false)
    }

    private func blob(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat, driftX: CGFloat, driftY: CGFloat, rotation: Double, opacity: Double = 1.0) -> some View {
        GeometryReader { geo in
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [DesignSystem.Colors.cloud.opacity(0.9), DesignSystem.Colors.caution.opacity(0.3), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: geo.size.width * w * 0.5
                    )
                )
                .frame(width: geo.size.width * w, height: geo.size.height * h)
                .position(x: geo.size.width * cx, y: geo.size.height * cy)
                .blur(radius: 24)
                .blendMode(.softLight)
                .opacity(opacity)
                .offset(x: animate ? driftX : 0, y: animate ? driftY : 0)
                .rotationEffect(.degrees(animate ? rotation : 0))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 26).repeatForever(autoreverses: true),
                    value: animate
                )
        }
    }
}
