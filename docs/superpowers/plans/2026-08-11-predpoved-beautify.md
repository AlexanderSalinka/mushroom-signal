# Predpoveď Beautify: Chart, Containers, Window Scaling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Predpoveď's daily chart as a real temp/rain chart with a range toggle, wrap its four sections in frosted-glass panels, cap the app window's content at 1024×768 (matching Apple Weather), rebuild the season calendar as full-width ranked rows, and give the rain-incoming empty state a near-miss forecast message.

**Architecture:** Two new pure functions in `MushroomSignalCore` (`MostRecentRainfall`, `NearMissRainInsight`), two new SwiftUI views in the app target (`WeatherRainChartView`, `ForestPanel`), and targeted edits to `PredpovedView`, `RegionWeatherState`, `ContentView`, and three other screens' background wiring.

**Tech Stack:** SwiftUI, Swift Charts, XCTest — same stack as the rest of the app, no new dependencies.

## Global Constraints

- All new UI styling routes through `DesignSystem` — never hardcode ad hoc colors/sizes (project `CLAUDE.md`).
- Never a dual-axis chart (two y-scales sharing one plot) — each measure gets its own single-axis panel (spec §1, `dataviz` skill guidance).
- Body/running text stays ≥20pt (`DesignSystem.captionSize` floor, set 2026-08-08); chart axis chrome is a documented exception, same precedent as `mapMarkerDotSize`.
- New files under `MushroomSignal/` (the Xcode app target) require `xcodegen generate` after creation, or the build silently omits them — files under `MushroomSignalCore/` (a Swift Package) are auto-discovered, no `xcodegen` step needed.
- Never hand-edit `MushroomSignal.xcodeproj` — always regenerate via `xcodegen generate` from `project.yml`.
- Pin `-derivedDataPath DerivedData` on every `xcodebuild` invocation (repo convention, avoids duplicate Launch Services registrations).
- Core logic changes: verify with `swift test --package-path MushroomSignalCore`. App-target view changes: verify with a headless `xcodebuild build` (`CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`, a throwaway derived-data path per the project's headless-build convention — never combine these flags with the pinned signed `DerivedData` path).

---

## Task 1: `MostRecentRainfall` pure function

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/MostRecentRainfall.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/MostRecentRainfallTests.swift`

**Interfaces:**
- Produces: `MostRecentRainfall.find(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> (date: Date, precipitationMm: Double)?` — consumed by Task 8 (`WeatherRainChartView`'s "last rain" callout).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MushroomSignalCore

final class MostRecentRainfallTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func daysAgo(_ n: Int, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(-Double(n) * 86400), meanTempC: 18, maxTempC: 22, minTempC: 14, precipitationMm: precipitationMm, humidityPercent: 70)
    }

    func testFindsMostRecentRainyDay() {
        let days = [daysAgo(5, precipitationMm: 3.0), daysAgo(2, precipitationMm: 8.0), daysAgo(8, precipitationMm: 1.0)]
        let result = MostRecentRainfall.find(in: days, asOf: today)
        XCTAssertEqual(result?.precipitationMm, 8.0)
    }

    func testDryDaysDoNotCount() {
        let days = [daysAgo(1, precipitationMm: 0.0), daysAgo(2, precipitationMm: 0.0)]
        XCTAssertNil(MostRecentRainfall.find(in: days, asOf: today))
    }

    func testEmptyArrayReturnsNil() {
        XCTAssertNil(MostRecentRainfall.find(in: [], asOf: today))
    }

    func testForecastFutureDaysAreExcludedEvenIfRainy() {
        let futureRain = DailyWeather(date: today.addingTimeInterval(2 * 86400), meanTempC: 18, maxTempC: 22, minTempC: 14, precipitationMm: 20.0, humidityPercent: 80)
        let pastRain = daysAgo(4, precipitationMm: 6.0)
        let result = MostRecentRainfall.find(in: [futureRain, pastRain], asOf: today)
        XCTAssertEqual(result?.precipitationMm, 6.0)
    }

    func testMultipleRainyDaysReturnsMostRecentNotLargest() {
        let days = [daysAgo(1, precipitationMm: 2.0), daysAgo(6, precipitationMm: 40.0)]
        let result = MostRecentRainfall.find(in: days, asOf: today)
        XCTAssertEqual(result?.precipitationMm, 2.0)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter MostRecentRainfallTests`
Expected: FAIL (build error) with "cannot find 'MostRecentRainfall' in scope"

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Answers "when did it last actually rain" from already-loaded weather data — the fact behind
/// `WeatherRainChartView`'s "Naposledy pršalo" callout. Deliberately independent of
/// `FlushTriggerDetector`'s thresholds: any measurable rain counts here, not just a flush-
/// triggering amount.
public enum MostRecentRainfall {
    public static func find(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> (date: Date, precipitationMm: Double)? {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        let mostRecent = dailyWeather
            .filter { utcCalendar.startOfDay(for: $0.date) <= todayStart }
            .filter { $0.precipitationMm > 0 }
            .sorted { $0.date > $1.date }
            .first

        guard let mostRecent else { return nil }
        return (date: mostRecent.date, precipitationMm: mostRecent.precipitationMm)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter MostRecentRainfallTests`
Expected: PASS, 5 tests

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/MostRecentRainfall.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/MostRecentRainfallTests.swift
git commit -m "feat: add MostRecentRainfall pure function for the chart's last-rain callout"
```

---

## Task 2: `NearMissRainInsight` pure function

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/NearMissRainInsight.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/NearMissRainInsightTests.swift`

**Interfaces:**
- Consumes: `FlushTriggerDetector.minTriggerMaxTempC`, `FlushTriggerDetector.minTriggerPrecipitationMm` (existing constants).
- Produces: `NearMissRainInsight.Case` enum (`.rainWithoutHeat(date:precipitationMm:maxTempC:)`, `.heatWithoutRain(date:precipitationMm:maxTempC:)`) and `NearMissRainInsight.describe(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> Case?` — consumed by Task 10 (`rainIncomingSection`'s expanded empty state).

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MushroomSignalCore

final class NearMissRainInsightTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func daysFromNow(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, minTempC: maxTempC - 10, precipitationMm: precipitationMm, humidityPercent: 70)
    }

    func testRainWithoutHeatIsDetected() {
        let days = [daysFromNow(2, maxTempC: 18.0, precipitationMm: 12.0)]
        let result = NearMissRainInsight.describe(in: days, asOf: today)
        XCTAssertEqual(result, .rainWithoutHeat(date: days[0].date, precipitationMm: 12.0, maxTempC: 18.0))
    }

    func testHeatWithoutRainIsDetected() {
        let days = [daysFromNow(3, maxTempC: 29.0, precipitationMm: 0.0)]
        let result = NearMissRainInsight.describe(in: days, asOf: today)
        XCTAssertEqual(result, .heatWithoutRain(date: days[0].date, precipitationMm: 0.0, maxTempC: 29.0))
    }

    func testFlatForecastReturnsNil() {
        let days = [daysFromNow(1, maxTempC: 18.0, precipitationMm: 0.0), daysFromNow(2, maxTempC: 20.0, precipitationMm: 1.0)]
        XCTAssertNil(NearMissRainInsight.describe(in: days, asOf: today))
    }

    func testFullTriggerDayIsSkippedNotReportedAsNearMiss() {
        let days = [daysFromNow(2, maxTempC: 28.0, precipitationMm: 11.0)]
        XCTAssertNil(NearMissRainInsight.describe(in: days, asOf: today))
    }

    func testReturnsEarliestQualifyingNearMiss() {
        let days = [daysFromNow(4, maxTempC: 18.0, precipitationMm: 12.0), daysFromNow(1, maxTempC: 29.0, precipitationMm: 0.0)]
        let result = NearMissRainInsight.describe(in: days, asOf: today)
        XCTAssertEqual(result, .heatWithoutRain(date: days[1].date, precipitationMm: 0.0, maxTempC: 29.0))
    }

    func testPastDaysAreIgnored() {
        let pastNearMiss = DailyWeather(date: today.addingTimeInterval(-2 * 86400), meanTempC: 15, maxTempC: 18, minTempC: 10, precipitationMm: 12.0, humidityPercent: 70)
        XCTAssertNil(NearMissRainInsight.describe(in: [pastNearMiss], asOf: today))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter NearMissRainInsightTests`
Expected: FAIL (build error) with "cannot find 'NearMissRainInsight' in scope"

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// When `UpcomingRainDetector` finds no real trigger day in the forecast, this looks for a
/// near miss — rain without enough heat, or heat without enough rain — so "Blíži sa dážď"'s
/// empty state can say what IS coming instead of just "nothing." Reuses
/// `FlushTriggerDetector`'s exact thresholds, same one-source-of-truth pattern as
/// `UpcomingRainDetector`. Callers should only consult this after `UpcomingRainDetector
/// .nextTriggerEvent` returns nil — a real trigger day always takes priority.
public enum NearMissRainInsight {
    public enum Case: Equatable, Sendable {
        case rainWithoutHeat(date: Date, precipitationMm: Double, maxTempC: Double)
        case heatWithoutRain(date: Date, precipitationMm: Double, maxTempC: Double)
    }

    public static func describe(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> Case? {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        let forecastDays = dailyWeather
            .filter { $0.date > todayStart }
            .sorted { $0.date < $1.date }

        for day in forecastDays {
            let hasRain = day.precipitationMm >= FlushTriggerDetector.minTriggerPrecipitationMm
            let hasHeat = day.maxTempC >= FlushTriggerDetector.minTriggerMaxTempC
            if hasRain && !hasHeat {
                return .rainWithoutHeat(date: day.date, precipitationMm: day.precipitationMm, maxTempC: day.maxTempC)
            }
            if hasHeat && !hasRain {
                return .heatWithoutRain(date: day.date, precipitationMm: day.precipitationMm, maxTempC: day.maxTempC)
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter NearMissRainInsightTests`
Expected: PASS, 6 tests

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/NearMissRainInsight.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/NearMissRainInsightTests.swift
git commit -m "feat: add NearMissRainInsight pure function for rain-alert empty state"
```

---

## Task 3: New `DesignSystem` tokens for panels, chart, and season rows

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift:85-86` (immediately after `rainHeatChartRowHeight`, before `public enum Colors {`)
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift`

**Interfaces:**
- Produces: `DesignSystem.panelCornerRadius`, `.panelFillOpacity`, `.panelBorderOpacity`, `.panelShadowRadius` (Task 5's `ForestPanel`); `.chartTempPanelHeight`, `.chartRainPanelHeight`, `.chartAxisLabelSize` (Tasks 6-8's `WeatherRainChartView`); `.seasonRowMinWidth`, `.seasonRowCornerRadius` (Task 9's season rows) — all `Double`.

- [ ] **Step 1: Add the new tokens**

In `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`, find:

```swift
    /// Height of each row (heat, rain) in Predpoveď's simplified two-row daily chart.
    public static let rainHeatChartRowHeight: Double = 56

    public enum Colors {
```

Replace with:

```swift
    /// Height of each row (heat, rain) in Predpoveď's simplified two-row daily chart.
    public static let rainHeatChartRowHeight: Double = 56
    /// `ForestPanel`'s corner radius — the frosted-glass section container wrapping each
    /// Predpoveď section (chart, top picks, rain alert, season calendar).
    public static let panelCornerRadius: Double = 18
    /// `ForestPanel`'s translucent fill opacity, over `Colors.forestDeep`.
    public static let panelFillOpacity: Double = 0.55
    /// `ForestPanel`'s hairline border opacity, over `Colors.cloud`.
    public static let panelBorderOpacity: Double = 0.08
    /// `ForestPanel`'s drop shadow radius, giving it depth against the page background.
    public static let panelShadowRadius: Double = 12
    /// `WeatherRainChartView`'s temperature panel height (line chart, y-axis only, no x-axis —
    /// the rain panel below carries the shared date axis for both).
    public static let chartTempPanelHeight: Double = 90
    /// `WeatherRainChartView`'s rain panel height — includes its own y-axis and the shared
    /// x-axis band for both panels (the full chart-plus-axis height, not just the bar area).
    public static let chartRainPanelHeight: Double = 72
    /// `WeatherRainChartView`'s x-axis day-of-month tick label size. Chart chrome, not running
    /// body text — not subject to the 20pt text floor, same precedent as `mapMarkerDotSize`'s
    /// documented exception above.
    public static let chartAxisLabelSize: Double = 9
    /// Minimum width of each full-width season-calendar row (`seasonRow`) — mobile-phone width
    /// at minimum, so a species' full common name is never truncated.
    public static let seasonRowMinWidth: Double = 375
    /// Corner radius for the full-width season-calendar rows (replaces the old pill-shaped
    /// `chipCornerRadius` chips, which were too small to fit full names).
    public static let seasonRowCornerRadius: Double = 12

    public enum Colors {
```

- [ ] **Step 2: Add tests for the new tokens**

In `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift`, add before the final closing `}`:

```swift

    func testPanelOpacitiesAreValidRange() {
        XCTAssertGreaterThan(DesignSystem.panelFillOpacity, 0)
        XCTAssertLessThanOrEqual(DesignSystem.panelFillOpacity, 1)
        XCTAssertGreaterThan(DesignSystem.panelBorderOpacity, 0)
        XCTAssertLessThanOrEqual(DesignSystem.panelBorderOpacity, 1)
    }

    func testSeasonRowMinWidthMeetsMobileWidthFloor() {
        XCTAssertGreaterThanOrEqual(DesignSystem.seasonRowMinWidth, 375)
    }
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter DesignSystemTests`
Expected: PASS, all `DesignSystemTests` tests including the 2 new ones

- [ ] **Step 4: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift
git commit -m "feat: add DesignSystem tokens for section panels, weather chart, and season rows"
```

---

## Task 4: `RegionWeatherState` fetches a 30-day superset

**Files:**
- Modify: `MushroomSignal/RegionWeatherState.swift:31`
- Modify: `MushroomSignalTests/RegionWeatherStateTests.swift`

**Interfaces:**
- Produces: `RegionWeatherState.dailyWeather` now holds 30 past days + 5 forecast days instead of 10+5 — consumed by Tasks 6-8 (`WeatherRainChartView`'s range toggle needs the 30-day superset already loaded).

- [ ] **Step 1: Write the failing test**

In `MushroomSignalTests/RegionWeatherStateTests.swift`, add this private actor after the existing `OrderedRegionStub` declaration (before `@MainActor final class RegionWeatherStateTests`):

```swift
private actor RecordingWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}
    private(set) var lastPastDays: Int?
    private(set) var lastForecastDays: Int?

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot { throw StubError() }
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] { [:] }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        lastPastDays = pastDays
        lastForecastDays = forecastDays
        return []
    }
}
```

Then add this test method inside `RegionWeatherStateTests`:

```swift
    func testLoadRequestsThirtyDaysOfHistoryAndFiveDayForecast() async {
        let client = RecordingWeatherClient()
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")

        let pastDays = await client.lastPastDays
        let forecastDays = await client.lastForecastDays
        XCTAssertEqual(pastDays, 30, "the 7/14/30-day range toggle needs a 30-day superset fetched once, not re-fetched per toggle")
        XCTAssertEqual(forecastDays, 5)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData -only-testing:MushroomSignalTests/RegionWeatherStateTests/testLoadRequestsThirtyDaysOfHistoryAndFiveDayForecast`
Expected: FAIL with `pastDays` equal to 10, not 30

- [ ] **Step 3: Change the fetch range**

In `MushroomSignal/RegionWeatherState.swift`, find:

```swift
            let result = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 10, forecastDays: 5)
```

Replace with:

```swift
            let result = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 30, forecastDays: 5)
```

- [ ] **Step 4: Run the full test file to verify it passes and nothing else broke**

Run: `xcodebuild test -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData -only-testing:MushroomSignalTests/RegionWeatherStateTests`
Expected: PASS, all `RegionWeatherStateTests` including the new one

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/RegionWeatherState.swift MushroomSignalTests/RegionWeatherStateTests.swift
git commit -m "feat: fetch 30 days of history so the range toggle never re-fetches"
```

---

## Task 5: `ForestPanel` container, wraps PredpovedView's four sections

**Files:**
- Create: `MushroomSignal/Views/ForestPanel.swift`
- Modify: `MushroomSignal/Views/PredpovedView.swift:89-129` (the `body` property)

**Interfaces:**
- Consumes: `DesignSystem.panelCornerRadius/.panelFillOpacity/.panelBorderOpacity/.panelShadowRadius` (Task 3).
- Produces: `ForestPanel<Content: View>(content: () -> Content)` — a generic wrapping view, reused as-is by Task 9 (no new interface needed there, just another call site).

- [ ] **Step 1: Create `ForestPanel.swift`**

```swift
// MushroomSignal/Views/ForestPanel.swift
import SwiftUI
import MushroomSignalCore

/// A frosted-glass section container — wraps each PredpovedView section (chart, top picks,
/// rain alert, season calendar) in a translucent, bordered, shadowed panel, replacing the
/// prior bare-VStack-plus-ForestDivider separation. Modeled on macOS System Settings' pane
/// grouping (approved mockup, style 3 — see
/// docs/superpowers/specs/mockups/2026-08-11-predpoved-beautify/container-style.html).
struct ForestPanel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(DesignSystem.spacingMedium)
            .background(DesignSystem.Colors.forestDeep.opacity(DesignSystem.panelFillOpacity))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.panelCornerRadius)
                    .stroke(DesignSystem.Colors.cloud.opacity(DesignSystem.panelBorderOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: DesignSystem.panelShadowRadius, y: 4)
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so it picks up the new file**

Run: `xcodegen generate`

- [ ] **Step 3: Wrap the four sections in `PredpovedView.body` and remove the now-redundant dividers between them**

In `MushroomSignal/Views/PredpovedView.swift`, find:

```swift
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
```

Replace with:

```swift
                heroSection
                ForestPanel { dailyStripSection }
                if !visibleTopSignals.isEmpty {
                    ForestPanel { topPicksSection }
                }
                ForestPanel { rainIncomingSection }
                ForestPanel { seasonCalendarSection }
                disclaimer
```

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData-Headless CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Build a signed run and visually confirm all four sections render as bordered/shadowed panels**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`, launch `DerivedData/Build/Products/Debug/MushroomSignal.app`, open the Predpoveď tab, and compare against `docs/superpowers/specs/mockups/2026-08-11-predpoved-beautify/container-style.html`'s style-3 panel.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignal/Views/ForestPanel.swift MushroomSignal/Views/PredpovedView.swift MushroomSignal.xcodeproj
git commit -m "feat: wrap Predpoveď sections in frosted-glass ForestPanel containers"
```

---

## Task 6: `WeatherRainChartView` — base two-panel chart, replaces `dailyStripSection`

**Files:**
- Create: `MushroomSignal/Views/WeatherRainChartView.swift`
- Modify: `MushroomSignal/Views/PredpovedView.swift` (remove `pastTenDays` and `dailyStripSection`, update the call site added in Task 5)

**Interfaces:**
- Consumes: `DesignSystem.chartTempPanelHeight/.chartRainPanelHeight/.chartAxisLabelSize/.chartBarCornerRadius` (Task 3 + existing), `DesignSystem.Colors.caution/.water` (existing).
- Produces: `WeatherRainChartView(dailyWeather: [DailyWeather], today: Date)` — extended in Task 7 (adds `selectedRange` state) and Task 8 (adds today-marker + last-rain callout). `PredpovedView` now calls this instead of `dailyStripSection`.

- [ ] **Step 1: Create `WeatherRainChartView.swift`**

```swift
// MushroomSignal/Views/WeatherRainChartView.swift
import SwiftUI
import Charts
import MushroomSignalCore

/// Predpoveď's daily weather chart — temperature line above rain bars, each with its own
/// honest y-axis (never a shared/dual-axis scale — see the 2026-08-11 predpoved-beautify
/// spec §1 for why: a dual-axis chart invents a correlation that isn't in the data).
struct WeatherRainChartView: View {
    let dailyWeather: [DailyWeather]
    let today: Date

    private var visibleDays: [DailyWeather] {
        let calendar = Calendar.current
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

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Posledných 7 dní + predpoveď")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))

            VStack(spacing: 0) {
                Chart(visibleDays, id: \.date) { day in
                    LineMark(
                        x: .value("Deň", day.date, unit: .day),
                        y: .value("Teplota", day.maxTempC)
                    )
                    .foregroundStyle(DesignSystem.Colors.caution)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .frame(height: DesignSystem.chartTempPanelHeight)
                .chartXAxis(.hidden)

                Chart(visibleDays, id: \.date) { day in
                    BarMark(
                        x: .value("Deň", day.date, unit: .day),
                        y: .value("Zrážky", day.precipitationMm)
                    )
                    .foregroundStyle(DesignSystem.Colors.water)
                    .cornerRadius(DesignSystem.chartBarCornerRadius * 0.5)
                }
                .frame(height: DesignSystem.chartRainPanelHeight)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Calendar.current.isDateInToday(date) ? "dnes" : date.formatted(.dateTime.day()))
                                    .font(.system(size: DesignSystem.chartAxisLabelSize))
                            }
                        }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so it picks up the new file**

Run: `xcodegen generate`

- [ ] **Step 3: Replace `dailyStripSection` with `WeatherRainChartView` in `PredpovedView`**

In `MushroomSignal/Views/PredpovedView.swift`, find:

```swift
                heroSection
                ForestPanel { dailyStripSection }
```

Replace with:

```swift
                heroSection
                ForestPanel { WeatherRainChartView(dailyWeather: weatherState.dailyWeather, today: Date()) }
```

Then delete the now-unused `pastTenDays` computed property and `dailyStripSection` computed property entirely — find and remove:

```swift
    private var pastTenDays: [DailyWeather] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        return Array(weatherState.dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
            .suffix(10))
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
            .chartXAxis(.hidden)
            .chartLegend(.hidden)

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

- [ ] **Step 4: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData-Headless CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Build a signed run and visually confirm the chart renders as two stacked single-axis panels with no gap**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`, launch, open Predpoveď, confirm the temperature line sits directly above the rain bars with one shared x-axis at the bottom (day-of-month labels) and no visible second axis on the temperature panel.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignal/Views/WeatherRainChartView.swift MushroomSignal/Views/PredpovedView.swift MushroomSignal.xcodeproj
git commit -m "feat: replace dailyStripSection with a real temp/rain chart, honest single axes"
```

---

## Task 7: Add the 7/14/30-day range toggle

**Files:**
- Modify: `MushroomSignal/Views/WeatherRainChartView.swift`

**Interfaces:**
- Consumes: nothing new (still just `dailyWeather`, `today`).
- Produces: `WeatherRainChartView` now owns `@State private var selectedRange: Int` — internal state, no external interface change (callers still just pass `dailyWeather`/`today`).

- [ ] **Step 1: Add the toggle and wire it into the day-slicing logic**

In `MushroomSignal/Views/WeatherRainChartView.swift`, find:

```swift
struct WeatherRainChartView: View {
    let dailyWeather: [DailyWeather]
    let today: Date

    private var visibleDays: [DailyWeather] {
        let calendar = Calendar.current
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

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Posledných 7 dní + predpoveď")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))

            VStack(spacing: 0) {
```

Replace with:

```swift
struct WeatherRainChartView: View {
    let dailyWeather: [DailyWeather]
    let today: Date
    @State private var selectedRange: Int = 7

    private var visibleDays: [DailyWeather] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: today)
        let pastDays = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
            .suffix(selectedRange)
        let forecastDays = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) > todayStart }
            .sorted { $0.date < $1.date }
        return Array(pastDays) + forecastDays
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            HStack {
                Text("Posledných \(selectedRange) dní + predpoveď")
                    .font(.system(size: DesignSystem.captionSize, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                Spacer()
                Picker("Rozsah", selection: $selectedRange) {
                    Text("7").tag(7)
                    Text("14").tag(14)
                    Text("30").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 160)
                .labelsHidden()
            }

            VStack(spacing: 0) {
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData-Headless CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Build a signed run and visually confirm the toggle re-slices instantly with no loading spinner**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`, launch, open Predpoveď, click `7`/`14`/`30` and confirm the chart redraws immediately (no network delay) and every visible day still has its own x-axis label at all three range sizes.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/WeatherRainChartView.swift
git commit -m "feat: add 7/14/30-day range toggle to the weather chart, client-side slicing only"
```

---

## Task 8: Add "today" marker and "last rain" callout

**Files:**
- Modify: `MushroomSignal/Views/WeatherRainChartView.swift`

**Interfaces:**
- Consumes: `MostRecentRainfall.find(in:asOf:calendar:)` (Task 1).
- Produces: no new external interface — visual additions only.

- [ ] **Step 1: Add the today-marker overlay and last-rain callout**

In `MushroomSignal/Views/WeatherRainChartView.swift`, find the closing of the `visibleDays` computed property and the start of `body`:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            HStack {
```

Replace with (adds two new computed properties before `body`):

```swift
    private var todayFraction: Double? {
        guard let todayIndex = visibleDays.firstIndex(where: { Calendar.current.isDateInToday($0.date) }) else { return nil }
        return (Double(todayIndex) + 0.5) / Double(visibleDays.count)
    }

    private var lastRainText: String {
        guard let recent = MostRecentRainfall.find(in: dailyWeather, asOf: today) else {
            return "Bez zaznamenaných zrážok za posledných 30 dní."
        }
        let daysAgo = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: recent.date),
            to: Calendar.current.startOfDay(for: today)
        ).day ?? 0
        let amount = String(format: "%.0f", recent.precipitationMm)
        if daysAgo == 0 {
            return "Dnes pršalo (\(amount) mm)."
        }
        let dayWord = daysAgo == 1 ? "dňom" : "dňami"
        return "Naposledy pršalo pred \(daysAgo) \(dayWord) (\(amount) mm)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            HStack {
```

Then find the end of the two-chart `VStack(spacing: 0) { ... }` block and the closing of `body`:

```swift
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Calendar.current.isDateInToday(date) ? "dnes" : date.formatted(.dateTime.day()))
                                    .font(.system(size: DesignSystem.chartAxisLabelSize))
                            }
                        }
                    }
                }
            }
        }
    }
}
```

Replace with:

```swift
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(Calendar.current.isDateInToday(date) ? "dnes" : date.formatted(.dateTime.day()))
                                    .font(.system(size: DesignSystem.chartAxisLabelSize))
                            }
                        }
                    }
                }
            }
            .overlay(alignment: .topLeading) {
                if let todayFraction {
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(DesignSystem.Colors.cloud.opacity(0.35))
                            .frame(width: 1.5)
                            .position(x: geometry.size.width * todayFraction, y: geometry.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
            }

            Text(lastRainText)
                .font(.system(size: DesignSystem.captionSize * 0.65))
                .foregroundStyle(DesignSystem.Colors.water)
                .padding(.top, DesignSystem.spacingTight)
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData-Headless CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Build a signed run and visually verify the marker aligns with today's bar and the callout text is correct**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`, launch, open Predpoveď. Confirm a vertical line crosses both panels roughly at the boundary between past and forecast bars, and the text below reads a plausible "Naposledy pršalo pred N dňami" or the no-rain fallback. **If the marker visibly misaligns with the actual today bar** (a real risk — `todayFraction`'s band-center approximation isn't guaranteed to match Swift Charts' exact internal bar positions), adjust the `(Double(todayIndex) + 0.5) / Double(visibleDays.count)` formula empirically against the rendered chart rather than leaving it misaligned; this was flagged as an implementation-detail open question in the spec.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/WeatherRainChartView.swift
git commit -m "feat: add today marker and last-rain callout to the weather chart"
```

---

## Task 9: Season calendar rebuilt as full-width ranked rows

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift` (`seasonCalendarSection`, `seasonChip`, add `rankedInSeasonSpecies`)

**Interfaces:**
- Consumes: `appState.signals: [SpeciesSignal]` (existing, already holds every species' score, not just the top 4), `DesignSystem.seasonRowMinWidth/.seasonRowCornerRadius` (Task 3).
- Produces: no external interface change — internal rewrite of `seasonCalendarSection`.

- [ ] **Step 1: Add score-based ranking and rebuild the row/chip rendering**

In `MushroomSignal/Views/PredpovedView.swift`, find:

```swift
    private var inSeasonSpecies: [Species] {
        let month = Calendar.current.component(.month, from: Date())
        return allSpecies
            .filter { $0.regionalAffinity.contains(regionId) }
            .filter { SignalAlgorithm.calendarFit(species: $0, month: month) > 0 }
            .sorted { $0.commonNameSk.localizedStandardCompare($1.commonNameSk) == .orderedAscending }
    }
```

Replace with:

```swift
    private var inSeasonSpecies: [Species] {
        let month = Calendar.current.component(.month, from: Date())
        return allSpecies
            .filter { $0.regionalAffinity.contains(regionId) }
            .filter { SignalAlgorithm.calendarFit(species: $0, month: month) > 0 }
            .sorted { $0.commonNameSk.localizedStandardCompare($1.commonNameSk) == .orderedAscending }
    }

    private var rankedInSeasonSpecies: [Species] {
        let scoreById = Dictionary(uniqueKeysWithValues: appState.signals.map { ($0.species.id, $0.score) })
        return inSeasonSpecies.sorted { (scoreById[$0.id] ?? 0) > (scoreById[$1.id] ?? 0) }
    }
```

Then find:

```swift
    private var seasonCalendarSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Sezóna tento mesiac")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: DesignSystem.spacingSmall)], spacing: DesignSystem.spacingSmall) {
                    ForEach(inSeasonSpecies) { species in
                        seasonChip(for: species)
                    }
                }
            }
        }
    }

    // Edible species get a moss swatch, matching the approved mockup's default chip. Caution
    // and poisonous species get their swatch recolored via the same `warningColor` policy used
    // everywhere else species appear (SpeciesCardView, topPicksSection), plus the same explicit
    // Slovak warning text — a color-only signal isn't sufficient for a foraging app's safety
    // info (colorblind accessibility, and this app never approximates safety-critical content).
    private func seasonChip(for species: Species) -> some View {
        let swatchColor = species.edibility == .edible ? DesignSystem.Colors.mossAccent : DesignSystem.warningColor(for: species.edibility)
        return VStack(alignment: .leading, spacing: DesignSystem.spacingTight / 2) {
            HStack(spacing: 7) {
                LeafShape()
                    .stroke(swatchColor, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: DesignSystem.chipDotSize + 4, height: DesignSystem.chipDotSize + 4)
                Text(species.commonNameSk)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                Text(warning)
                    .font(.system(size: DesignSystem.captionSize, weight: .bold))
                    .foregroundStyle(swatchColor)
            }
        }
        .padding(EdgeInsets(top: 7, leading: 10, bottom: 7, trailing: 14))
        .background(swatchColor.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.chipCornerRadius)
                .stroke(swatchColor.opacity(0.45), lineWidth: 1)
        )
    }
```

Replace with:

```swift
    private var seasonCalendarSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Sezóna tento mesiac")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if rankedInSeasonSpecies.isEmpty {
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
                VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                    ForEach(Array(rankedInSeasonSpecies.enumerated()), id: \.element.id) { index, species in
                        seasonRow(rank: index + 1, species: species)
                    }
                }
            }
        }
    }

    // Edible species get a moss swatch, matching the approved mockup's default chip. Caution
    // and poisonous species get their swatch recolored via the same `warningColor` policy used
    // everywhere else species appear (SpeciesCardView, topPicksSection), plus the same explicit
    // Slovak warning text — a color-only signal isn't sufficient for a foraging app's safety
    // info (colorblind accessibility, and this app never approximates safety-critical content).
    // The warning now sits inline on the row's trailing edge instead of stacking below the
    // name, so caution/poisonous rows are the same height as edible ones — the sign stays,
    // the extra line doesn't (2026-08-11 predpoved-beautify spec §5).
    private func seasonRow(rank: Int, species: Species) -> some View {
        let swatchColor = species.edibility == .edible ? DesignSystem.Colors.mossAccent : DesignSystem.warningColor(for: species.edibility)
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: DesignSystem.captionSize * 0.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.35))
                .frame(width: 16, alignment: .trailing)
            LeafShape()
                .stroke(swatchColor, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                .frame(width: DesignSystem.chipDotSize + 4, height: DesignSystem.chipDotSize + 4)
            Text(species.commonNameSk)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.cloud)
            Spacer(minLength: 8)
            if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                Text(warning)
                    .font(.system(size: DesignSystem.captionSize * 0.6, weight: .bold))
                    .foregroundStyle(swatchColor)
                    .lineLimit(1)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 14))
        .frame(minWidth: DesignSystem.seasonRowMinWidth, alignment: .leading)
        .background(swatchColor.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.seasonRowCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.seasonRowCornerRadius)
                .stroke(swatchColor.opacity(0.35), lineWidth: 1)
        )
    }
```

Note: the name `Text(species.commonNameSk)` deliberately has **no** `.lineLimit(1)` — the whole point of this task is that names never truncate. At `seasonRowMinWidth` (375pt) this will read as one line for virtually every real name in the dataset; an exceptionally long name is allowed to wrap to two lines rather than ever showing an ellipsis.

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData-Headless CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Build a signed run and visually verify full-width rows, no truncated names, ranked order, and equal row heights**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`, launch, open Predpoveď, scroll to "Sezóna tento mesiac." Confirm: every row shows the complete species name with no ellipsis; rows are ordered by score (cross-check against `appState.signals`, e.g. via the top-picks section showing the same top species first); caution/poisonous rows are the same height as edible rows (warning badge inline, not stacked). Compare against `docs/superpowers/specs/mockups/2026-08-11-predpoved-beautify/season-chips.html`.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: rebuild season calendar as full-width rows ranked by score"
```

---

## Task 10: Near-miss forecast messaging in "Blíži sa dážď"

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift` (`rainIncomingSection`)

**Interfaces:**
- Consumes: `NearMissRainInsight.describe(in:asOf:calendar:)` and `NearMissRainInsight.Case` (Task 2), existing `slovakDayWord(_:)` helper.
- Produces: no external interface change.

- [ ] **Step 1: Add the near-miss lookup and wire it into the empty-state branch**

In `MushroomSignal/Views/PredpovedView.swift`, find:

```swift
    private var upcomingRainEvent: RainEvent? {
        UpcomingRainDetector.nextTriggerEvent(in: weatherState.dailyWeather, asOf: Date())
    }
```

Replace with:

```swift
    private var upcomingRainEvent: RainEvent? {
        UpcomingRainDetector.nextTriggerEvent(in: weatherState.dailyWeather, asOf: Date())
    }

    private var nearMissInsight: NearMissRainInsight.Case? {
        guard upcomingRainEvent == nil else { return nil }
        return NearMissRainInsight.describe(in: weatherState.dailyWeather, asOf: Date())
    }

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

Then find the final `else` branch of `rainIncomingSection`:

```swift
            } else if weatherState.errorMessage != nil {
                Text("Predpoveď nie je k dispozícii.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else {
                Text("Žiadny výraznejší dážď v predpovedi.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
```

Replace with:

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData-Headless CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Build a signed run and visually verify the expanded message appears when applicable**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`, launch, open Predpoveď. Since real forecast data will rarely land exactly on a near-miss day, confirm correctness by temporarily reading the current forecast values in a debugger/log rather than requiring a specific visual state — the priority logic (`upcomingRainEvent` wins, then near-miss, then flat fallback) is what to verify structurally.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: expand Blíži sa dážď empty state with near-miss forecast messaging"
```

---

## Task 11: App-wide window size cap + centralized background

**Files:**
- Modify: `MushroomSignal/ContentView.swift`
- Modify: `MushroomSignal/Views/ShortlistView.swift:33`
- Modify: `MushroomSignal/Views/MapScreenView.swift:23`
- Modify: `MushroomSignal/Views/SpeciesDetailView.swift:64`
- Modify: `MushroomSignal/Views/PredpovedView.swift` (its own `.mushroomGlassBackground()` call)

**Interfaces:**
- Consumes: existing `mushroomGlassBackground()` view extension (`GlassBackground.swift`, unchanged).
- Produces: no new interface — moves where an existing modifier is called.

- [ ] **Step 1: Cap the TabView content and centralize the background in `ContentView`**

In `MushroomSignal/ContentView.swift`, find:

```swift
                PredpovedView(regionId: appState.selectedRegion.id, appState: appState)
                    .tabItem { Label("Predpoveď", systemImage: "cloud.sun") }
                    .tag(Tab.forecast)
            }
            .navigationTitle("Mushroom Signal")
```

Replace with:

```swift
                PredpovedView(regionId: appState.selectedRegion.id, appState: appState)
                    .tabItem { Label("Predpoveď", systemImage: "cloud.sun") }
                    .tag(Tab.forecast)
            }
            .frame(maxWidth: 1024, maxHeight: 768)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Mushroom Signal")
```

Then find:

```swift
        .task { await appState.refresh() }
        .frame(minWidth: 420, minHeight: 480)
        .background(WindowTransparencyConfigurator())
```

Replace with:

```swift
        .mushroomGlassBackground()
        .task { await appState.refresh() }
        .frame(minWidth: 420, minHeight: 480)
        .background(WindowTransparencyConfigurator())
```

- [ ] **Step 2: Remove the now-redundant per-screen background calls**

In `MushroomSignal/Views/ShortlistView.swift`, find:

```swift
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .refreshable { await appState.refresh() }
```

Replace with:

```swift
            .padding(DesignSystem.spacingLarge)
        }
        .refreshable { await appState.refresh() }
```

In `MushroomSignal/Views/MapScreenView.swift`, find:

```swift
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
    }
}
```

Replace with:

```swift
            .padding(DesignSystem.spacingLarge)
        }
    }
}
```

In `MushroomSignal/Views/SpeciesDetailView.swift`, find:

```swift
                .padding(DesignSystem.spacingLarge)
            }
            .mushroomGlassBackground()
            .toolbar {
```

Replace with:

```swift
                .padding(DesignSystem.spacingLarge)
            }
            .toolbar {
```

In `MushroomSignal/Views/PredpovedView.swift`, find:

```swift
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .task(id: regionId) {
```

Replace with:

```swift
            .padding(DesignSystem.spacingLarge)
        }
        .task(id: regionId) {
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData-Headless CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Build a signed run and visually verify the window cap and background on all three tabs**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`, launch, and:
1. Resize the window well past 1024×768 (or full-screen it) — confirm the tab content stays capped and centered, with the translucent forest background filling the remaining space, on Zoznam, Mapa, and Predpoveď.
2. Resize the window down toward its minimum (420×480) — confirm existing adaptive layouts (Zoznam's grid, etc.) still reflow correctly, unaffected by the new upper cap.
3. Open a species detail sheet (from Zoznam) — confirm it still renders inside the capped/backgrounded shell rather than escaping it (a real risk introduced by moving the background call, flagged in the spec).
4. Confirm the background's light-blob animation still runs (it should now run once for the whole window, not once per tab).

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/ContentView.swift MushroomSignal/Views/ShortlistView.swift MushroomSignal/Views/MapScreenView.swift MushroomSignal/Views/SpeciesDetailView.swift MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: cap window content at 1024x768 and centralize the glass background"
```

---

## Final Verification

- [ ] Run the full core test suite: `swift test --package-path MushroomSignalCore` — expect all tests passing, including the new `MostRecentRainfallTests`, `NearMissRainInsightTests`, and the 2 new `DesignSystemTests`.
- [ ] Run the full app test suite: `xcodebuild test -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData` — expect all tests passing, including the new `RegionWeatherStateTests` test.
- [ ] Build a final signed run (`xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`) and walk through every mockup comparison listed in the spec's Testing section: `chart-final.html` (7-day and 30-day states), `container-style.html` (panel style), `season-chips.html` (ranked full-width rows).
- [ ] Confirm no dead code remains: `pastTenDays`, the old `dailyStripSection`, and the old `seasonChip(for:)` should no longer exist anywhere in `PredpovedView.swift`.
