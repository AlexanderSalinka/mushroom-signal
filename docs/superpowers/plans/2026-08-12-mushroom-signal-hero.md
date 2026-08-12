# Mushroom Signal Hero Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `PredpovedView`'s plain-text `rainIncomingSection` with a "Mushroom Signal"
hero — one panel with a 4-state priority ladder (flush-happening > rain-incoming >
near-miss > no-rain), a shared panel shell, per-state hand-drawn graphics (one animated),
and a loud-states-only mini chart — per
`docs/superpowers/specs/2026-08-12-mushroom-signal-hero-widget-design.md` (approved,
commit `a1300b3`).

**Architecture:** Four small, independently-testable pure logic units land in
`MushroomSignalCore` first (design tokens, season-word mapping, state-priority resolver,
a fixed weather-window helper) — each gets real XCTest coverage, matching how
`FlushTriggerDetector`/`UpcomingRainDetector`/`NearMissRainInsight` are already tested.
Three new/modified SwiftUI views in the `MushroomSignal` app target consume those units:
new hand-drawn `Shape`s in `ForestIcons.swift`, a new condensed mini-chart view, and the
new hero panel view itself (which owns the flush-happening animation and its
`reduceMotion`/`.onDisappear` lifecycle). The last task wires the hero into
`PredpovedView` and deletes the `rainIncomingSection` code path it replaces.

**Tech Stack:** SwiftUI, Swift Charts (`import Charts`), `AppKit`'s
`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` — no new dependencies.

## Global Constraints

- **Widget is out of scope.** Do not touch anything under `MushroomSignalWidget/`,
  including `ShortlistWidgetView.swift`. The spec explicitly defers widget integration to
  a future spec (Alexander, 2026-08-12).
- All new UI **sizing** (badge/glyph diameters, chart heights, spacing, colors) routes
  through `DesignSystem` — no ad hoc layout constants (project `CLAUDE.md`). Small
  **decorative** constants inside hand-drawn `Shape` stroke styling (line widths, dash
  patterns, minor badge-internal offsets/opacities) are NOT part of that system — this
  matches the existing precedent in `ForestIcons.swift`, `CanopyLightView.swift`, and the
  `rainIncomingSection` this plan removes, none of which tokenize stroke line widths
  either. Don't "fix" that precedent while implementing this plan.
- 20pt text floor (`DesignSystem.captionSize`/`bodySize`/`titleSize`/`heroSize`) applies
  here — this plan reuses those existing tokens as-is for all headline/subline/context
  text, so no exception is needed or should be introduced.
- This codebase has no SwiftUI View-level unit test infrastructure (confirmed:
  `MushroomSignalTests/` only covers `@ObservableObject` state classes). Don't invent one
  for this plan — View tasks (5-8) are verified by building and visually checking the
  running app, exactly like the codebase's existing views. Pure-logic tasks (1-4) live in
  `MushroomSignalCore` and get real `XCTest` coverage, same as the existing detectors.
- XcodeGen does NOT auto-detect new `.swift` files in the `MushroomSignal` app target —
  run `xcodegen generate` after adding `MushroomSignalHeroMiniChart.swift` (Task 6) and
  `MushroomSignalHeroView.swift` (Task 7) before building. `MushroomSignalCore` is a
  Swift Package and auto-discovers new files on its own — no `xcodegen generate` needed
  for Tasks 1-4.
- Never hand-edit `MushroomSignal.xcodeproj` directly — only `project.yml` +
  `xcodegen generate`.
- **Every `xcodebuild build`/`xcodebuild test` invocation mutates `MushroomSignal/Info.plist`
  and `MushroomSignalWidget/Info.plist`**, overwriting their `$(MARKETING_VERSION)`/
  `$(CURRENT_PROJECT_VERSION)` build-variable references with hardcoded literal values —
  a pre-existing build-configuration quirk, unrelated to this plan. Before every
  `git add`/`git commit` in any App-target task (5-8), run
  `git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist` first if
  `git status` shows them modified, so this noise never lands in a task commit.
- Reduce-motion gating and the `.onDisappear` animation teardown (Task 7) are **hard
  requirements from the spec**, not optional polish — the flush-happening idle loop must
  never run when the system requests reduced motion, and must never keep running after
  the hero scrolls off-screen inside `PredpovedView`'s `ScrollView`.

---

## Task 1: New `DesignSystem` tokens

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift`

**Interfaces:**
- Produces: `DesignSystem.heroIconBadgeSize: Double`, `DesignSystem.heroIconGlyphSize:
  Double`, `DesignSystem.heroIconBadgeSizeQuiet: Double`,
  `DesignSystem.heroIconGlyphSizeQuiet: Double`, `DesignSystem.heroSparklineTempHeight:
  Double`, `DesignSystem.heroSparklineRainHeight: Double` — all consumed by Tasks 6 and 7.

- [ ] **Step 1: Write the failing test**

In `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift`, add at the
end of the class, before the final closing `}`:

```swift
    func testHeroIconBadgeSizesAreDistinctByLoudness() {
        XCTAssertGreaterThan(DesignSystem.heroIconBadgeSize, DesignSystem.heroIconBadgeSizeQuiet)
        XCTAssertGreaterThan(DesignSystem.heroIconGlyphSize, DesignSystem.heroIconGlyphSizeQuiet)
    }

    func testHeroIconGlyphSizesFitInsideTheirBadges() {
        XCTAssertLessThan(DesignSystem.heroIconGlyphSize, DesignSystem.heroIconBadgeSize)
        XCTAssertLessThan(DesignSystem.heroIconGlyphSizeQuiet, DesignSystem.heroIconBadgeSizeQuiet)
    }

    func testHeroSparklinePanelsAreSmallerThanTheFullChart() {
        XCTAssertLessThan(DesignSystem.heroSparklineTempHeight, DesignSystem.chartTempPanelHeight)
        XCTAssertLessThan(DesignSystem.heroSparklineRainHeight, DesignSystem.chartRainPanelHeight)
    }
```

- [ ] **Step 2: Run tests to verify they fail (compile error)**

```bash
swift test --package-path MushroomSignalCore --filter DesignSystemTests
```

Expected: FAIL to build — `heroIconBadgeSize` (and the other 5 tokens) don't exist yet.

- [ ] **Step 3: Add the tokens**

In `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`, find
the end of the existing token list (currently ends with `seasonRowCornerRadius` right
before `public enum Colors {`). Insert before that enum:

```swift
    /// `MushroomSignalHeroView`'s icon badge diameter for loud states (flush-happening,
    /// rain-incoming) — a real focal point, ~2x the icon badge `rainIncomingSection` used
    /// before this view replaced it.
    public static let heroIconBadgeSize: Double = 64
    /// `MushroomSignalHeroView`'s icon glyph size inside `heroIconBadgeSize`, loud states —
    /// ~53% of the badge, matching the glyph-to-badge ratio the replaced view already used
    /// (15pt glyph inside a 30pt badge).
    public static let heroIconGlyphSize: Double = 34
    /// `MushroomSignalHeroView`'s icon badge diameter for quiet states (near-miss, no-rain) —
    /// deliberately smaller than the loud badge, but still well above the 20pt text floor so
    /// "quiet" never reads as an unfinished/omitted state.
    public static let heroIconBadgeSizeQuiet: Double = 40
    /// `MushroomSignalHeroView`'s icon glyph size inside `heroIconBadgeSizeQuiet`, quiet
    /// states — same ~53% ratio as the loud badge/glyph pair.
    public static let heroIconGlyphSizeQuiet: Double = 21
    /// `MushroomSignalHeroView`'s mini temp-line panel height (loud states only) — ~40% of
    /// `chartTempPanelHeight`, condensed for a hero-panel preview, not a full chart.
    public static let heroSparklineTempHeight: Double = 36
    /// `MushroomSignalHeroView`'s mini rain-bars panel height (loud states only) — ~40% of
    /// `chartRainPanelHeight`, same condensation ratio as `heroSparklineTempHeight`.
    public static let heroSparklineRainHeight: Double = 28
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --package-path MushroomSignalCore --filter DesignSystemTests
```

Expected: PASS, all `DesignSystemTests` green.

- [ ] **Step 5: Run the full Core suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
```

Expected: all green, same pass count plus the 3 new tests.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift
git commit -m "feat: add DesignSystem tokens for the Mushroom Signal hero"
```

---

## Task 2: Slovak season-word mapping

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SeasonWord.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SeasonWordTests.swift`

**Interfaces:**
- Produces: `SeasonWord.forMonth(_ month: Int) -> String` — consumed by Task 7's
  `MushroomSignalHeroView.contextRow`.

**Background (confirmed in code):** `seasonCalendarSection` in `PredpovedView.swift` only
ever uses the raw month number (`Calendar.current.component(.month, from: Date())`) to
filter `fruitingMonths` — there is no month→Slovak-season-word mapping anywhere in the
codebase today. Meteorological season boundaries (Dec-Feb winter, Mar-May spring, etc.)
are used, not astronomical ones — matches how Slovak weather/foraging content usually
talks about seasons and keeps the mapping to whole months.

- [ ] **Step 1: Write the failing test**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/SeasonWordTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class SeasonWordTests: XCTestCase {
    func testAllTwelveMonthsResolveToOneOfFourWords() {
        let validWords: Set<String> = ["jar", "leto", "jeseň", "zima"]
        for month in 1...12 {
            XCTAssertTrue(validWords.contains(SeasonWord.forMonth(month)), "month \(month) resolved to an unexpected word")
        }
    }

    func testDecemberJanuaryFebruaryAreWinter() {
        XCTAssertEqual(SeasonWord.forMonth(12), "zima")
        XCTAssertEqual(SeasonWord.forMonth(1), "zima")
        XCTAssertEqual(SeasonWord.forMonth(2), "zima")
    }

    func testMarchAprilMayAreSpring() {
        XCTAssertEqual(SeasonWord.forMonth(3), "jar")
        XCTAssertEqual(SeasonWord.forMonth(4), "jar")
        XCTAssertEqual(SeasonWord.forMonth(5), "jar")
    }

    func testJuneJulyAugustAreSummer() {
        XCTAssertEqual(SeasonWord.forMonth(6), "leto")
        XCTAssertEqual(SeasonWord.forMonth(7), "leto")
        XCTAssertEqual(SeasonWord.forMonth(8), "leto")
    }

    func testSeptemberOctoberNovemberAreAutumn() {
        XCTAssertEqual(SeasonWord.forMonth(9), "jeseň")
        XCTAssertEqual(SeasonWord.forMonth(10), "jeseň")
        XCTAssertEqual(SeasonWord.forMonth(11), "jeseň")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --package-path MushroomSignalCore --filter SeasonWordTests
```

Expected: FAIL to build — `SeasonWord` doesn't exist yet.

- [ ] **Step 3: Implement `SeasonWord`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SeasonWord.swift`:

```swift
import Foundation

/// Maps a calendar month to its Slovak season word — used by `MushroomSignalHeroView`'s
/// context row (`region · month · season`). No existing code in this app produces this
/// mapping; `seasonCalendarSection` only ever needed the raw month number to filter
/// `fruitingMonths`, never a season name.
public enum SeasonWord {
    /// Slovak meteorological seasons: December-February winter, March-May spring, and so
    /// on — matches how Slovak weather/foraging content usually talks about seasons.
    public static func forMonth(_ month: Int) -> String {
        switch month {
        case 12, 1, 2: return "zima"
        case 3, 4, 5: return "jar"
        case 6, 7, 8: return "leto"
        case 9, 10, 11: return "jeseň"
        default: return "zima"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --package-path MushroomSignalCore --filter SeasonWordTests
```

Expected: PASS, all 5 tests green.

- [ ] **Step 5: Run the full Core suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/SeasonWord.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SeasonWordTests.swift
git commit -m "feat: add Slovak month-to-season-word mapping"
```

---

## Task 3: Hero state priority resolver

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/MushroomSignalHeroState.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/MushroomSignalHeroStateTests.swift`

**Interfaces:**
- Consumes: `SpeciesSignal` (existing, `score: Int`, `flushTriggered: Bool`),
  `UpcomingRainDetector.nextTriggerEvent(in:asOf:calendar:) -> RainEvent?` (existing),
  `NearMissRainInsight.describe(in:asOf:calendar:) -> NearMissRainInsight.Case?` (existing).
- Produces: `MushroomSignalHeroState` enum (`.flushHappening`, `.rainIncoming(RainEvent)`,
  `.nearMiss(NearMissRainInsight.Case)`, `.noRain`), `Equatable`, `Sendable`, and
  `MushroomSignalHeroState.resolve(signals:dailyWeather:asOf:calendar:) ->
  MushroomSignalHeroState` — consumed by Task 7's `MushroomSignalHeroView`.

**Priority logic (from the spec):** flush-happening (`FlushTriggerDetector.triggered`
AND at least one signal has `score == 4`) > rain-incoming > near-miss > no-rain. Every
`SpeciesSignal` in a given refresh already carries the same `flushTriggered` value (set
once per `AppState.refresh()`), so `signals.contains(where: \.flushTriggered)` is
equivalent to calling `FlushTriggerDetector.triggered` again — reading it off `signals`
avoids a second, independently-fetched weather array just for this check.

- [ ] **Step 1: Write the failing tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/MushroomSignalHeroStateTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class MushroomSignalHeroStateTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private let sampleSpecies = Species(
        id: "boletus-edulis",
        commonNameSk: "Hríb smrekový",
        latinName: "Boletus edulis",
        edibility: .edible,
        lookAlikes: [],
        fruitingMonths: [6, 7, 8, 9, 10],
        idealTempMinC: 12,
        idealTempMaxC: 22,
        idealHumidityMinPercent: 60,
        idealHumidityMaxPercent: 90,
        rainfallSensitivity: .high,
        habitat: "smrekové lesy",
        regionalAffinity: ["zilinsky"]
    )

    private func signal(score: Int, flushTriggered: Bool) -> SpeciesSignal {
        SpeciesSignal(species: sampleSpecies, score: score, reason: nil, flushTriggered: flushTriggered)
    }

    private func daysFromNow(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, minTempC: maxTempC - 10, precipitationMm: precipitationMm, humidityPercent: 70)
    }

    func testFlushHappeningRequiresBothTriggerAndMaxedScore() {
        let signals = [signal(score: 4, flushTriggered: true)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: [], asOf: today)
        XCTAssertEqual(result, .flushHappening)
    }

    func testTriggeredWithoutAnyMaxedScoreIsNotFlushHappening() {
        let signals = [signal(score: 3, flushTriggered: true)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: [], asOf: today)
        XCTAssertEqual(result, .noRain)
    }

    func testMaxedScoreWithoutTriggerIsNotFlushHappening() {
        let signals = [signal(score: 4, flushTriggered: false)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: [], asOf: today)
        XCTAssertEqual(result, .noRain)
    }

    func testFlushHappeningWinsOverRainIncomingOnTheSameDay() {
        let signals = [signal(score: 4, flushTriggered: true)]
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: days, asOf: today)
        XCTAssertEqual(result, .flushHappening)
    }

    func testRainIncomingWhenNoFlushButForecastQualifies() {
        let signals = [signal(score: 2, flushTriggered: false)]
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: days, asOf: today)
        guard case .rainIncoming(let event) = result else {
            return XCTFail("expected rainIncoming, got \(result)")
        }
        XCTAssertEqual(event.precipitationMm, 11.0)
    }

    func testNearMissWhenNoFlushAndNoFullRainEvent() {
        let signals = [signal(score: 1, flushTriggered: false)]
        let days = [daysFromNow(2, maxTempC: 29.0, precipitationMm: 0.0)] // heat without rain
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: days, asOf: today)
        XCTAssertEqual(result, .nearMiss(.heatWithoutRain(date: days[0].date, precipitationMm: 0.0, maxTempC: 29.0)))
    }

    func testNoRainWhenEverythingIsFlat() {
        let signals = [signal(score: 1, flushTriggered: false)]
        let days = [daysFromNow(1, maxTempC: 18.0, precipitationMm: 0.0)]
        let result = MushroomSignalHeroState.resolve(signals: signals, dailyWeather: days, asOf: today)
        XCTAssertEqual(result, .noRain)
    }

    func testEmptySignalsAndEmptyWeatherResolvesToNoRain() {
        let result = MushroomSignalHeroState.resolve(signals: [], dailyWeather: [], asOf: today)
        XCTAssertEqual(result, .noRain)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --package-path MushroomSignalCore --filter MushroomSignalHeroStateTests
```

Expected: FAIL to build — `MushroomSignalHeroState` doesn't exist yet.

- [ ] **Step 3: Implement `MushroomSignalHeroState`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Signal/MushroomSignalHeroState.swift`:

```swift
import Foundation

/// Resolves `MushroomSignalHeroView`'s 4-way state — one shared priority ladder over
/// signals already computed by `AppState.refresh()`/`SignalPipeline` and the raw
/// forward-looking detectors. Pure, no I/O, so it's fully unit-testable against fixture
/// data the same way `FlushTriggerDetector`/`UpcomingRainDetector`/`NearMissRainInsight`
/// already are.
public enum MushroomSignalHeroState: Equatable, Sendable {
    case flushHappening
    case rainIncoming(RainEvent)
    case nearMiss(NearMissRainInsight.Case)
    case noRain

    /// - Parameter signals: today's ranked signals (`AppState.signals` in the app) — every
    ///   entry shares the same `flushTriggered` value for a given refresh cycle, so reading
    ///   it here avoids a second, independently-fetched call to `FlushTriggerDetector`.
    public static func resolve(signals: [SpeciesSignal], dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> MushroomSignalHeroState {
        let flushTriggered = signals.contains { $0.flushTriggered }
        let hasMaxedOutSpecies = signals.contains { $0.score == 4 }
        if flushTriggered && hasMaxedOutSpecies {
            return .flushHappening
        }
        if let event = UpcomingRainDetector.nextTriggerEvent(in: dailyWeather, asOf: today, calendar: calendar) {
            return .rainIncoming(event)
        }
        if let nearMiss = NearMissRainInsight.describe(in: dailyWeather, asOf: today, calendar: calendar) {
            return .nearMiss(nearMiss)
        }
        return .noRain
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --package-path MushroomSignalCore --filter MushroomSignalHeroStateTests
```

Expected: PASS, all 8 tests green.

- [ ] **Step 5: Run the full Core suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/MushroomSignalHeroState.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/MushroomSignalHeroStateTests.swift
git commit -m "feat: add MushroomSignalHeroState 4-way priority resolver"
```

---

## Task 4: Fixed 7-day weather window helper

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/RecentWeatherWindow.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/RecentWeatherWindowTests.swift`

**Interfaces:**
- Produces: `RecentWeatherWindow.lastSevenDaysPlusForecast(in:asOf:calendar:) ->
  [DailyWeather]` — consumed by Task 6's `MushroomSignalHeroMiniChart`.

**Why this can't reuse `WeatherRainChartView`:** its day-range filtering (`visibleDays`)
is a `private` computed property driven by that view's own `private @State
selectedRange` (the user-facing 7/14/30-day toggle) — not callable from a sibling view.
The mini chart needs its own always-fixed-at-7 window, applied to the same shared
`RegionWeatherState.dailyWeather` array the full chart already loads (no independent
fetch).

- [ ] **Step 1: Write the failing tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/RecentWeatherWindowTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class RecentWeatherWindowTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func day(_ offset: Int) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(offset) * 86400), meanTempC: 18, maxTempC: 22, minTempC: 14, precipitationMm: 2, humidityPercent: 70)
    }

    func testKeepsOnlyTheLastSevenPastDaysWhenMoreAreAvailable() {
        let days = (-10...0).map { day($0) }
        let result = RecentWeatherWindow.lastSevenDaysPlusForecast(in: days, asOf: today)
        XCTAssertEqual(result.count, 7)
        XCTAssertEqual(result.first?.date, day(-6).date)
        XCTAssertEqual(result.last?.date, day(0).date)
    }

    func testReturnsFewerThanSevenWhenFewerPastDaysExist() {
        let days = [day(-2), day(-1), day(0)]
        let result = RecentWeatherWindow.lastSevenDaysPlusForecast(in: days, asOf: today)
        XCTAssertEqual(result.count, 3)
    }

    func testIncludesAllForecastDaysRegardlessOfCount() {
        let days = [day(0), day(1), day(2), day(3), day(4), day(5)]
        let result = RecentWeatherWindow.lastSevenDaysPlusForecast(in: days, asOf: today)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result.last?.date, day(5).date)
    }

    func testReturnsEmptyArrayWhenNoDataAvailable() {
        XCTAssertEqual(RecentWeatherWindow.lastSevenDaysPlusForecast(in: [], asOf: today), [])
    }

    func testPastDaysComeBeforeForecastDaysInResult() {
        let days = [day(1), day(-1), day(0), day(-2)]
        let result = RecentWeatherWindow.lastSevenDaysPlusForecast(in: days, asOf: today)
        XCTAssertEqual(result.map { $0.date }, [day(-2).date, day(-1).date, day(0).date, day(1).date])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --package-path MushroomSignalCore --filter RecentWeatherWindowTests
```

Expected: FAIL to build — `RecentWeatherWindow` doesn't exist yet.

- [ ] **Step 3: Implement `RecentWeatherWindow`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Weather/RecentWeatherWindow.swift`:

```swift
import Foundation

/// A fixed 7-day-back + all-forecast window over daily weather — the minimal,
/// non-toggleable counterpart to `WeatherRainChartView`'s own `visibleDays` (which
/// supports a user-facing 7/14/30-day range toggle via private `@State`, not something a
/// sibling view can call into). `MushroomSignalHeroMiniChart` uses this to stay a pure
/// view over the same shared `RegionWeatherState.dailyWeather` the full chart already
/// loads, without a second fetch or a dependency on the full chart's internal state.
public enum RecentWeatherWindow {
    public static func lastSevenDaysPlusForecast(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> [DailyWeather] {
        let todayStart = calendar.startOfDay(for: today)
        let pastDays = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
            .suffix(7)
        let forecastDays = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) > todayStart }
            .sorted { $0.date < $1.date }
        return Array(pastDays) + forecastDays
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --package-path MushroomSignalCore --filter RecentWeatherWindowTests
```

Expected: PASS, all 5 tests green.

- [ ] **Step 5: Run the full Core suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Weather/RecentWeatherWindow.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/RecentWeatherWindowTests.swift
git commit -m "feat: add fixed 7-day weather window for the hero mini chart"
```

---

## Task 5: New hand-drawn `Shape`s in `ForestIcons.swift`

**Files:**
- Modify: `MushroomSignal/Views/ForestIcons.swift`

**Interfaces:**
- Produces: `MushroomCapShape` (single cap-on-stem `Shape`), `GrowthRaysShape` (baseline +
  radiating rays `Shape`), `CloudOutlineShape` (flat outline cloud `Shape`) — all consumed
  by Task 7's badge views. `DropletShape` and `SunriseShape` (existing) are reused as-is
  by Task 7 — no changes to either.

**Design note — why 3 caps are 3 shape instances, not 1 combined shape:** the spec calls
for each mushroom cap to grow independently with a staggered delay (~150-200ms apart).
That's only animatable in SwiftUI if each cap is its own view applying its own
`scaleEffect`/`.animation`, so `MushroomCapShape` draws one cap; Task 7 composes three
positioned instances. `GrowthRaysShape` is the separate "faint radiating growth lines
beneath" layer, pulsing as a whole (not staggered per the spec).

- [ ] **Step 1: Add the three new `Shape` structs**

In `MushroomSignal/Views/ForestIcons.swift`, add at the end of the file (after
`SporeShape`'s closing `}`):

```swift

/// A single mushroom-cap dome on a short stem — the flush-happening motif's repeating
/// unit. `MushroomSignalHeroView` composes three positioned instances of this, each
/// animated independently, for the spec's staggered entrance.
struct MushroomCapShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x, y: y + h * 0.55))
        path.addCurve(
            to: CGPoint(x: x + w, y: y + h * 0.55),
            control1: CGPoint(x: x, y: y),
            control2: CGPoint(x: x + w, y: y)
        )
        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.55))
        path.addLine(to: CGPoint(x: x + w * 0.5, y: y + h))
        return path
    }
}

/// Faint radiating growth lines beneath the mushroom caps — reuses `SunriseShape`'s
/// rays-from-a-baseline language for the flush-happening motif's ground layer.
struct GrowthRaysShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x, y: y + h * 0.15))
        path.addLine(to: CGPoint(x: x + w, y: y + h * 0.15))
        for rayX: CGFloat in [0.2, 0.5, 0.8] {
            path.move(to: CGPoint(x: x + w * rayX, y: y + h * 0.35))
            path.addLine(to: CGPoint(x: x + w * rayX, y: y + h))
        }
        return path
    }
}

/// A plain flat outline cloud — the no-rain motif, muted and undecorated (no droplet).
struct CloudOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.22, y: y + h * 0.68))
        path.addCurve(
            to: CGPoint(x: x + w * 0.22, y: y + h * 0.4),
            control1: CGPoint(x: x + w * 0.02, y: y + h * 0.62),
            control2: CGPoint(x: x + w * 0.04, y: y + h * 0.4)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.55, y: y + h * 0.22),
            control1: CGPoint(x: x + w * 0.28, y: y + h * 0.22),
            control2: CGPoint(x: x + w * 0.42, y: y + h * 0.16)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.85, y: y + h * 0.42),
            control1: CGPoint(x: x + w * 0.68, y: y + h * 0.28),
            control2: CGPoint(x: x + w * 0.82, y: y + h * 0.3)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.78, y: y + h * 0.68),
            control1: CGPoint(x: x + w * 0.98, y: y + h * 0.48),
            control2: CGPoint(x: x + w * 0.96, y: y + h * 0.68)
        )
        path.addLine(to: CGPoint(x: x + w * 0.22, y: y + h * 0.68))
        return path
    }
}
```

- [ ] **Step 2: Build to confirm it compiles**

```bash
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
```

Expected: build succeeds. These shapes aren't wired into any screen yet (that happens in
Task 7), so there's nothing to visually check until then — a clean build is the only
available signal at this point.

- [ ] **Step 3: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: both green, same pass counts as before (no testable logic changed — pure
geometry, no unit test precedent for `Shape` path output anywhere in this codebase).

- [ ] **Step 4: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignal/Views/ForestIcons.swift
git commit -m "feat: add MushroomCapShape, GrowthRaysShape, CloudOutlineShape"
```

---

## Task 6: Hero mini chart (loud states only)

**Files:**
- Create: `MushroomSignal/Views/MushroomSignalHeroMiniChart.swift`

**Interfaces:**
- Consumes: `RecentWeatherWindow.lastSevenDaysPlusForecast(in:asOf:) -> [DailyWeather]`
  (Task 4), `DesignSystem.heroSparklineTempHeight`/`heroSparklineRainHeight` (Task 1),
  `DailyWeather` (existing).
- Produces: `MushroomSignalHeroMiniChart(dailyWeather: [DailyWeather], today: Date)` —
  consumed by Task 7's `MushroomSignalHeroView`.

**Resolved design decision (Alexander, 2026-08-12):** temp+rain **stacked**, matching the
full chart's two-panel structure condensed down — not a temp-only sparkline.

- [ ] **Step 1: Add the file to `project.yml`'s source list (if needed) and regenerate**

Check whether `MushroomSignal/Views/` is globbed automatically:

```bash
grep -A3 "MushroomSignal:" project.yml | grep -i sources
```

If it's a directory glob (e.g. `sources: [MushroomSignal]`), no `project.yml` edit is
needed — just run `xcodegen generate` after creating the file in Step 2 to make Xcode
pick it up (XcodeGen re-scans the glob on every `generate`, it just doesn't do so
automatically on file save).

- [ ] **Step 2: Create the mini chart view**

Create `MushroomSignal/Views/MushroomSignalHeroMiniChart.swift`:

```swift
// MushroomSignal/Views/MushroomSignalHeroMiniChart.swift
import SwiftUI
import Charts
import MushroomSignalCore

/// The hero panel's condensed temp+rain preview (loud states only) — same `LineMark`/
/// `BarMark` pattern as `WeatherRainChartView`, fixed at a 7-day-back + forecast window
/// via `RecentWeatherWindow` (not the full chart's user-toggleable range), no axis
/// labels. A pure view over the caller-supplied `dailyWeather` — no independent fetch.
struct MushroomSignalHeroMiniChart: View {
    let dailyWeather: [DailyWeather]
    let today: Date

    private var visibleDays: [DailyWeather] {
        RecentWeatherWindow.lastSevenDaysPlusForecast(in: dailyWeather, asOf: today)
    }

    var body: some View {
        VStack(spacing: 2) {
            Chart(visibleDays, id: \.date) { day in
                LineMark(
                    x: .value("Deň", day.date, unit: .day),
                    y: .value("Teplota", day.maxTempC)
                )
                .foregroundStyle(DesignSystem.Colors.caution)
                .lineStyle(StrokeStyle(lineWidth: 1.6))
            }
            .frame(height: DesignSystem.heroSparklineTempHeight)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)

            Chart(visibleDays, id: \.date) { day in
                BarMark(
                    x: .value("Deň", day.date, unit: .day),
                    y: .value("Zrážky", day.precipitationMm)
                )
                .foregroundStyle(DesignSystem.Colors.water)
                .cornerRadius(DesignSystem.chartBarCornerRadius * 0.4)
            }
            .frame(height: DesignSystem.heroSparklineRainHeight)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        }
    }
}
```

- [ ] **Step 3: Regenerate the Xcode project and build**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
```

Expected: build succeeds. Not wired into any screen yet (Task 8) — nothing to visually
check until then.

- [ ] **Step 4: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: both green, same pass counts as before.

- [ ] **Step 5: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignal/Views/MushroomSignalHeroMiniChart.swift project.yml MushroomSignal.xcodeproj
git commit -m "feat: add MushroomSignalHeroMiniChart"
```

---

## Task 7: `MushroomSignalHeroView` — panel shell, 4 states, animation

**Files:**
- Create: `MushroomSignal/Views/MushroomSignalHeroView.swift`

**Interfaces:**
- Consumes: `MushroomSignalHeroState.resolve(signals:dailyWeather:asOf:) ->
  MushroomSignalHeroState` (Task 3), `SeasonWord.forMonth(_:) -> String` (Task 2),
  `RecentWeatherWindow` indirectly via `MushroomSignalHeroMiniChart` (Task 6),
  `MushroomCapShape`/`GrowthRaysShape`/`CloudOutlineShape` (Task 5), `DropletShape`/
  `SunriseShape` (existing, `ForestIcons.swift`), all 6 `heroIcon*`/`heroSparkline*`
  tokens (Task 1), `Region` (existing, `nameSk: String`).
- Produces: `MushroomSignalHeroView(signals: [SpeciesSignal], dailyWeather:
  [DailyWeather], region: Region, today: Date)` — consumed by Task 8's `PredpovedView`.

**Correctness note on the month name — read before implementing:** every other string in
this app is a hardcoded Slovak literal (there is no localization infrastructure at all).
Using SwiftUI's `.formatted(.dateTime.month(.wide))` would render the month name in
whatever locale the *device* is set to, which silently breaks (shows English month names)
on a non-Slovak-locale device — this app has no such mismatch anywhere else. Force the
locale explicitly with a `DateFormatter`, matching the deliberate-locale pattern this
plan needs even though no existing file in the codebase happens to need it yet.

**Animation design — read before implementing:** the spec asks for two different-timed
animations layered on the same caps: a one-shot staggered spring entrance (~0.75s per
cap, ~150-200ms apart) AND a separate slow breathing loop (~3-4s, `repeatForever`) once
settled. SwiftUI composes multiple `.animation(_:value:)` modifiers on the same view when
they're keyed to *different* `@State` values, so this uses two: `hasEntered` (one-shot,
spring) and `isBreathing` (looping, `repeatForever`), combined by multiplying their scale
factors. **Reduce-motion handling is intentionally not a straight copy of
`CanopyLightView`'s pattern**: `CanopyLightView`'s blobs are always fully visible at
their resting position regardless of its `animate` flag (only drift/rotation depend on
it), so guarding `animate = true` entirely under reduce-motion still leaves it in a
complete-looking state. Here, `hasEntered = false` means the caps are stuck at
`scaleY(0.15)` — visibly broken, not "settled." So `hasEntered` is set `true`
unconditionally on appear (landing instantly at full size, no animation, when
`reduceMotion` is true because the `.animation` modifier itself is `nil` in that case),
and only `isBreathing` (the actual continuous loop) is skipped under reduce-motion. Both
flags are reset to `false` in `.onDisappear`, satisfying the "loop must be torn down"
requirement for `isBreathing` and giving a clean replay of the entrance if the hero
scrolls back into view.

- [ ] **Step 1: Create the file**

Create `MushroomSignal/Views/MushroomSignalHeroView.swift`:

```swift
// MushroomSignal/Views/MushroomSignalHeroView.swift
import SwiftUI
import AppKit
import MushroomSignalCore

/// Replaces `rainIncomingSection` — one prominent panel combining the temperature+rain
/// trigger state, a mini chart (loud states only), and region/season context. See
/// docs/superpowers/specs/2026-08-12-mushroom-signal-hero-widget-design.md.
struct MushroomSignalHeroView: View {
    let signals: [SpeciesSignal]
    let dailyWeather: [DailyWeather]
    let region: Region
    let today: Date

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sk_SK")
        formatter.dateFormat = "LLLL"
        return formatter
    }()

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var state: MushroomSignalHeroState {
        MushroomSignalHeroState.resolve(signals: signals, dailyWeather: dailyWeather, asOf: today)
    }

    private var isLoud: Bool {
        switch state {
        case .flushHappening, .rainIncoming: return true
        case .nearMiss, .noRain: return false
        }
    }

    private func slovakDayWord(_ count: Int) -> String {
        switch count {
        case 1: return "deň"
        case 2...4: return "dni"
        default: return "dní"
        }
    }

    private func slovakSpeciesWord(_ count: Int) -> String {
        switch count {
        case 1: return "druh"
        case 2...4: return "druhy"
        default: return "druhov"
        }
    }

    private func daysUntil(_ date: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today), to: Calendar.current.startOfDay(for: date)).day ?? 1)
    }

    private var headline: String {
        switch state {
        case .flushHappening: return "Huby práve rastú"
        case .rainIncoming: return "Blíži sa dážď"
        case .nearMiss: return "Takmer to vyšlo"
        case .noRain: return "Žiadny výraznejší dážď"
        }
    }

    private var subline: String {
        switch state {
        case .flushHappening:
            let count = signals.filter { $0.score == 4 }.count
            return "\(count) \(slovakSpeciesWord(count)) na 100 % — posledné dni priniesli ideálne teplo aj dážď."
        case .rainIncoming(let event):
            let days = daysUntil(event.date)
            return "O \(days) \(slovakDayWord(days)) · \(String(format: "%.0f", event.precipitationMm)) mm dažďa a \(Int(event.maxTempC.rounded()))°C"
        case .nearMiss(let insight):
            switch insight {
            case .rainWithoutHeat(let date, let precipitationMm, _):
                let days = daysUntil(date)
                return "O \(days) \(slovakDayWord(days)) mierny dážď (\(String(format: "%.0f", precipitationMm)) mm), ale bez dostatočného tepla."
            case .heatWithoutRain(let date, _, let maxTempC):
                let days = daysUntil(date)
                return "O \(days) \(slovakDayWord(days)) teplo (\(Int(maxTempC.rounded()))°C), ale bez výraznejšieho dažďa."
            }
        case .noRain:
            return "V predpovedi zatiaľ nie je dážď spĺňajúci podmienky pre novú vlnu."
        }
    }

    private var contextRow: String {
        let month = Calendar.current.component(.month, from: today)
        let monthName = Self.monthFormatter.string(from: today)
        return "\(region.nameSk) · \(monthName) · \(SeasonWord.forMonth(month))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            HStack(alignment: .top, spacing: DesignSystem.spacingSmall) {
                badge
                VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                    Text(headline)
                        .font(.system(size: DesignSystem.titleSize, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                    Text(subline)
                        .font(.system(size: DesignSystem.bodySize))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                }
            }
            if isLoud {
                MushroomSignalHeroMiniChart(dailyWeather: dailyWeather, today: today)
            }
            Text(contextRow)
                .font(.system(size: DesignSystem.captionSize))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch state {
        case .flushHappening:
            FlushHappeningBadge(reduceMotion: reduceMotion)
        case .rainIncoming:
            RainIncomingBadge()
        case .nearMiss:
            NearMissBadge()
        case .noRain:
            NoRainBadge()
        }
    }
}

/// Loud, animated: three mushroom caps with a staggered spring entrance, settling into a
/// slow breathing idle loop. See the "Animation design" note in the plan for why
/// `hasEntered` and `isBreathing` are two separate `@State` flags.
private struct FlushHappeningBadge: View {
    let reduceMotion: Bool
    @State private var hasEntered = false
    @State private var isBreathing = false

    private let caps: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (0.28, 0.62, 0.34, 0.0),
        (0.5, 0.7, 0.42, 0.16),
        (0.72, 0.58, 0.3, 0.32)
    ]

    private var breathingScale: CGFloat { isBreathing ? 1.06 : 1.0 }

    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.mossAccent.opacity(0.22))
                .frame(width: DesignSystem.heroIconBadgeSize, height: DesignSystem.heroIconBadgeSize)

            GrowthRaysShape()
                .stroke(DesignSystem.Colors.mossAccent.opacity(0.5), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .frame(width: DesignSystem.heroIconGlyphSize, height: DesignSystem.heroIconGlyphSize * 0.4)
                .offset(y: DesignSystem.heroIconGlyphSize * 0.32)
                .opacity(isBreathing ? 0.85 : 0.5)
                .animation(reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: isBreathing)

            ForEach(Array(caps.enumerated()), id: \.offset) { index, cap in
                MushroomCapShape()
                    .stroke(DesignSystem.Colors.mossAccent, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: DesignSystem.heroIconGlyphSize * cap.size, height: DesignSystem.heroIconGlyphSize * cap.size)
                    .scaleEffect(x: 1.0, y: hasEntered ? 1.0 : 0.15, anchor: .bottom)
                    .scaleEffect(breathingScale, anchor: .bottom)
                    .position(x: DesignSystem.heroIconGlyphSize * cap.x, y: DesignSystem.heroIconGlyphSize * cap.y)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.75, dampingFraction: 0.62).delay(cap.delay),
                        value: hasEntered
                    )
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 3.4).repeatForever(autoreverses: true),
                        value: isBreathing
                    )
            }
        }
        .frame(width: DesignSystem.heroIconBadgeSize, height: DesignSystem.heroIconBadgeSize)
        .onAppear {
            hasEntered = true
            guard !reduceMotion else { return }
            isBreathing = true
        }
        .onDisappear {
            hasEntered = false
            isBreathing = false
        }
    }
}

/// Loud, static: droplet with two short motion lines, unchanged `DropletShape` sized up.
private struct RainIncomingBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.water.opacity(0.22))
                .frame(width: DesignSystem.heroIconBadgeSize, height: DesignSystem.heroIconBadgeSize)
            DropletShape()
                .stroke(DesignSystem.Colors.water, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: DesignSystem.heroIconGlyphSize, height: DesignSystem.heroIconGlyphSize)
            ForEach([CGFloat(-1), 1], id: \.self) { side in
                Rectangle()
                    .fill(DesignSystem.Colors.water.opacity(0.6))
                    .frame(width: 1.4, height: DesignSystem.heroIconGlyphSize * 0.3)
                    .rotationEffect(.degrees(20))
                    .offset(x: side * DesignSystem.heroIconGlyphSize * 0.42, y: -DesignSystem.heroIconGlyphSize * 0.32)
            }
        }
        .frame(width: DesignSystem.heroIconBadgeSize, height: DesignSystem.heroIconBadgeSize)
    }
}

/// Quiet: sunrise arc (reused from the flush-trigger glyph language) with a faint dashed
/// droplet beneath, smaller badge, caution/amber.
private struct NearMissBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.caution.opacity(0.18))
                .frame(width: DesignSystem.heroIconBadgeSizeQuiet, height: DesignSystem.heroIconBadgeSizeQuiet)
            SunriseShape()
                .stroke(DesignSystem.Colors.caution, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: DesignSystem.heroIconGlyphSizeQuiet, height: DesignSystem.heroIconGlyphSizeQuiet)
                .offset(y: -DesignSystem.heroIconGlyphSizeQuiet * 0.14)
            DropletShape()
                .stroke(DesignSystem.Colors.caution.opacity(0.65), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round, dash: [2, 2]))
                .frame(width: DesignSystem.heroIconGlyphSizeQuiet * 0.55, height: DesignSystem.heroIconGlyphSizeQuiet * 0.55)
                .offset(y: DesignSystem.heroIconGlyphSizeQuiet * 0.4)
        }
        .frame(width: DesignSystem.heroIconBadgeSizeQuiet, height: DesignSystem.heroIconBadgeSizeQuiet)
    }
}

/// Quiet: plain flat outline cloud, muted, low opacity, no droplet.
private struct NoRainBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(DesignSystem.Colors.cloud.opacity(0.1))
                .frame(width: DesignSystem.heroIconBadgeSizeQuiet, height: DesignSystem.heroIconBadgeSizeQuiet)
            CloudOutlineShape()
                .stroke(DesignSystem.Colors.cloud.opacity(0.5), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: DesignSystem.heroIconGlyphSizeQuiet, height: DesignSystem.heroIconGlyphSizeQuiet)
        }
        .frame(width: DesignSystem.heroIconBadgeSizeQuiet, height: DesignSystem.heroIconBadgeSizeQuiet)
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project and build**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
```

Fix any compile errors before proceeding. Not wired into any screen yet (Task 8) — a
clean build is the only available signal at this point.

- [ ] **Step 3: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: both green, same pass counts as before.

- [ ] **Step 4: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignal/Views/MushroomSignalHeroView.swift project.yml MushroomSignal.xcodeproj
git commit -m "feat: add MushroomSignalHeroView"
```

---

## Task 8: Wire the hero into `PredpovedView`, remove `rainIncomingSection`

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift`

**Interfaces:**
- Consumes: `MushroomSignalHeroView(signals:dailyWeather:region:today:)` (Task 7),
  `RegionDatabase.find(id:) -> Region?` (existing, `MushroomSignalCore`).

**What gets deleted:** `rainIncomingSection`, `upcomingRainEvent`, `nearMissInsight`,
`nearMissText(for:)`, and `slovakDayWord(_:)` are all superseded by logic now inside
`MushroomSignalHeroView` (confirmed via `grep` that none of these five are referenced
anywhere else in the file besides `rainIncomingSection` itself).

- [ ] **Step 1: Confirm current (pre-change) behavior**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
pkill -f "MushroomSignal.app" 2>/dev/null
open DerivedData/Build/Products/Debug/MushroomSignal.app
```

Navigate to the Predpoveď tab. Confirm the "Blíži sa dážď" plain-text section still shows
today, exactly as before — this is the baseline this task replaces.

- [ ] **Step 2: Add a `region` computed property**

In `MushroomSignal/Views/PredpovedView.swift`, find `todayEntry` (currently lines 16-19):

```swift
    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }
```

Add a new computed property right before it:

```swift
    private var region: Region {
        RegionDatabase.find(id: regionId) ?? RegionDatabase.all[0]
    }

    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }
```

- [ ] **Step 3: Delete the five now-superseded private members**

Find and delete `slovakDayWord` (currently lines 38-44):

```swift
    private func slovakDayWord(_ count: Int) -> String {
        switch count {
        case 1: return "deň"
        case 2...4: return "dni"
        default: return "dní"
        }
    }
```

Find and delete `upcomingRainEvent` (currently lines 46-48):

```swift
    private var upcomingRainEvent: RainEvent? {
        UpcomingRainDetector.nextTriggerEvent(in: weatherState.dailyWeather, asOf: Date())
    }
```

Find and delete `nearMissInsight` (currently lines 50-53):

```swift
    private var nearMissInsight: NearMissRainInsight.Case? {
        guard upcomingRainEvent == nil else { return nil }
        return NearMissRainInsight.describe(in: weatherState.dailyWeather, asOf: Date())
    }
```

Find and delete `nearMissText(for:)` (currently lines 55-64):

```swift
    private func nearMissText(for insight: NearMissRainInsight.Case) -> String {
        switch insight {
        case .rainWithoutHeat(let date, let precipitationMm, _):
            let daysUntil = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 1)
            return "O \(daysUntil) \(slovakDayWord(daysUntil)) mierny dážď (\(String(format: "%.0f", precipitationMm)) mm), ale bez dostatočného tepla na nárast rastu."
        case .heatWithoutRain(let date, _, let maxTempC):
            let daysUntil = max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 1)
            return "O \(daysUntil) \(slovakDayWord(daysUntil)) teplo (\(Int(maxTempC.rounded()))°C), ale bez výraznejšieho dažďa."
        }
    }
```

Find and delete `rainIncomingSection` (currently lines 66-113):

```swift
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
            } else if weatherState.isLoading {
                Text("Načítavam predpoveď…")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else if weatherState.errorMessage != nil {
                Text("Predpoveď nie je k dispozícii.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else if let nearMiss = nearMissInsight {
                Text(nearMissText(for: nearMiss))
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else {
                Text("Žiadny výraznejší dážď v predpovedi.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
        }
    }
```

- [ ] **Step 4: Replace the `ForestPanel { rainIncomingSection }` line**

Find (currently line 134, inside `body`'s `ScrollView`):

```swift
                ForestPanel { rainIncomingSection }
```

Replace with:

```swift
                ForestPanel { MushroomSignalHeroView(signals: appState.signals, dailyWeather: weatherState.dailyWeather, region: region, today: Date()) }
```

- [ ] **Step 5: Build**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
```

Fix any compile errors before proceeding — in particular, confirm no other code in this
file (or elsewhere) referenced the five deleted members. If the build fails on a missing
symbol outside this file, that's a real dependency this plan didn't account for — stop
and investigate rather than re-adding the deleted code as a workaround.

- [ ] **Step 6: Visually verify all 4 states**

```bash
pkill -f "MushroomSignal.app" 2>/dev/null
open DerivedData/Build/Products/Debug/MushroomSignal.app
```

Navigate to Predpoveď. Take a screenshot and confirm, by actually looking at it — a
passing build is not sufficient evidence this task is done:

1. The hero panel appears in `rainIncomingSection`'s old slot (below the top-picks
   cards, above the season calendar), inside the same `ForestPanel` frosted-glass
   styling as every other section.
2. Whatever state is live today (check which by reasoning about current weather, or
   temporarily hardcode `MushroomSignalHeroState.resolve`'s inputs to force each case one
   at a time and revert after) renders: icon badge, headline, subline, and the
   `region · month · season` context row all visible and legible against the panel
   background.
3. If today is a loud state (flush-happening or rain-incoming), the mini temp+rain chart
   renders beneath the headline/subline, above the context row.
4. If today is flush-happening: the three mushroom caps animate in with a staggered
   entrance on load, then settle into a slow breathing pulse. Scroll the hero off-screen
   and back — confirm the animation replays cleanly rather than glitching or stacking.
5. Toggle **System Settings → Accessibility → Display → Reduce Motion** on, relaunch the
   app, and confirm (if flush-happening is active) the caps render at full size
   immediately with no entrance animation and no breathing loop — not stuck at the
   shrunk `scaleY(0.15)` starting point.
6. Near-miss and no-rain states (force them via the same temporary-hardcode technique
   if today isn't naturally one of them) show their full badge + headline + subline +
   context row — not an empty-looking or truncated panel.

- [ ] **Step 7: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: both green, same pass counts as after Task 7 (this task only rewires an
existing view's call site — no new testable logic).

- [ ] **Step 8: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: replace rainIncomingSection with the Mushroom Signal hero"
```
