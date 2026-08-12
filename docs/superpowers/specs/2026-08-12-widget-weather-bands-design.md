# Widget Temperature + Rain Bands — Design

**Status: approved, implementation-ready.** The deferred widget-integration work from
this morning's hero spec. Went through 8 rounds of live mockup iteration in the visual
companion (real widget dimensions, real colors, real icon paths) — this version reflects
the final approved result, not the first draft.

## Why

The widget shows species signals but nothing about the weather driving them. Alexander
wants the "incoming rain / last rain" fact the app's hero panel shows, plus a
temperature reading, visible in the widget — and, once that was working, wanted the
widget's information density pushed further: bigger header text, more species shown per
family, and a proper top-3 "podium" treatment for the large family instead of a single
hero row.

## Goals

Temperature and rain info visible in every widget family, a denser species list than
today's, and a centered region header showing date + time (not just a bare region name).
Reuses the app's established visual language throughout — no new patterns invented where
an existing one already fits.

## Out of Scope

- Any change to the app's own hero panel — untouched.
- Animation — WidgetKit renders a static snapshot per timeline refresh, same constraint
  the hero spec already established for the widget's icon set.
- The aggregate "⚠️ obsahuje jedovaté" footer banner — **removed** by explicit request
  (see Region Header / Footer below), not merely out of scope.

## Design

### Dependency on Item 1

Temperature computation reuses `WeatherSnapshot.derive(regionId:from:windowDays:asOf:
calendar:)`, which the weather-fetch-consolidation design (Item 1) adds. **Implement
this after Item 1 lands**, same ordering dependency Item 3 already has.

### Data: `ShortlistEntry` gains the daily weather array

```swift
struct ShortlistEntry: TimelineEntry {
    let date: Date
    let region: Region
    let signals: [SpeciesSignal]
    let dailyWeather: [DailyWeather]
}
```

`ShortlistProvider.fetchEntry` (post Item 8's widget-fetch-unification) already has this
array in scope from its single `fetchDailyBreakdown` call — no new fetch, just threading
an existing value through one more field.

### Shared icons move to `MushroomSignalCore`

The widget bands need `DropletShape` and `SunriseShape`, and the large family's podium
squares need a new generic single-mushroom icon — but `ForestIcons.swift` lives in
`MushroomSignal/Views/` (the app target), which the widget extension target cannot see.
Fix: move `DropletShape` and `SunriseShape` out of `ForestIcons.swift` into a new file,
`MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/SharedIcons.swift`, marked
`public` (matching `DesignSystem.swift`'s own precedent of `import SwiftUI` inside
`MushroomSignalCore` — this isn't a new pattern for the package). Add the new mushroom
icon there too, since it's needed by the widget from the start:

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/SharedIcons.swift
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
```

`ForestIcons.swift` deletes its own `DropletShape`/`SunriseShape` definitions; every
existing app-side call site (`rainIncomingSection`'s old usage — now the hero panel's
badges, `heroSection`'s droplet, `seasonRow`'s leaf, etc.) keeps working unchanged since
`MushroomSignal` already `import MushroomSignalCore` everywhere these are used — only
the shapes' defining file/module changes, not their names or call sites.

### Region header — centered, date + time, no footer

```swift
private static let headerDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "sk_SK")
    formatter.dateFormat = "d. MMMM · HH:mm"
    return formatter
}()

private var regionHeader: some View {
    VStack(spacing: 1) {
        Text(entry.region.nameSk)
            .font(.system(size: DesignSystem.captionSize * 0.65, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.85))
        Text(Self.headerDateFormatter.string(from: entry.date))
            .font(.system(size: DesignSystem.captionSize * 0.55))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.55))
    }
    .frame(maxWidth: .infinity)
}
```

Locale forced to `sk_SK` — same rationale as `MushroomSignalHeroView.monthFormatter`
(2026-08-12): every string in this app is Slovak, and an unforced formatter would
silently render English month names on a non-Slovak-locale device.

**The footer is removed entirely** (Alexander's explicit call): the existing aggregate
`"⚠️ obsahuje jedovaté"` banner goes away. This does not remove safety information —
`row()`/`heroRow()` already prefix an individual poisonous/caution species' name with
`"⚠️ "` and color it via `DesignSystem.warningColor(for:)`, per-row, and that's
unchanged. Only the redundant widget-level aggregate banner is cut, and only because the
time it used to show now lives in the header instead.

### Weather tiles

Two pieces of content, computed once per render:

```swift
private var sevenDayAverage: WeatherSnapshot? {
    WeatherSnapshot.derive(regionId: entry.region.id, from: entry.dailyWeather, windowDays: 7, asOf: entry.date)
}

private var todayWeather: DailyWeather? {
    entry.dailyWeather.first { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
}

private var temperatureHeadline: String {
    guard let todayWeather else { return "—" }
    return "\(Int(todayWeather.minTempC.rounded()))° / \(Int(todayWeather.maxTempC.rounded()))°"
}

private var temperatureSubline: String? {
    guard let sevenDayAverage else { return nil }
    return "Týždenný priemer: \(Int(sevenDayAverage.averageTempLast10DaysC.rounded()))°C"
}

private var upcomingRainEvent: RainEvent? {
    UpcomingRainDetector.nextTriggerEvent(in: entry.dailyWeather, asOf: entry.date)
}

private var lastRainfall: (date: Date, precipitationMm: Double)? {
    MostRecentRainfall.find(in: entry.dailyWeather, asOf: entry.date)
}

private func daysBetween(_ from: Date, _ to: Date) -> Int {
    max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from), to: Calendar.current.startOfDay(for: to)).day ?? 1)
}

private var rainHeadline: String {
    if let event = upcomingRainEvent {
        return "O \(daysBetween(entry.date, event.date)) dní · \(String(format: "%.0f", event.precipitationMm)) mm"
    }
    if let last = lastRainfall {
        return "Naposledy pred \(daysBetween(last.date, entry.date)) dňami"
    }
    return "Bez výraznejšieho dažďa"
}

private var rainSubline: String? {
    guard let last = lastRainfall else { return nil }
    if upcomingRainEvent != nil {
        return "Naposledy pred \(daysBetween(last.date, entry.date)) dňami · \(String(format: "%.0f", last.precipitationMm)) mm"
    }
    return "\(String(format: "%.0f", last.precipitationMm)) mm"
}
```

`WeatherSnapshot.derive`'s `windowDays` overridden to **7** (not the 10-day default) —
Alexander's explicit call, and the field is now explicitly labeled "týždenný" (weekly),
matching the window. The rain headline no longer includes temperature (`WeatherSnapshot`
already covers that in its own tile) — just days-until and mm. The last-rain fact now
always includes mm, both as the sole rain fact (no incoming event) and as the subline
next to an incoming event.

**`.systemSmall`: unchanged stacked layout** — two full-width rounded-rectangle bands,
temperature above rain, using the same circle-badge-plus-text pattern the original
`rainIncomingSection` established (`infoBand(icon:color:headline:subline:)` helper,
unchanged from the first draft of this spec). Alexander confirmed this reads well as-is
and asked for no further change to `.systemSmall`'s band layout.

**`.systemMedium`/`.systemLarge`: side-by-side square tiles**, not stacked bands —
addresses Alexander's "too much empty space" feedback on the wide-band layout at these
larger widths:

```swift
private func squareTile(icon: some Shape, color: Color, headline: String, subline: String?) -> some View {
    VStack(spacing: 1) {
        icon
            .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .frame(width: 12, height: 12)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color.opacity(0.25)))
        Text(headline)
            .font(.system(size: DesignSystem.captionSize * 0.65, weight: .bold))
            .foregroundStyle(DesignSystem.Colors.cloud)
        if let subline {
            Text(subline)
                .font(.system(size: DesignSystem.captionSize * 0.5))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                .multilineTextAlignment(.center)
        }
    }
    .frame(maxWidth: .infinity)
    .padding(6)
    .background(color.opacity(0.18))
    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35))
    .overlay(
        RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35)
            .stroke(color.opacity(0.45), lineWidth: 1)
    )
}

private var weatherTileRow: some View {
    HStack(spacing: 6) {
        squareTile(icon: SunriseShape(), color: DesignSystem.Colors.caution, headline: temperatureHeadline, subline: temperatureSubline)
        squareTile(icon: DropletShape(), color: DesignSystem.Colors.water, headline: rainHeadline, subline: rainSubline)
    }
}
```

Each tile is `flex`-equivalent (`.frame(maxWidth: .infinity)` on equal-weight `HStack`
children) so the pair fills the row with no flanking gaps, but content is centered and
padding is tight enough that neither tile reads as an oversized empty box around small
text — confirmed visually across two mockup rounds (the first attempt still looked
"stretched"; tightening padding and enlarging the headline text to `captionSize * 0.65`
fixed it).

### Species list

**`.systemSmall`**: 4 rows (up from the original 3 — real vertical math after adding the
header's second line and the two bands still leaves room for 4 at this font size,
confirmed visually, not assumed), reusing the existing `row(for:nameFont:showLatin:)`
helper unchanged.

**`.systemMedium`**: 4 rows with inline latin names, same existing `row(...,
inlineLatin: true)` helper, unchanged call pattern.

**`.systemLarge`**: replaces the old single `heroRow` + list entirely with a **top-3
podium row** (three square tiles, one per rank, side by side — same visual language as
the weather tiles, not a full-width card) followed by plain numbered rows for ranks 4
onward:

```swift
private func podiumSquare(rank: Int, signal: SpeciesSignal, isFirst: Bool) -> some View {
    let hasWarning = signal.species.edibility != .edible
    let color = hasWarning ? DesignSystem.warningColor(for: signal.species.edibility) : DesignSystem.Colors.mossAccent
    return VStack(spacing: 2) {
        MushroomShape()
            .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: isFirst ? 30 : 22, height: isFirst ? 30 : 22)
        Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
            .font(.system(size: isFirst ? DesignSystem.captionSize * 0.7 : DesignSystem.captionSize * 0.6, weight: .bold))
            .foregroundStyle(hasWarning ? color : DesignSystem.Colors.cloud)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        Text(String(repeating: "●", count: max(0, min(4, signal.score))) + String(repeating: "○", count: 4 - max(0, min(4, signal.score))))
            .font(.system(size: DesignSystem.captionSize * 0.5))
            .foregroundStyle(DesignSystem.Colors.mossAccent)
    }
    .frame(maxWidth: .infinity)
    .padding(8)
    .background((hasWarning ? color : DesignSystem.Colors.mossAccent).opacity(isFirst ? 0.26 : 0.16))
    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35))
    .overlay(
        RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35)
            .stroke((hasWarning ? color : DesignSystem.Colors.mossAccent).opacity(isFirst ? 0.6 : 0.4), lineWidth: 1)
    )
}

private func rankedRow(rank: Int, signal: SpeciesSignal) -> some View {
    let hasWarning = signal.species.edibility != .edible
    let color = hasWarning ? DesignSystem.warningColor(for: signal.species.edibility) : DesignSystem.Colors.cloud
    return HStack(spacing: 8) {
        Text("\(rank)")
            .font(.system(size: DesignSystem.captionSize * 0.55))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.4))
            .frame(width: 14, alignment: .trailing)
        Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
            .font(.system(size: DesignSystem.captionSize * 0.7, weight: .semibold))
            .foregroundStyle(color)
        Spacer()
        Text(String(repeating: "●", count: max(0, min(4, signal.score))) + String(repeating: "○", count: 4 - max(0, min(4, signal.score))))
            .font(.system(size: DesignSystem.captionSize * 0.55))
            .foregroundStyle(DesignSystem.Colors.mossAccent)
    }
}
```

`.systemLarge` shows up to **9 species total**: 3 in the podium row, 6 more as ranked
rows — chosen because the frame's actual available height (after header, weather tiles,
and podium row) was still roughly half-empty at the old hero-row-plus-2 count (3 total),
confirmed by rendering the mockup at real proportions, not assumed.

### Testing

- No new unit tests — this is pure SwiftUI View content, same "no View-level test
  infrastructure" convention as the rest of this codebase. `ShortlistEntry` gaining a
  field is a trivial, untestable-in-isolation struct change.
- `MushroomSignalCore`'s `SharedIcons.swift` shapes are pure geometry, same
  no-test-precedent as `ForestIcons.swift`'s existing shapes (confirmed during the hero
  work, 2026-08-12) — not newly introducing a gap.
- Verified by building and visually checking all 3 widget families via Xcode preview
  and/or the built widget (subject to this project's pre-existing widget-gallery
  visibility bug, same limitation every prior widget change has worked around, not
  something this task newly solves).
