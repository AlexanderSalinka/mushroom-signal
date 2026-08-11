// MushroomSignal/Views/GrainTexture.swift
import SwiftUI
import MushroomSignalCore

/// A very subtle procedural noise overlay for card fills — reads as bark/leaf texture, not
/// visible static. Never applied behind running text or the daily chart (legibility).
private struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 42)
            let dotCount = Int(size.width * size.height / 6)
            for _ in 0..<dotCount {
                let x = CGFloat.random(in: 0...size.width, using: &generator)
                let y = CGFloat.random(in: 0...size.height, using: &generator)
                let shade = Double.random(in: 0...1, using: &generator)
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(shade))
                )
            }
        }
        .blendMode(.overlay)
    }
}

/// Deterministic PRNG so the grain pattern doesn't re-randomize on every view redraw
/// (which would look like animated static instead of a fixed texture).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

extension View {
    func grainTexture() -> some View {
        overlay(
            GrainOverlay()
                .opacity(DesignSystem.grainOpacity)
                .allowsHitTesting(false)
        )
    }
}
