# Forest Glass Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the forest-themed visual redesign of `PredpovedView` — canopy-light glass, compact species cards, forest glyphs, grain texture, a simplified rain/heat chart, and a new forward-looking rain alert — exactly matching the three approved mockups.

**Architecture:** Almost entirely SwiftUI view code plus two small pure-logic additions (`SpeciesSignal.flushTriggered`, `UpcomingRainDetector`) in `MushroomSignalCore`. No new network calls — every new view reads data already fetched by `AppState`/`RegionWeatherState`.

**Tech Stack:** Swift 5, SwiftUI, Swift Charts, XCTest. macOS 14+ target (`MushroomSignal.xcodeproj`, generated via `xcodegen generate` from `project.yml` — never hand-edit the `.xcodeproj`).

## Global Constraints

- Spec source of truth: `docs/superpowers/specs/2026-08-11-forest-glass-visual-redesign-design.md`. Final visual source of truth: the three approved mockups referenced in that spec's Testing section (`predpoved-full-tab.html` is the final word on section order/content).
- All new styling routes through `DesignSystem` (`MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`) — no hardcoded ad hoc colors/sizes (project-wide rule, `CLAUDE.md`).
- No new `WeatherClient` fetches anywhere in this plan — `RegionWeatherState.dailyWeather` (already loaded, `pastDays: 10, forecastDays: 5`) is the only data source for both the chart and the rain alert.
- Grain texture never renders behind running text or the chart's data marks (spec §4/§6).
- SF Pro stays the only typeface everywhere — no display-typeface change (spec: Fraunces explicitly rejected).
- Every build command uses `-derivedDataPath DerivedData` (repo-relative, gitignored) per `CLAUDE.md` — prevents duplicate Launch Services registrations.
- Commit after every task. One task = one commit (plus any same-task fix-up commits if a step fails and needs correcting).
- Do not touch `~/.claude/CLAUDE.md`. Do not modify `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` until Task 14 (explicitly the last task, per Alexander's own instruction that the version bump happens once this work ships).

---

## File Structure

**New files:**
- `MushroomSignalCore/Sources/MushroomSignalCore/Signal/UpcomingRainDetector.swift` — pure forward-looking trigger scan + `RainEvent`
- `MushroomSignalCore/Tests/MushroomSignalCoreTests/UpcomingRainDetectorTests.swift`
- `MushroomSignal/Views/ForestIcons.swift` — 4 SwiftUI `Shape`s (leaf, droplet, sunrise, spore)
- `MushroomSignal/Views/CanopyLightView.swift` — the dappled-light layer
- `MushroomSignal/Views/GrainTexture.swift` — `.grainTexture()` view modifier
- `MushroomSignal/Views/ForestDivider.swift` — the `bark`-toned section divider
- `MushroomSignal/Views/CompactSpeciesCardView.swift` — the new "glass button" card

**Modified files:**
- `MushroomSignalCore/Sources/MushroomSignalCore/Signal/FlushTriggerDetector.swift` — expose shared threshold constants
- `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SpeciesSignal.swift` — add `flushTriggered: Bool`
- `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift` — thread `flushTriggered` into the two `SpeciesSignal` constructions
- `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift` — new tokens
- `MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift` — mechanical update for the new required init parameter
- `MushroomSignalWidget/ShortlistWidgetView.swift` — same, in its preview helper
- `MushroomSignal/Views/GlassBackground.swift` — wire in `CanopyLightView`
- `MushroomSignal/Views/SpeciesCardView.swift` — sunrise glyph next to reason text when triggered
- `MushroomSignal/Views/PredpovedView.swift` — full rebuild of body: new section order, new chart, new top-picks card, new rain section, leaf-glyph season chips

---

### Task 1: `SpeciesSignal.flushTriggered` + shared trigger-condition constants

Today, whether a signal was flush-triggered is only encoded as a specific Slovak sentence inside `signal.reason` (`SignalAlgorithm.reasonText`'s first branch). The new sunrise glyph (Task 8) needs a real boolean to check, not a string comparison against reason text. `computeSignal` already receives `flushTriggered: Bool` as a parameter — it's just never stored on the result. Fix that, and while touching `FlushTriggerDetector`, promote its inline `26.0`/`5.0` literals to named constants so `UpcomingRainDetector` (Task 2) can reuse the exact same numbers instead of duplicating them.

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/FlushTriggerDetector.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SpeciesSignal.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift:8,20`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift` (9 call sites)
- Modify: `MushroomSignalWidget/ShortlistWidgetView.swift:162` (preview helper)
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift`

**Interfaces:**
- Produces: `FlushTriggerDetector.minTriggerMaxTempC: Double`, `FlushTriggerDetector.minTriggerPrecipitationMm: Double` (both `public static let`); `SpeciesSignal.flushTriggered: Bool` (new stored property, part of the memberwise-style `init`).

- [ ] **Step 1: Write the failing test for `SpeciesSignal.flushTriggered`**

Add to `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift` (open the file first to match its existing species-fixture helper — reuse it rather than redefining one; if the file has no `makeSpecies` helper, use the same pattern as `FlushTriggerDetectorTests.swift`'s fixtures, adapted for `Species`/`WeatherSnapshot`):

```swift
func testComputeSignalStoresFlushTriggeredTrue() {
    let species = makeSpecies(rainfallSensitivity: .high)
    let weather = makeWeather() // any in-range snapshot
    let signal = SignalAlgorithm.computeSignal(species: species, weather: weather, month: 9, flushTriggered: true)
    XCTAssertTrue(signal.flushTriggered)
}

func testComputeSignalStoresFlushTriggeredFalse() {
    let species = makeSpecies(rainfallSensitivity: .high)
    let weather = makeWeather()
    let signal = SignalAlgorithm.computeSignal(species: species, weather: weather, month: 9, flushTriggered: false)
    XCTAssertFalse(signal.flushTriggered)
}
```

(Match whatever the file's existing helpers are actually named — read the file first; do not invent helper names that don't exist there.)

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter SignalAlgorithmTests 2>&1 | tail -30`
Expected: FAIL — `value of type 'SpeciesSignal' has no member 'flushTriggered'`

- [ ] **Step 3: Add named constants to `FlushTriggerDetector`**

```swift
public enum FlushTriggerDetector {
    /// Minimum same-day max temperature for a day to count toward a flush trigger.
    public static let minTriggerMaxTempC: Double = 26.0
    /// Minimum same-day rainfall for a day to count toward a flush trigger.
    public static let minTriggerPrecipitationMm: Double = 5.0

    public static func triggered(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> Bool {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        return dailyWeather.contains { day in
            let dayStart = utcCalendar.startOfDay(for: day.date)
            guard let daysAgo = utcCalendar.dateComponents([.day], from: dayStart, to: todayStart).day else { return false }
            guard (2...7).contains(daysAgo) else { return false }
            return day.maxTempC >= minTriggerMaxTempC && day.precipitationMm >= minTriggerPrecipitationMm
        }
    }
}
```

- [ ] **Step 4: Add `flushTriggered` to `SpeciesSignal`**

```swift
public struct SpeciesSignal: Equatable, Sendable {
    public let species: Species
    public let score: Int
    public let reason: String?
    public let flushTriggered: Bool

    public init(species: Species, score: Int, reason: String?, flushTriggered: Bool) {
        self.species = species
        self.score = score
        self.reason = reason
        self.flushTriggered = flushTriggered
    }
}
```

- [ ] **Step 5: Update `SignalAlgorithm`'s two constructions**

In `SignalAlgorithm.swift`, line 8:
```swift
return SpeciesSignal(species: species, score: 0, reason: "mimo hlavnej sezóny", flushTriggered: flushTriggered)
```
Line 20:
```swift
return SpeciesSignal(species: species, score: min(4, max(0, score)), reason: reason, flushTriggered: flushTriggered)
```

- [ ] **Step 6: Fix every other `SpeciesSignal(...)` call site (compiler will point you at each one)**

Run: `swift build --package-path MushroomSignalCore 2>&1 | grep error`

This will list every construction missing the new argument. For `ShortlistRankerTests.swift`'s 9 call sites, add `flushTriggered: false` to each (none of those tests exercise flush-trigger behavior — this is purely mechanical). Example transformation:
```swift
// before
SpeciesSignal(species: makeSpecies(id: "a", name: "A", edibility: .edible), score: 1, reason: nil),
// after
SpeciesSignal(species: makeSpecies(id: "a", name: "A", edibility: .edible), score: 1, reason: nil, flushTriggered: false),
```
For `MushroomSignalWidget/ShortlistWidgetView.swift:162`'s `previewSignal` helper, add `flushTriggered: false` to its `SpeciesSignal(...)` construction the same way — it's preview-only sample data.

- [ ] **Step 7: Run tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter SignalAlgorithmTests 2>&1 | tail -30`
Expected: PASS

Run full core suite to confirm nothing else broke: `swift test --package-path MushroomSignalCore 2>&1 | tail -15`
Expected: all tests pass (should be 82 + 2 new = 84, or whatever the current baseline is +2)

- [ ] **Step 8: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/FlushTriggerDetector.swift \
        MushroomSignalCore/Sources/MushroomSignalCore/Signal/SpeciesSignal.swift \
        MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift \
        MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift \
        MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift \
        MushroomSignalWidget/ShortlistWidgetView.swift
git commit -m "feat: store flushTriggered on SpeciesSignal, share trigger constants"
```

---

### Task 2: `UpcomingRainDetector` + `RainEvent`

Forward-looking counterpart to `FlushTriggerDetector`: scans the *forecast* portion of `dailyWeather` for the earliest day meeting the exact same condition, using Task 1's shared constants.

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/UpcomingRainDetector.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/UpcomingRainDetectorTests.swift`

**Interfaces:**
- Consumes: `FlushTriggerDetector.minTriggerMaxTempC`, `FlushTriggerDetector.minTriggerPrecipitationMm` (Task 1); `DailyWeather` (existing).
- Produces: `RainEvent` struct (`date`, `precipitationMm`, `maxTempC`, `flushWindowStart`, `flushWindowEnd`); `UpcomingRainDetector.nextTriggerEvent(in:asOf:calendar:) -> RainEvent?`.

- [ ] **Step 1: Write the failing tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/UpcomingRainDetectorTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class UpcomingRainDetectorTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func daysFromNow(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, minTempC: maxTempC - 10, precipitationMm: precipitationMm, humidityPercent: 70)
    }

    func testReturnsNilWhenNoForecastDayQualifies() {
        let days = [
            daysFromNow(1, maxTempC: 20.0, precipitationMm: 0.0),
            daysFromNow(2, maxTempC: 27.0, precipitationMm: 2.0), // rain too low
            daysFromNow(3, maxTempC: 24.0, precipitationMm: 8.0)  // temp too low
        ]
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today))
    }

    func testReturnsEventWhenBothThresholdsMetOnSameDay() {
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        let event = UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today)
        XCTAssertEqual(event?.precipitationMm, 11.0)
        XCTAssertEqual(event?.maxTempC, 28.0)
    }

    func testRainAloneWithoutHeatDoesNotQualify() {
        let days = [daysFromNow(2, maxTempC: 20.0, precipitationMm: 20.0)]
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today))
    }

    func testHeatAloneWithoutRainDoesNotQualify() {
        let days = [daysFromNow(2, maxTempC: 30.0, precipitationMm: 0.0)]
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today))
    }

    func testReturnsEarliestQualifyingDayWhenMultipleQualify() {
        let days = [
            daysFromNow(4, maxTempC: 29.0, precipitationMm: 15.0),
            daysFromNow(1, maxTempC: 27.0, precipitationMm: 6.0)
        ]
        let event = UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today)
        XCTAssertEqual(event?.date, today.addingTimeInterval(86400))
    }

    func testIgnoresPastDaysEvenIfTheyQualify() {
        let pastQualifying = DailyWeather(date: today.addingTimeInterval(-2 * 86400), meanTempC: 25, maxTempC: 30, minTempC: 20, precipitationMm: 10, humidityPercent: 70)
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: [pastQualifying], asOf: today))
    }

    func testWindowIsTwoToSevenDaysAfterTriggerDay() {
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        let event = UpcomingRainDetector.nextTriggerEvent(in: days, asOf: today)
        XCTAssertEqual(event?.flushWindowStart, event?.date.addingTimeInterval(2 * 86400))
        XCTAssertEqual(event?.flushWindowEnd, event?.date.addingTimeInterval(7 * 86400))
    }

    func testEmptyArrayReturnsNil() {
        XCTAssertNil(UpcomingRainDetector.nextTriggerEvent(in: [], asOf: today))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter UpcomingRainDetectorTests 2>&1 | tail -30`
Expected: FAIL — `cannot find 'UpcomingRainDetector' in scope`

- [ ] **Step 3: Implement**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Signal/UpcomingRainDetector.swift`:

```swift
import Foundation

/// Forward-looking counterpart to `FlushTriggerDetector`: instead of asking "did a trigger
/// day already happen in the last week" (which feeds today's score), this scans upcoming
/// forecast days for the same condition, so the app can tell the user a flush may be coming
/// before it shows up in the score. Reuses `FlushTriggerDetector`'s exact thresholds — one
/// source of truth, read in both directions.
public enum UpcomingRainDetector {
    public static func nextTriggerEvent(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> RainEvent? {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        let qualifying = dailyWeather
            .filter { $0.date > todayStart }
            .filter { $0.maxTempC >= FlushTriggerDetector.minTriggerMaxTempC && $0.precipitationMm >= FlushTriggerDetector.minTriggerPrecipitationMm }
            .sorted { $0.date < $1.date }

        guard let earliest = qualifying.first else { return nil }

        return RainEvent(
            date: earliest.date,
            precipitationMm: earliest.precipitationMm,
            maxTempC: earliest.maxTempC,
            flushWindowStart: earliest.date.addingTimeInterval(2 * 86400),
            flushWindowEnd: earliest.date.addingTimeInterval(7 * 86400)
        )
    }
}

public struct RainEvent: Equatable, Sendable {
    public let date: Date
    public let precipitationMm: Double
    public let maxTempC: Double
    public let flushWindowStart: Date
    public let flushWindowEnd: Date

    public init(date: Date, precipitationMm: Double, maxTempC: Double, flushWindowStart: Date, flushWindowEnd: Date) {
        self.date = date
        self.precipitationMm = precipitationMm
        self.maxTempC = maxTempC
        self.flushWindowStart = flushWindowStart
        self.flushWindowEnd = flushWindowEnd
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter UpcomingRainDetectorTests 2>&1 | tail -30`
Expected: PASS (8 tests)

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/UpcomingRainDetector.swift \
        MushroomSignalCore/Tests/MushroomSignalCoreTests/UpcomingRainDetectorTests.swift
git commit -m "feat: add UpcomingRainDetector for forward-looking rain+heat alerts"
```

---

### Task 3: Forest glyph set — `ForestIcons.swift`

Four SwiftUI `Shape`s, hand-drawn to match the approved mockup's silhouettes (redrawn for SwiftUI's `Path` API, not a literal SVG-path port — SwiftUI's curve commands differ from SVG's). Foundational for Tasks 4, 7, 8, 11, 12.

**Files:**
- Create: `MushroomSignal/Views/ForestIcons.swift`

**Interfaces:**
- Produces: `LeafShape`, `DropletShape`, `SunriseShape`, `SporeShape` — all `Shape`, all normalized to draw within whatever `CGRect` they're given (so callers size them via `.frame(width:height:)`, matching how any SwiftUI `Shape` is used).

- [ ] **Step 1: Implement (no test — this is pure declarative drawing code; verified visually in Task 13)**

Create `MushroomSignal/Views/ForestIcons.swift`:

```swift
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
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **` (the file isn't used anywhere yet, so this only checks it compiles standalone)

- [ ] **Step 3: Commit**

```bash
git add MushroomSignal/Views/ForestIcons.swift
git commit -m "feat: add forest glyph set (leaf, droplet, sunrise, spore)"
```

---

### Task 4: Canopy-light glass — `CanopyLightView` + `GlassBackground.swift` wiring

Replaces the flat `forestDeep.opacity(0.25)` tint with 2-3 soft, irregular, warm-toned light blobs, locked at 66% intensity, with an explicit reduce-motion decision (spec left this open — resolved here: skip the drift animation entirely when the system signals reduced motion, rather than a partial/slowed version, since a static-but-present glow still reads as "canopy light," just without the drift).

**Files:**
- Create: `MushroomSignal/Views/CanopyLightView.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`
- Modify: `MushroomSignal/Views/GlassBackground.swift`

**Interfaces:**
- Produces: `DesignSystem.canopyLightIntensity: Double = 0.66`; `CanopyLightView: View` (no parameters — self-contained, matching `VisualEffectBackground`'s existing no-parameter pattern in the same file).

- [ ] **Step 1: Add the token**

In `DesignSystem.swift`, after `chipCornerRadius` (line 69), add:

```swift
    /// Locked opacity multiplier on `CanopyLightView`'s light-blob layer — approved via
    /// interactive mockup calibration, 2026-08-11. Not user-adjustable in the shipped app.
    public static let canopyLightIntensity: Double = 0.66
```

- [ ] **Step 2: Implement `CanopyLightView`**

Create `MushroomSignal/Views/CanopyLightView.swift`:

```swift
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
```

- [ ] **Step 3: Wire into `mushroomGlassBackground()`**

In `GlassBackground.swift`, replace:

```swift
extension View {
    func mushroomGlassBackground() -> some View {
        background(
            ZStack {
                VisualEffectBackground()
                DesignSystem.Colors.forestDeep.opacity(0.25)
            }
        )
    }
}
```

with:

```swift
extension View {
    func mushroomGlassBackground() -> some View {
        background(
            ZStack {
                VisualEffectBackground()
                DesignSystem.Colors.forestDeep.opacity(0.25)
                CanopyLightView()
                    .opacity(DesignSystem.canopyLightIntensity)
            }
        )
    }
}
```

- [ ] **Step 4: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual visual check**

Run the signed build (`DerivedData/Build/Products/Debug/MushroomSignal.app`), open any tab, confirm the glass now shows soft warm light blobs instead of a flat green tint, and that they drift slowly. Compare against the canopy-light mockup referenced in the spec.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignal/Views/CanopyLightView.swift \
        MushroomSignal/Views/GlassBackground.swift \
        MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift
git commit -m "feat: replace flat glass tint with dappled canopy-light effect"
```

---

### Task 5: Grain texture — `.grainTexture()` modifier

Very subtle (5%, `overlay` blend) procedural noise, applied to card fills — never behind text or the chart. Built with `Canvas` (procedural), not a bundled image asset — avoids an Asset Catalog entry, keeps everything as reviewable Swift code, consistent with Task 3's approach.

**Files:**
- Create: `MushroomSignal/Views/GrainTexture.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`

**Interfaces:**
- Produces: `DesignSystem.grainOpacity: Double = 0.05`; `View.grainTexture()` modifier.

- [ ] **Step 1: Add the token**

In `DesignSystem.swift`, after `canopyLightIntensity` (added in Task 4), add:

```swift
    /// Opacity of the procedural grain texture applied to `forestMid`/`forestDeep` card
    /// fills — a whisper of bark/leaf texture, never behind running text or chart marks.
    public static let grainOpacity: Double = 0.05
```

- [ ] **Step 2: Implement**

Create `MushroomSignal/Views/GrainTexture.swift`:

```swift
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
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/GrainTexture.swift \
        MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift
git commit -m "feat: add procedural grain texture modifier"
```

---

### Task 6: `ForestDivider`

A 1pt `bark`-toned divider replacing ad hoc separators, first used between `PredpovedView`'s sections (wired in Task 13).

**Files:**
- Create: `MushroomSignal/Views/ForestDivider.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`

**Interfaces:**
- Produces: `DesignSystem.forestDividerOpacity: Double = 0.7`; `ForestDivider: View`.

- [ ] **Step 1: Add the token**

In `DesignSystem.swift`, after `grainOpacity` (Task 5), add:

```swift
    /// Opacity of `ForestDivider`'s bark-toned gradient line.
    public static let forestDividerOpacity: Double = 0.7
```

- [ ] **Step 2: Implement**

Create `MushroomSignal/Views/ForestDivider.swift`:

```swift
// MushroomSignal/Views/ForestDivider.swift
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
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/ForestDivider.swift \
        MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift
git commit -m "feat: add ForestDivider"
```

---

### Task 7: `CompactSpeciesCardView`

The new fixed-size "glass button" card. Depends on Task 1 (`flushTriggered`), Task 3 (glyphs), Task 5 (grain).

**Files:**
- Create: `MushroomSignal/Views/CompactSpeciesCardView.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`

**Interfaces:**
- Consumes: `Species`, `SpeciesSignal` (with `.flushTriggered`, Task 1), `SpeciesPhoto` (existing), `LeafShape`/`DropletShape`/`SunriseShape` unused here directly — only `SunriseShape` (Task 3), `.grainTexture()` (Task 5), `DesignSystem.warningColor(for:)` (existing).
- Produces: `DesignSystem.compactCardSize: Double = 120`; `CompactSpeciesCardView(species:signal:rank:photo:)`.

- [ ] **Step 1: Add the token**

In `DesignSystem.swift`, after `forestDividerOpacity` (Task 6), add:

```swift
    /// Fixed size (both dimensions) of `CompactSpeciesCardView` — deliberately NOT part of
    /// an adaptive grid; the grid's column *count* reflows on window resize, this size does
    /// not. Picked from the mockup's ~110-130pt range.
    public static let compactCardSize: Double = 120
    /// `CompactSpeciesCardView`'s rank-badge / sunrise-badge circle diameter.
    public static let compactCardBadgeSize: Double = 18
```

- [ ] **Step 2: Implement**

Create `MushroomSignal/Views/CompactSpeciesCardView.swift`:

```swift
// MushroomSignal/Views/CompactSpeciesCardView.swift
import SwiftUI
import MushroomSignalCore

/// The forest redesign's new compact "glass button" species card — small, roughly square,
/// translucent, fixed size regardless of window/grid resize. Distinct from `SpeciesCardView`
/// (Zoznam/Mapa's larger photo-backed grid cards, unaffected by this redesign).
struct CompactSpeciesCardView: View {
    let species: Species
    let signal: SpeciesSignal?
    let rank: Int?
    let photo: SpeciesPhoto?

    private var isWarning: Bool { species.edibility != .edible }
    private var accentColor: Color {
        isWarning ? DesignSystem.warningColor(for: species.edibility) : DesignSystem.Colors.mossAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                if let rank {
                    Text("\(rank)")
                        .font(.system(size: DesignSystem.captionSize * 0.6, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                        .frame(width: DesignSystem.compactCardBadgeSize, height: DesignSystem.compactCardBadgeSize)
                        .background(Circle().fill(accentColor.opacity(0.28)))
                }
                Spacer()
                if signal?.flushTriggered == true {
                    SunriseShape()
                        .stroke(DesignSystem.Colors.caution, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .frame(width: 11, height: 11)
                        .frame(width: DesignSystem.compactCardBadgeSize, height: DesignSystem.compactCardBadgeSize)
                        .background(Circle().fill(DesignSystem.Colors.caution.opacity(0.22)))
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(species.commonNameSk)
                    .font(.system(size: DesignSystem.captionSize * 0.55, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                    .lineLimit(2)
                Text(species.latinName)
                    .font(.system(size: DesignSystem.captionSize * 0.45).italic())
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.55))
                    .lineLimit(1)
                if let signal {
                    ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize * 0.4)
                        .padding(.top, 2)
                }
            }
        }
        .padding(8)
        .frame(width: DesignSystem.compactCardSize, height: DesignSystem.compactCardSize)
        .background(
            LinearGradient(colors: [DesignSystem.Colors.cloud.opacity(0.10), DesignSystem.Colors.cloud.opacity(0.02)], startPoint: .top, endPoint: .bottom)
        )
        .background(DesignSystem.Colors.forestMid)
        .grainTexture()
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.58))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.58)
                .stroke(isWarning ? DesignSystem.Colors.caution.opacity(0.4) : DesignSystem.Colors.cloud.opacity(0.16), lineWidth: 1)
        )
    }
}
```

Note: `photo` is intentionally unused in this pass — kept as a stored property so a future photo-enabled version doesn't need to restructure the type. If/when a photo is added, it must be centered, clipped to this same rounded shape, and must never overlap the rank/sunrise badges, name, latin name, or score dots at `compactCardSize` — verify against a real build with a real photo before shipping that change, not in isolation (per spec §2).

- [ ] **Step 3: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/CompactSpeciesCardView.swift \
        MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift
git commit -m "feat: add CompactSpeciesCardView"
```

---

### Task 8: Wire the sunrise glyph into `SpeciesCardView`'s reason line

The other first-use site from spec §3's glyph table (the compact card's corner badge, Task 7, is the first). `SpeciesCardView` (Zoznam/Mapa's big cards) shows `signal.reason` as plain text today — add the sunrise glyph inline before it when `flushTriggered` is true.

**Files:**
- Modify: `MushroomSignal/Views/SpeciesCardView.swift:46-53`

**Interfaces:**
- Consumes: `SunriseShape` (Task 3), `signal.flushTriggered` (Task 1).

- [ ] **Step 1: Modify the reason block**

In `SpeciesCardView.swift`, replace:

```swift
                if let signal {
                    ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize)
                    if let reason = signal.reason {
                        Text(reason)
                            .font(.system(size: DesignSystem.captionSize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            .lineLimit(2)
                    }
                }
```

with:

```swift
                if let signal {
                    ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize)
                    if let reason = signal.reason {
                        HStack(alignment: .top, spacing: 4) {
                            if signal.flushTriggered {
                                SunriseShape()
                                    .stroke(DesignSystem.Colors.caution, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                                    .frame(width: 12, height: 12)
                                    .padding(.top, 2)
                            }
                            Text(reason)
                                .font(.system(size: DesignSystem.captionSize))
                                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                                .lineLimit(2)
                        }
                    }
                }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual visual check**

Find a species currently showing a flush-triggered reason ("nedávno teplo a dážď — čoskoro môže prísť nová vlna") in Zoznam or Mapa's library grid, confirm the sunrise glyph appears before the text, doesn't clip, doesn't break the 2-line limit's layout.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/SpeciesCardView.swift
git commit -m "feat: show sunrise glyph next to flush-triggered reason text"
```

---

### Task 9: Rewire `topPicksSection` to use `CompactSpeciesCardView`

Replace the numbered-badge/`VStack` rows with a fixed-size grid of the new card, count raised 3→4.

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift:28-30,69-100`

**Interfaces:**
- Consumes: `CompactSpeciesCardView` (Task 7).

- [ ] **Step 1: Update `visibleTopSignals` and `topPicksSection`**

In `PredpovedView.swift`, change:

```swift
    private var visibleTopSignals: [SpeciesSignal] {
        Array(appState.signals.filter { $0.score > 0 }.prefix(3))
    }
```

to:

```swift
    private var visibleTopSignals: [SpeciesSignal] {
        Array(appState.signals.filter { $0.score > 0 }.prefix(4))
    }
```

Replace the whole `topPicksSection` computed property with:

```swift
    private var topPicksSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Odporúčané dnes")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: DesignSystem.compactCardSize, maximum: DesignSystem.compactCardSize), spacing: DesignSystem.spacingSmall)],
                spacing: DesignSystem.spacingSmall
            ) {
                ForEach(Array(visibleTopSignals.enumerated()), id: \.element.species.id) { index, signal in
                    CompactSpeciesCardView(species: signal.species, signal: signal, rank: index + 1, photo: nil)
                }
            }
        }
    }
```

Note: `GridItem(.adaptive(minimum:maximum:))` with equal min/max is the correct way to get "column count reflows, individual size doesn't" in SwiftUI — a plain `.fixed(...)` column would produce a fixed *number* of columns regardless of width, which is the opposite of what's needed (spec §2 explicitly wants column count to reflow). This is a deliberate correction of the spec's literal `GridItem(.fixed(...))` suggestion — `.adaptive` with matching min/max is the construct that actually satisfies the stated requirement.

- [ ] **Step 2: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual visual check — resize behavior**

Run the app, open Predpoveď, resize the window narrower and wider. Confirm: column count changes, but individual card size stays exactly `120×120pt` (measure or eyeball against another known-120pt element) at every width.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: replace topPicksSection rows with CompactSpeciesCardView grid, count 4"
```

---

### Task 10: Rebuild `dailyStripSection` — rain+heat, last 10 days only

Two simple stacked bar rows (heat, rain), past days only, no forecast, no humidity, no dual-axis. Replaces the current single temperature-range `BarMark` chart.

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift:123-150`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`

**Interfaces:**
- Consumes: `weatherState.dailyWeather` (existing, already loaded).
- Produces: `DesignSystem.rainHeatChartRowHeight: Double = 56`.

- [ ] **Step 1: Add the token**

In `DesignSystem.swift`, after `compactCardBadgeSize` (Task 7), add:

```swift
    /// Height of each row (heat, rain) in Predpoveď's simplified two-row daily chart.
    public static let rainHeatChartRowHeight: Double = 56
```

- [ ] **Step 2: Replace `dailyStripSection` and `isForecastDay`**

In `PredpovedView.swift`, replace:

```swift
    private var dailyStripSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Denný prehľad")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Chart(weatherState.dailyWeather, id: \.date) { day in
                BarMark(
                    x: .value("Deň", day.date, unit: .day),
                    yStart: .value("Min", day.minTempC),
                    yEnd: .value("Max", day.maxTempC)
                )
                // Cold-to-hot gradient per bar (caution at the top/max end, water at the
                // bottom/min end) — matches the approved mockup and gives `water` its first
                // real use anywhere in the app (previously defined, never consumed).
                .foregroundStyle(
                    LinearGradient(colors: [DesignSystem.Colors.caution, DesignSystem.Colors.water], startPoint: .top, endPoint: .bottom)
                        .opacity(isForecastDay(day) ? 0.5 : 1.0)
                )
                .cornerRadius(DesignSystem.chartBarCornerRadius)
            }
            .frame(height: DesignSystem.trendChartHeight)
        }
    }

    private func isForecastDay(_ day: DailyWeather) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: day.date) > calendar.startOfDay(for: Date())
    }
```

with:

```swift
    private var pastTenDays: [DailyWeather] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        return weatherState.dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
    }

    private var dailyStripSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Posledných 10 dní")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            HStack(spacing: 12) {
                Text("teplo")
                    .font(.system(size: DesignSystem.captionSize * 0.6))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
                Text("dážď")
                    .font(.system(size: DesignSystem.captionSize * 0.6))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            }
            Chart(pastTenDays, id: \.date) { day in
                BarMark(
                    x: .value("Deň", day.date, unit: .day),
                    y: .value("Teplo", day.maxTempC)
                )
                .foregroundStyle(DesignSystem.Colors.caution)
                .cornerRadius(DesignSystem.chartBarCornerRadius * 0.5)
            }
            .frame(height: DesignSystem.rainHeatChartRowHeight)
            .chartYAxis(.hidden)

            Chart(pastTenDays, id: \.date) { day in
                BarMark(
                    x: .value("Deň", day.date, unit: .day),
                    y: .value("Dážď", day.precipitationMm)
                )
                .foregroundStyle(DesignSystem.Colors.water)
                .cornerRadius(DesignSystem.chartBarCornerRadius * 0.5)
            }
            .frame(height: DesignSystem.rainHeatChartRowHeight)
            .chartYAxis(.hidden)
        }
    }
```

Two separate `Chart` views stacked in the enclosing `VStack`, sharing the same `pastTenDays` data and x-axis unit (`.day`) so their bars align vertically — the implementation choice the spec's Open Questions left open, resolved here as the simpler of the two options it listed.

- [ ] **Step 3: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual visual check**

Open Predpoveď, confirm two stacked bar rows appear (heat above, rain below), 10 bars each, no forecast days included, bars align by day between the two rows. Compare against `predpoved-full-tab.html`'s chart section.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift \
        MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift
git commit -m "feat: simplify daily chart to rain+heat, last 10 days"
```

---

### Task 11: New `rainIncomingSection`

The "Blíži sa dážď" alert. Depends on Task 2 (`UpcomingRainDetector`), Task 3 (droplet glyph).

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift`

**Interfaces:**
- Consumes: `UpcomingRainDetector.nextTriggerEvent(in:asOf:)` (Task 2), `DropletShape` (Task 3).

- [ ] **Step 1: Add the pluralization helper and section**

In `PredpovedView.swift`, add a computed property and a new section. First, the day-count helper (Slovak: 1 → "deň", 2-4 → "dni", the realistic range given a 5-day forecast window):

```swift
    private func slovakDayWord(_ count: Int) -> String {
        switch count {
        case 1: return "deň"
        default: return "dni"
        }
    }

    private var upcomingRainEvent: RainEvent? {
        UpcomingRainDetector.nextTriggerEvent(in: weatherState.dailyWeather, asOf: Date())
    }

    private var rainIncomingSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Blíži sa dážď")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if let event = upcomingRainEvent {
                let daysUntil = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: event.date)).day ?? 1)
                HStack(spacing: 11) {
                    DropletShape()
                        .stroke(DesignSystem.Colors.water, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(DesignSystem.Colors.water.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("O \(daysUntil) \(slovakDayWord(daysUntil)) · \(String(format: "%.0f", event.precipitationMm)) mm dažďa a \(Int(event.maxTempC.rounded()))°C")
                            .font(.system(size: DesignSystem.captionSize * 0.65, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.cloud)
                        Text("Dážď aj teplo spolu — sleduj skóre o 4–9 dní")
                            .font(.system(size: DesignSystem.captionSize * 0.55))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.65))
                    }
                }
                .padding(11)
                .background(DesignSystem.Colors.water.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.55)
                        .stroke(DesignSystem.Colors.water.opacity(0.4), lineWidth: 1)
                )
            } else {
                Text("Žiadny výraznejší dážď v predpovedi.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
        }
    }
```

- [ ] **Step 2: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

(`rainIncomingSection` isn't called from `body` yet — that's Task 13. This task only needs to compile standalone.)

- [ ] **Step 3: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: add rainIncomingSection (Blíži sa dážď alert)"
```

---

### Task 12: `seasonCalendarSection` — leaf glyph on chips, spore glyph on the empty state

Chip shape/layout stays exactly as previously approved (2026-08-10) — only the swatch
changes. Also wires `SporeShape` (Task 3) into its first real use site — the spec's glyph
table names this exact empty state as the spore glyph's use, but no earlier task actually
called it; fixed here rather than shipping an unused shape.

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift:152-202` (`seasonCalendarSection` and the `seasonChip(for:)` helper)

**Interfaces:**
- Consumes: `LeafShape`, `SporeShape` (Task 3).

- [ ] **Step 1: Replace the swatch `Circle` with `LeafShape`**

In `seasonChip(for:)`, replace:

```swift
            HStack(spacing: 7) {
                Circle()
                    .fill(swatchColor)
                    .frame(width: DesignSystem.chipDotSize, height: DesignSystem.chipDotSize)
```

with:

```swift
            HStack(spacing: 7) {
                LeafShape()
                    .stroke(swatchColor, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: DesignSystem.chipDotSize + 4, height: DesignSystem.chipDotSize + 4)
```

(Slightly larger than the old dot — a stroked leaf silhouette needs a bit more room than a filled circle to read clearly at a glance; `chipDotSize + 4` keeps it proportionate rather than introducing a new unrelated token.)

- [ ] **Step 2: Add the spore glyph to the empty state**

In `seasonCalendarSection`, replace:

```swift
            if inSeasonSpecies.isEmpty {
                Text("Žiadne druhy nie sú aktuálne v sezóne.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else {
```

with:

```swift
            if inSeasonSpecies.isEmpty {
                VStack(spacing: 8) {
                    SporeShape()
                        .fill(DesignSystem.Colors.cloud.opacity(0.4))
                        .frame(width: 26, height: 26)
                    Text("Žiadne druhy nie sú aktuálne v sezóne.")
                        .font(.system(size: DesignSystem.bodySize))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.spacingSmall)
            } else {
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual visual check**

Confirm season-calendar chips show a small leaf silhouette instead of a filled dot, correctly recolored to `caution`/`danger` for non-edible species, chip pill shape unchanged. Force the empty state (test with a region/month where no species are in season, or temporarily filter `inSeasonSpecies` to empty) and confirm the spore-dot cluster renders above the message, centered.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: replace season-calendar chip dot with leaf glyph"
```

---

### Task 13: Final assembly — full section order, hero styling, grain on remaining surfaces

Wires everything built in Tasks 1-12 into `PredpovedView.body` in the locked order, applies the droplet+water hero styling, inserts `ForestDivider`s, and applies `.grainTexture()` to `SpeciesCardView` and the panel background (the remaining spots from spec §4 not already covered by Task 7's `CompactSpeciesCardView`).

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift` (body + `heroSection`)
- Modify: `MushroomSignal/Views/SpeciesCardView.swift` (grain on its background)

**Interfaces:**
- Consumes: everything from Tasks 1-12.

- [ ] **Step 1: Rebuild `body` and `heroSection`**

Replace `PredpovedView.body`:

```swift
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                if let error = appState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(appState.isShowingStaleData ? DesignSystem.Colors.caution : DesignSystem.Colors.danger)
                }
                if let error = weatherState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(DesignSystem.Colors.danger)
                }

                heroSection
                ForestDivider()
                dailyStripSection
                ForestDivider()
                if !visibleTopSignals.isEmpty {
                    topPicksSection
                    ForestDivider()
                }
                rainIncomingSection
                ForestDivider()
                seasonCalendarSection
                disclaimer
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
        .task {
            do {
                allSpecies = try SpeciesDatabase.loadAll()
            } catch {
                predpovedLogger.error("Failed to load species dataset: \(String(describing: error), privacy: .public)")
            }
        }
    }
```

Replace `heroSection`'s moisture line — change:

```swift
                Text("Vlhkosť \(Int(today.humidityPercent.rounded()))% · Zrážky \(String(format: "%.1f", today.precipitationMm)) mm")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
```

to:

```swift
                HStack(spacing: 5) {
                    DropletShape()
                        .stroke(DesignSystem.Colors.water, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .frame(width: 12, height: 12)
                    Text("Vlhkosť \(Int(today.humidityPercent.rounded()))% · Zrážky \(String(format: "%.1f", today.precipitationMm)) mm")
                        .font(.system(size: DesignSystem.bodySize))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                }
```

- [ ] **Step 2: Apply grain to `SpeciesCardView`'s background**

In `SpeciesCardView.swift`, find:

```swift
        .frame(height: DesignSystem.speciesCardPhotoHeight)
        .background(DesignSystem.Colors.forestMid)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))
```

change to:

```swift
        .frame(height: DesignSystem.speciesCardPhotoHeight)
        .background(DesignSystem.Colors.forestMid)
        .grainTexture()
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))
```

- [ ] **Step 3: Build**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run the full test suite**

Run: `swift test --package-path MushroomSignalCore 2>&1 | tail -15`
Expected: all tests pass.

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData test 2>&1 | tail -30`
Expected: all app-target tests pass.

- [ ] **Step 5: Full manual visual QA against all three mockups**

Run the signed build. Open Predpoveď for a region with real data. Section-by-section, compare against:
- The canopy-light intensity mockup — confirm the glass glow.
- The round-2 mockup — confirm compact-card shape, grain, glyph set.
- `predpoved-full-tab.html` — confirm the exact section order (hero → chart → top 4 picks → rain alert → season calendar), dividers between every section, moisture-line droplet.

Also verify negative paths, not just the happy path:
- A region with no in-season species: `seasonCalendarSection`'s existing empty message still renders correctly with the new leaf-swatch chip code untouched in that branch.
- A forecast with no qualifying rain+heat day: `rainIncomingSection` shows "Žiadny výraznejší dážď v predpovedi." not a blank space.
- Fewer than 4 scoring species: `topPicksSection`'s grid renders however many are actually available (1-4), no broken layout.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift MushroomSignal/Views/SpeciesCardView.swift
git commit -m "feat: assemble full Predpoveď forest-redesign layout"
```

---

### Task 14: Version bump

Per Alexander's explicit instruction: once this work ships, `MARKETING_VERSION` → `"0.01"`, `CURRENT_PROJECT_VERSION` → `"0.11"`, both targets (app + widget, `project.yml` lines 23-24 and 65-66).

**Files:**
- Modify: `project.yml:23-24,65-66`

- [ ] **Step 1: Edit `project.yml`**

Change both occurrences of:
```yaml
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
```
to:
```yaml
        MARKETING_VERSION: "0.01"
        CURRENT_PROJECT_VERSION: "0.11"
```

- [ ] **Step 2: Regenerate the Xcode project**

Run: `xcodegen generate`
Expected: regenerates `MushroomSignal.xcodeproj` from the edited `project.yml` — never hand-edit the `.xcodeproj` directly (`CLAUDE.md`).

- [ ] **Step 3: Build to confirm the regenerated project still builds**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Verify the version actually landed in the built app**

Run: `defaults read "$(pwd)/DerivedData/Build/Products/Debug/MushroomSignal.app/Contents/Info.plist" CFBundleShortVersionString`
Expected: `0.01`

Run: `defaults read "$(pwd)/DerivedData/Build/Products/Debug/MushroomSignal.app/Contents/Info.plist" CFBundleVersion`
Expected: `0.11`

- [ ] **Step 5: Commit**

```bash
git add project.yml MushroomSignal.xcodeproj
git commit -m "chore: bump version to 0.01 (marketing) / 0.11 (build) for forest redesign"
```

---

## Self-Review Notes

**Spec coverage:** Goals 1 (Task 4), 2 (Tasks 7, 9), 3 (Tasks 3, 8, 11, 12), 4 (Tasks 5, 13), 5 (Tasks 6, 13), 6 (Task 13), 7 (Task 10), 8 (Tasks 2, 11) all have a task. Every Open Question the spec deferred is resolved explicitly in this plan rather than left implicit: canopy-light blob geometry (Task 4, concrete `GeometryReader`-based blobs), reduce-motion (Task 4, `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, skip animation entirely), grain asset generation (Task 5, `Canvas`-procedural, not a bundled image), glyph fidelity (Task 3, redrawn natively for SwiftUI rather than ported SVG data), two-row chart construction (Task 10, two stacked `Chart` views), final Slovak copy (Task 11, real strings with a day-count pluralization helper).

**Deviation flagged during planning, not silently made:** Task 9 uses `GridItem(.adaptive(minimum:maximum:))` rather than the spec's literal `GridItem(.fixed(...))` suggestion — `.fixed` produces a fixed *column count*, which is the opposite of the spec's actual requirement (column count reflows, card size doesn't). `.adaptive` with matching min/max is the construct that satisfies the real requirement; noted inline in Task 9.

**Discovered during grounding, not in the original spec:** `SpeciesSignal` had no `flushTriggered` field at all — flush-trigger state was only recoverable by string-matching `reason` text. Task 1 fixes this properly (a real boolean, threaded through the already-existing `computeSignal` parameter) rather than having later tasks compare against a literal Slovak sentence.
