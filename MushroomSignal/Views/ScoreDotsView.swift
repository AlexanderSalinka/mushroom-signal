// MushroomSignal/Views/ScoreDotsView.swift
import SwiftUI

struct ScoreDotsView: View {
    let score: Int
    let color: Color
    let dotSize: Double

    var body: some View {
        let clamped = max(0, min(4, score))
        Text(String(repeating: "●", count: clamped) + String(repeating: "○", count: 4 - clamped))
            .font(.system(size: dotSize))
            .foregroundStyle(color)
    }
}
