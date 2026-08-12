import SwiftUI

/// Shapes shared between the app and widget extension targets — ForestIcons.swift
/// (MushroomSignal/Views/) holds app-only shapes; anything the widget also needs to draw
/// lives here instead, since the widget extension can't see app-target source files.

public struct DropletShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
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

public struct SunriseShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
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

/// A generic single mushroom (cap + stem, gill lines beneath the cap) — the widget's
/// top-3 podium squares. Deliberately distinct from the hero's `MushroomCapShape` (a
/// three-cap-burst animation motif, app-only, not a static per-species icon).
public struct MushroomShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.2, y: y + h * 0.5))
        path.addCurve(
            to: CGPoint(x: x + w * 0.8, y: y + h * 0.5),
            control1: CGPoint(x: x + w * 0.2, y: y + h * 0.05),
            control2: CGPoint(x: x + w * 0.8, y: y + h * 0.05)
        )
        path.move(to: CGPoint(x: x + w * 0.4, y: y + h * 0.55))
        path.addCurve(
            to: CGPoint(x: x + w * 0.4, y: y + h * 0.85),
            control1: CGPoint(x: x + w * 0.4, y: y + h * 0.55),
            control2: CGPoint(x: x + w * 0.4, y: y + h * 0.85)
        )
        path.addLine(to: CGPoint(x: x + w * 0.6, y: y + h * 0.85))
        path.addLine(to: CGPoint(x: x + w * 0.6, y: y + h * 0.55))
        path.move(to: CGPoint(x: x + w * 0.325, y: y + h * 0.45))
        path.addCurve(
            to: CGPoint(x: x + w * 0.675, y: y + h * 0.45),
            control1: CGPoint(x: x + w * 0.45, y: y + h * 0.325),
            control2: CGPoint(x: x + w * 0.55, y: y + h * 0.325)
        )
        return path
    }
}
