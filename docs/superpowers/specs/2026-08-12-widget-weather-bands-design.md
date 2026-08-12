# Widget Temperature + Rain Bands — Design

**Status: approved, implementation-ready.** The deferred widget-integration work from
this morning's hero spec, now specced properly against real mockup iteration instead of
a description of icons that didn't exist yet.

## Why

The widget shows species signals but nothing about the weather driving them. Alexander
wants the same "incoming rain / last rain" fact the app's hero panel shows, plus a
temperature reading, visible in the widget — mocked up interactively (3 approaches, then
iterated to a final direction) rather than designed blind.

## Goals

Two small rectangle "info bands" in the widget — temperature above, rain below — between
the region header and the species rows, using the app's **already-established** visual
language (not new patterns): the exact rounded-rectangle/circle-badge treatment
`rainIncomingSection` used before the hero replaced it, and the existing `DropletShape`
(rain)/`SunriseShape` (warmth) icons already used elsewhere for these exact concepts.

## Out of Scope

- Any change to the app's own hero panel — untouched.
- Any change to the widget's existing species-row list or footer logic.
- Animation — this is the widget; WidgetKit renders a static snapshot per timeline
  refresh, same constraint the hero spec already established for the widget's icon set.

## Design

### Dependency on Item 1

This spec's temperature computation reuses `WeatherSnapshot.derive(regionId:from:
windowDays:asOf:calendar:)`, which the weather-fetch-consolidation design (Item 1) adds.
**Implement this after Item 1 lands**, same ordering dependency Item 3 already has.

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

### `ShortlistWidgetView` — two new bands, shared helper

```swift
private func infoBand(icon: some Shape, color: Color, headline: String, subline: String?) -> some View {
    HStack(spacing: 8) {
        icon
            .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            .frame(width: 11, height: 11)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color.opacity(0.22)))
        VStack(alignment: .leading, spacing: 1) {
            Text(headline)
                .font(.system(size: DesignSystem.captionSize * 0.6, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud)
            if let subline {
                Text(subline)
                    .font(.system(size: DesignSystem.captionSize * 0.5))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.65))
            }
        }
        Spacer(minLength: 0)
    }
    .padding(7)
    .background(color.opacity(0.16))
    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.4))
    .overlay(
        RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.4)
            .stroke(color.opacity(0.4), lineWidth: 1)
    )
}
```

This is a scaled-down, faithful transcription of `rainIncomingSection`'s exact pattern
(`.padding(11)` → `7` for the widget's tighter space, `cardCornerRadius * 0.55` →
`* 0.4`, same `captionSize * 0.65`/`* 0.55` two-tier text sizing, same
circle-badge-with-tinted-fill construction) — not a new visual language. Text sizes stay
below the 20pt floor deliberately, consistent with the floor's existing widget exemption
(2026-08-12) — the same trade-off `rainIncomingSection` itself made at this scale before
being replaced by the hero.

Two call sites, added to `smallBody`/`mediumBody`/`largeBody` between `regionHeader` and
the species-row list:

```swift
private var todayWeather: DailyWeather? {
    entry.dailyWeather.first { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
}

private var tenDayAverage: WeatherSnapshot? {
    WeatherSnapshot.derive(regionId: entry.region.id, from: entry.dailyWeather, asOf: entry.date)
}

private var temperatureHeadline: String {
    guard let todayWeather else {
        guard let tenDayAverage else { return "—" }
        return "\(Int(tenDayAverage.averageTempLast10DaysC.rounded()))°C priemer"
    }
    return "\(Int(todayWeather.minTempC.rounded()))° / \(Int(todayWeather.maxTempC.rounded()))°"
}

private var temperatureSubline: String? {
    guard todayWeather != nil, let tenDayAverage else { return nil }
    return "Priemer 10 dní: \(Int(tenDayAverage.averageTempLast10DaysC.rounded()))°C"
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
        let days = daysBetween(entry.date, event.date)
        return "O \(days) dní · \(String(format: "%.0f", event.precipitationMm))mm a \(Int(event.maxTempC.rounded()))°C"
    }
    if let last = lastRainfall {
        let days = daysBetween(last.date, entry.date)
        return "Naposledy pred \(days) dňami"
    }
    return "Bez výraznejšieho dažďa"
}

private var rainSubline: String? {
    guard upcomingRainEvent != nil, let last = lastRainfall else { return nil }
    let days = daysBetween(last.date, entry.date)
    return "Naposledy pred \(days) dňami"
}

private var temperatureBand: some View {
    infoBand(icon: SunriseShape(), color: DesignSystem.Colors.caution, headline: temperatureHeadline, subline: temperatureSubline)
}

private var rainBand: some View {
    let icon = upcomingRainEvent == nil && lastRainfall == nil ? SunriseShape() : DropletShape()
    return infoBand(icon: icon, color: DesignSystem.Colors.water, headline: rainHeadline, subline: rainSubline)
}
```

`SunriseShape`/`DropletShape` are the existing `ForestIcons.swift` shapes — no new Shape
structs needed. `DesignSystem.Colors.caution` (amber) for temperature matches the exact
color `WeatherRainChartView`'s temp `LineMark` already uses; `DesignSystem.Colors.water`
(blue) for rain matches every other rain-related element in the app.

### Content logic

**Temperature band:** today's min/max from `entry.dailyWeather` if present (matching
`heroSection`'s existing "18° / 28°" app format exactly, not inventing a new one), with
the 10-day average as the subline. Falls back to the 10-day average alone (no subline) if
today's entry isn't in the array (e.g. a stale-cache fallback with only historical days).

**Rain band — the "incoming + last combined" content Alexander picked:**
- If `UpcomingRainDetector.nextTriggerEvent` returns an event: headline is the incoming
  fact ("O 3 dni · 8mm a 24°C" — same phrasing `rainIncomingSection`/the hero already
  use), subline is the last-rain fact if `MostRecentRainfall.find` also returns something
  ("Naposledy pred 5 dňami").
- If no incoming event but `MostRecentRainfall.find` returns something: headline becomes
  the last-rain fact instead, no subline.
- If neither: headline is a quiet "Bez výraznejšieho dažďa" (matching the hero's no-rain
  copy), no subline, `SunriseShape` instead of `DropletShape` (nothing wet to show — an
  outline-cloud-style treatment would be more correct long-term, but reusing the existing
  `SunriseShape`/`DropletShape` pair here avoids adding a third shape just for the
  widget's no-rain case; revisit if this reads as inconsistent once built).

### Layout cost, per family

Two bands cost real vertical space. Verified in the mockup: `.systemSmall` drops from 3
species rows to 1 to fit both bands plus a still-legible list; `.systemMedium` drops to
2; `.systemLarge` (more vertical room already) keeps its existing hero-row-plus-2 layout
unchanged below the bands.

### Testing

- No new unit tests — this is pure SwiftUI View content, same "no View-level test
  infrastructure" convention as the rest of this codebase. `ShortlistEntry` gaining a
  field is a trivial, untestable-in-isolation struct change.
- Verified by building and visually checking all 3 widget families via Xcode preview
  and/or the built widget (subject to this project's pre-existing widget-gallery
  visibility bug, same limitation every prior widget change has worked around, not
  something this task newly solves).
