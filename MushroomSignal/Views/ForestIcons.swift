// MushroomSignal/Views/ForestIcons.swift
import SwiftUI

/// Four hand-drawn line icons for the forest visual redesign. Each is a stroked `Shape`
/// normalized to draw within whatever rect it's given — callers size via `.frame(...)` and
/// color via `.stroke(...)`, the same pattern as any SwiftUI `Shape`.

/// An almond-shaped leaf silhouette with a center vein.
struct LeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.02))
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h * 0.95),
            control1: CGPoint(x: x + w * 0.05, y: y + h * 0.2),
            control2: CGPoint(x: x + w * 0.05, y: y + h * 0.8)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h * 0.02),
            control1: CGPoint(x: x + w * 0.95, y: y + h * 0.8),
            control2: CGPoint(x: x + w * 0.95, y: y + h * 0.2)
        )
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.15))
        path.addLine(to: CGPoint(x: x + w * 0.5, y: y + h * 0.9))
        return path
    }
}

/// A classic teardrop/raindrop silhouette.
struct DropletShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y))
        path.addCurve(
            to: CGPoint(x: x + w * 0.92, y: y + h * 0.65),
            control1: CGPoint(x: x + w * 0.5, y: y),
            control2: CGPoint(x: x + w * 0.92, y: y + h * 0.4)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h),
            control1: CGPoint(x: x + w * 0.92, y: y + h * 0.9),
            control2: CGPoint(x: x + w * 0.73, y: y + h)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.08, y: y + h * 0.65),
            control1: CGPoint(x: x + w * 0.27, y: y + h),
            control2: CGPoint(x: x + w * 0.08, y: y + h * 0.9)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y),
            control1: CGPoint(x: x + w * 0.08, y: y + h * 0.4),
            control2: CGPoint(x: x + w * 0.5, y: y)
        )
        path.closeSubpath()
        return path
    }
}

/// A horizon line, a rising sun arc, and three short rays — a warm-day/flush-trigger motif.
struct SunriseShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x, y: y + h * 0.75))
        path.addLine(to: CGPoint(x: x + w, y: y + h * 0.75))

        path.move(to: CGPoint(x: x + w * 0.29, y: y + h * 0.75))
        path.addArc(
            center: CGPoint(x: x + w * 0.5, y: y + h * 0.75),
            radius: w * 0.21,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )

        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.33))
        path.addLine(to: CGPoint(x: x + w * 0.5, y: y + h * 0.13))

        path.move(to: CGPoint(x: x + w * 0.27, y: y + h * 0.46))
        path.addLine(to: CGPoint(x: x + w * 0.12, y: y + h * 0.29))

        path.move(to: CGPoint(x: x + w * 0.73, y: y + h * 0.46))
        path.addLine(to: CGPoint(x: x + w * 0.88, y: y + h * 0.29))

        return path
    }
}

/// A loose scatter of dots, evoking a spore print — used as a filled shape, not stroked.
struct SporeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        let dots: [(cx: CGFloat, cy: CGFloat, r: CGFloat)] = [
            (0.33, 0.33, 0.05), (0.54, 0.25, 0.04), (0.69, 0.44, 0.06),
            (0.42, 0.52, 0.03), (0.29, 0.63, 0.045), (0.58, 0.67, 0.05),
            (0.75, 0.69, 0.035)
        ]
        var path = Path()
        for dot in dots {
            let cx = x + w * dot.cx, cy = y + h * dot.cy, r = min(w, h) * dot.r
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }
        return path
    }
}
