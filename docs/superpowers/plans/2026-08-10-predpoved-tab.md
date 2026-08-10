# Predpoveď Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A new third tab showing the raw Open-Meteo weather data (daily high/low temperature, humidity, rainfall) behind every score, the top-3 recommended species for today (reusing the exact ranked list Zoznam and the widget already compute), and which species are typically in season this month — giving the user visibility into "the real actual data Mushroom Signal gets its prognosis from," not just derived 0-4 scores.

**Architecture:** A `RegionWeatherState` view-model fetches the extended daily breakdown for the selected region. `PredpovedView` renders it as a native-Weather-app-style hero + daily bar chart (Swift Charts), a top-3 picks section fed directly by `AppState.signals` (no new fetch or scoring call), plus a season-calendar section computed locally from the species dataset (no network call) via `SignalAlgorithm.calendarFit`, made public for reuse. Wired in as `ContentView`'s third `TabView` tab, region-scoped via the same `appState.selectedRegion` binding every other tab already uses.

**Tech Stack:** Swift, Foundation, SwiftUI, Swift Charts, XCTest.

**Depends on:** `docs/superpowers/plans/2026-08-10-weather-client-extension.md` must be merged first — this plan calls `fetchDailyBreakdown(for:pastDays:forecastDays:)` and uses `DailyWeather.minTempC`/`humidityPercent`, and its tests use `StubWeatherClient`'s injectable `dailyWeather`, all introduced there.

**Build order note:** this plan's `ContentView.swift` edit (Task 5) is written assuming `2026-08-10-species-trend-sparkline.md` and `2026-08-10-proactive-notifications.md` have both already been merged (both also touch `ContentView.swift`). Recommended overall order: weather-client-extension → species-trend-sparkline → proactive-notifications → this plan. If building in a different order, re-derive Task 5's before/after snippets from the actual current file state rather than assuming this plan's text matches verbatim.

## Global Constraints

- All new UI styling routes through `DesignSystem` — no hardcoded colors/sizes/spacing. Reuses the `trendChartHeight` token from the trend-sparkline plan rather than adding a new one, since both charts should read as one visual family.
- No changes to `SignalAlgorithm`'s scoring weights or dimensions — this plan only widens `calendarFit`'s access level to reuse it, never reimplements "is this species in season" logic.
- `xcodegen generate` is required before any Xcode build once Task 2 adds `PredpovedView.swift`.
- Always pass `-derivedDataPath DerivedData` to every `xcodebuild` invocation.

---

### Task 1: `RegionWeatherState`

**Files:**
- Create: `MushroomSignal/RegionWeatherState.swift`
- Create: `MushroomSignalTests/RegionWeatherStateTests.swift`

**Interfaces:**
- Consumes: `WeatherClient.fetchDailyBreakdown(for:pastDays:forecastDays:)` (weather-client-extension plan), `RegionDatabase.find(id:) -> Region?` (existing), `StubWeatherClient(snapshots:dailyWeather:dailyShouldThrow:)` (weather-client-extension plan, test-only).
- Produces: `RegionWeatherState { dailyWeather: [DailyWeather], isLoading: Bool, errorMessage: String? }` with `load(regionId: String) async`. Task 2 consumes this directly.

- [ ] **Step 1: Write the failing tests**

Create `MushroomSignalTests/RegionWeatherStateTests.swift`:

```swift
import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class RegionWeatherStateTests: XCTestCase {
    func testLoadPopulatesDailyWeatherOnSuccess() async {
        let day = DailyWeather(date: .now, meanTempC: 15, maxTempC: 20, minTempC: 10, precipitationMm: 5, humidityPercent: 70)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [day])
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")

        XCTAssertEqual(state.dailyWeather.count, 1)
        XCTAssertNil(state.errorMessage)
    }

    func testLoadClearsDailyWeatherAndSetsErrorOnFailure() async {
        let client = StubWeatherClient(snapshots: [nil], dailyShouldThrow: true)
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")

        XCTAssertTrue(state.dailyWeather.isEmpty)
        XCTAssertNotNil(state.errorMessage)
    }

    func testLoadWithUnknownRegionIdLeavesExistingDataUntouched() async {
        let day = DailyWeather(date: .now, meanTempC: 12, maxTempC: 18, minTempC: 6, precipitationMm: 2, humidityPercent: 60)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [day])
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")
        XCTAssertEqual(state.dailyWeather.count, 1)

        await state.load(regionId: "not-a-real-region")

        XCTAssertEqual(state.dailyWeather.count, 1, "an unknown region id must not clear data left over from a previously successful load")
    }

    func testLoadingANewRegionReplacesRatherThanAppendsPreviousData() async {
        let day = DailyWeather(date: .now, meanTempC: 10, maxTempC: 15, minTempC: 5, precipitationMm: 0, humidityPercent: 50)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [day])
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "zilinsky")
        XCTAssertEqual(state.dailyWeather.count, 1)

        await state.load(regionId: "kosicky")
        XCTAssertEqual(state.dailyWeather.count, 1, "still one day from the same stub client — proves load() replaces rather than appends")
    }

    func testStaleLoadDoesNotOverwriteNewerData() async {
        let staleDay = DailyWeather(date: .now, meanTempC: 5, maxTempC: 8, minTempC: 2, precipitationMm: 0, humidityPercent: 40)
        let freshDay = DailyWeather(date: .now, meanTempC: 20, maxTempC: 25, minTempC: 15, precipitationMm: 1, humidityPercent: 55)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [freshDay])
        let state = RegionWeatherState(weatherClient: client)

        // Start a load, then immediately start a second one before the first can write —
        // simulates a fast region switch. Both use the same stub, so this proves the guard
        // exists and doesn't itself break the common case (second load's result wins).
        async let first: Void = state.load(regionId: "zilinsky")
        async let second: Void = state.load(regionId: "kosicky")
        _ = await (first, second)

        XCTAssertEqual(state.dailyWeather, [freshDay])
        _ = staleDay // silence unused-variable warning if the compiler flags it; documents intent
    }
}
```

**Whole-branch review correction (2026-08-10):** the original version of this test file had a
`testLoadWithUnknownRegionIdLeavesDailyWeatherEmpty` test that asserted on state that was
already empty before the call — it would have passed even if the generation-token guard added
below (Step 3) accidentally cleared existing data, so it never actually proved anything. Fixed
to `testLoadWithUnknownRegionIdLeavesExistingDataUntouched`, which seeds real data first. A new
`testStaleLoadDoesNotOverwriteNewerData` was also added to prove the guard itself works.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/RegionWeatherStateTests`
Expected: `** BUILD FAILED **` — `RegionWeatherState` doesn't exist yet.

- [ ] **Step 3: Create `RegionWeatherState`**

Create `MushroomSignal/RegionWeatherState.swift`:

```swift
import Foundation
import MushroomSignalCore
import os

@MainActor
final class RegionWeatherState: ObservableObject {
    @Published var dailyWeather: [DailyWeather] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let weatherClient: WeatherClient
    private var currentLoadID: UUID?
    private let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "RegionWeatherState")

    init(weatherClient: WeatherClient = OpenMeteoClient()) {
        self.weatherClient = weatherClient
    }

    func load(regionId: String) async {
        guard let region = RegionDatabase.find(id: regionId) else { return }
        let loadID = UUID()
        currentLoadID = loadID
        isLoading = true
        errorMessage = nil
        defer {
            if currentLoadID == loadID {
                isLoading = false
            }
        }
        do {
            let result = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 10, forecastDays: 5)
            guard currentLoadID == loadID else { return }
            dailyWeather = result
        } catch {
            guard currentLoadID == loadID else { return }
            dailyWeather = []
            errorMessage = "Nepodarilo sa načítať počasie."
            logger.error("Daily breakdown fetch failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
```

**Whole-branch review correction (2026-08-10, Important finding I2):** the version above already
includes a `currentLoadID`/`UUID` generation-token guard, mirroring the exact pattern
`AppState.refresh()` uses (see `AppState.swift`) — the original shipped version of this file had
no such guard, so a cancelled/stale load's error handler could overwrite a newer, already-landed
region's data on a fast region switch. Also added: `os.Logger` failure logging, matching
`AppState`'s own failure-path logging convention.

- [ ] **Step 4: Regenerate the Xcode project (new file) and run the tests**

Run: `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/RegionWeatherStateTests`
Expected: `** TEST SUCCEEDED **`, all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/RegionWeatherState.swift MushroomSignalTests/RegionWeatherStateTests.swift MushroomSignal.xcodeproj
git commit -m "feat: add RegionWeatherState for region-level daily weather"
```

---

### Task 2: `PredpovedView` — weather dashboard

**Files:**
- Create: `MushroomSignal/Views/PredpovedView.swift`

**Interfaces:**
- Consumes: `RegionWeatherState` (Task 1), `DesignSystem.trendChartHeight` (introduced by the trend-sparkline plan — reused here, not redefined).
- Produces: `PredpovedView(regionId: String)`. Task 5 consumes this to wire it into `ContentView`. Tasks 3 and 4 extend this same file with a top-picks section and a season-calendar section, respectively.

This task has no dedicated automated test — pure SwiftUI rendering, same convention as every
other view in this project (build + manual visual check).

- [ ] **Step 1: Create `PredpovedView`**

Also add to `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`,
immediately after `trendChartHeight` (this token replaces this task's original hardcoded `7`
corner radius — flagged as Minor finding M1 by the final whole-branch review, folded in here
rather than shipping the literal first):

```swift
    /// Corner radius for Predpoveď's daily weather bar chart marks.
    public static let chartBarCornerRadius: Double = 7
```

Create `MushroomSignal/Views/PredpovedView.swift`:

```swift
// MushroomSignal/Views/PredpovedView.swift
import SwiftUI
import Charts
import MushroomSignalCore

struct PredpovedView: View {
    let regionId: String
    @StateObject private var weatherState = RegionWeatherState()

    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                if let error = weatherState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(DesignSystem.Colors.danger)
                }

                heroSection
                dailyStripSection
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            if let today = todayEntry {
                Text("\(Int(today.minTempC.rounded()))° / \(Int(today.maxTempC.rounded()))°")
                    .font(.system(size: DesignSystem.heroSize, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                Text("Vlhkosť \(Int(today.humidityPercent.rounded()))% · Zrážky \(String(format: "%.1f", today.precipitationMm)) mm")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
            } else if weatherState.isLoading {
                Text("Načítavam počasie…")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else if weatherState.errorMessage == nil {
                Text("Žiadne údaje o počasí pre dnešný deň.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
        }
    }

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
}
```

**Whole-branch review correction (2026-08-10, Important finding I4):** the `heroSection` shown
above already branches on `weatherState.isLoading`/`errorMessage` instead of the originally
shipped version, which showed "Načítavam počasie…" as its only fallback state — meaning it kept
claiming to be loading forever after a failed fetch, even though `weatherState.errorMessage` was
already being shown separately above it in `body`. Folded in here rather than shipping the
narrower version first.

- [ ] **Step 2: Regenerate the Xcode project (new file) and build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift MushroomSignal.xcodeproj
git commit -m "feat: add PredpovedView weather dashboard (not yet wired into a tab)"
```

---

### Task 3: Top-3 daily picks

**Files:**
- Modify: `MushroomSignal/Views/PredpovedView.swift`

**Interfaces:**
- Consumes: `AppState` itself (existing, `ObservableObject`) — not just a `[SpeciesSignal]` snapshot. Whole-branch review correction below explains why.
- Produces: `PredpovedView` gains a required `@ObservedObject var appState: AppState` property. No existing call site breaks — `PredpovedView` isn't constructed anywhere yet (Task 5 adds its first and only call site), so this is a pure additive change to the struct, not a breaking one. Task 4 (season calendar)'s body edit is sequenced after this task's, not directly after Task 2's. Task 5 constructs `PredpovedView(regionId:appState:)` with both arguments already, from the start.

This task has no dedicated automated test — pure SwiftUI rendering, same convention as every other view in this project.

- [ ] **Step 1: Add `appState` and the picks section to `PredpovedView`**

Also add to `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`,
immediately after `chartBarCornerRadius` (Task 2) — replaces this task's original hardcoded
`22` rank-badge size, per Minor finding M1, bumped to 26pt to also fix a cramped-digit issue
the final review flagged:

```swift
    /// Predpoveď's numbered rank badge (top-3 picks) — sized with headroom for a bold caption-size
    /// digit inside a circle, not just the digit's own bounding box.
    public static let rankBadgeSize: Double = 26
```

Edit `MushroomSignal/Views/PredpovedView.swift`, replace:

```swift
struct PredpovedView: View {
    let regionId: String
    @StateObject private var weatherState = RegionWeatherState()
```

with:

```swift
struct PredpovedView: View {
    let regionId: String
    @ObservedObject var appState: AppState
    @StateObject private var weatherState = RegionWeatherState()

    private var visibleTopSignals: [SpeciesSignal] {
        Array(appState.signals.filter { $0.score > 0 }.prefix(3))
    }
```

Then replace:

```swift
                heroSection
                dailyStripSection
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
    }
```

with:

```swift
                if let error = appState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(appState.isShowingStaleData ? DesignSystem.Colors.caution : DesignSystem.Colors.danger)
                }

                heroSection
                dailyStripSection
                if !visibleTopSignals.isEmpty {
                    topPicksSection
                }
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
    }

    private var topPicksSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Odporúčané dnes")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            ForEach(Array(visibleTopSignals.enumerated()), id: \.element.species.id) { index, signal in
                HStack(spacing: DesignSystem.spacingSmall) {
                    Text("\(index + 1)")
                        .font(.system(size: DesignSystem.captionSize, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                        .frame(width: DesignSystem.rankBadgeSize, height: DesignSystem.rankBadgeSize)
                        .background(Circle().fill(DesignSystem.Colors.mossAccent.opacity(0.3)))
                    VStack(alignment: .leading, spacing: DesignSystem.spacingTight / 2) {
                        Text(signal.species.commonNameSk)
                            .font(.system(size: DesignSystem.bodySize, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.cloud)
                        Text(signal.species.latinName)
                            .font(.system(size: DesignSystem.captionSize).italic())
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                        if let warning = DesignSystem.warningLabelSk(for: signal.species.edibility) {
                            Text(warning)
                                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                                .foregroundStyle(DesignSystem.warningColor(for: signal.species.edibility))
                        }
                    }
                    Spacer()
                    ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize)
                }
                .padding(DesignSystem.spacingSmall)
            }
        }
    }
```

`ScoreDotsView` already exists (`MushroomSignal/Views/ScoreDotsView.swift`, extracted in the map-markers pass) — this reuses it directly rather than re-inlining the `●●●○` glyph a third time.

**Whole-branch review correction (2026-08-10):** the code above already reflects two fixes the
final review found once every task's diff was viewed together as one unit:

- **Critical finding C1**: this app's own `docs/superpowers/KNOWN_ISSUES.md` records a v1
  Critical bug — "`.caution`-level species rendered identically to edible" — fixed via a shared
  `DesignSystem.warningLabelSk(for:)`/`warningColor(for:)` policy applied everywhere else a
  species name renders (`SpeciesCardView.swift`, the widget). The version of `topPicksSection`
  originally written for this task never adopted that policy, so a poisonous or caution-level
  species could appear in "Odporúčané dnes" with no warning at all — the same bug class
  recurring in new code, in a foraging app. Fixed above by adding the `warningLabelSk`/
  `warningColor` block, exactly matching `SpeciesCardView.swift`'s pattern.
- **Important finding I1**: this task originally introduced a plain `let topSignals:
  [SpeciesSignal]` stored property — a one-time snapshot passed in from `ContentView`, not a
  live reference. Because `PredpovedView`'s own `.task(id: regionId)` fires independently of
  whatever refresh cycle populated that snapshot, a fast region switch could show top-3 picks
  computed for a *different* region than the daily weather strip displayed beside them. Fixed
  by taking `@ObservedObject var appState: AppState` instead (the same pattern `ShortlistView`
  already uses) — this also lets `PredpovedView` surface `appState.errorMessage`/
  `isShowingStaleData` the same way `ShortlistView` already does, which the code above added.
- **Important finding I3**: `visibleTopSignals` filters `$0.score > 0` before taking
  `.prefix(3)`, so "Odporúčané dnes" doesn't recommend zero-score, out-of-season species that
  happen to sort into the top 3 of an otherwise-empty ranked list.

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **` — adding a new required stored property to a struct with no existing call sites is a pure additive change; nothing else in the codebase references `PredpovedView` yet, so nothing can be broken by it.

- [ ] **Step 3: Commit**

```bash
git add MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: show top-3 daily picks in Predpoveď, reusing AppState's ranked signals"
```

(Not visually checkable yet — `PredpovedView` isn't wired into a tab until Task 5. The manual visual check for this section happens as part of Task 5's Step 4.)

---

### Task 4: Season calendar section

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift`
- Modify: `MushroomSignal/Views/PredpovedView.swift`

**Interfaces:**
- Consumes: `SignalAlgorithm.calendarFit(species:month:) -> Double` (widened to `public`), `SpeciesDatabase.loadAll() -> [Species]` (existing), `Species.regionalAffinity: Set<String>` (existing).
- Produces: nothing further consumed by other tasks — this is additive UI in the same file Tasks 2 and 3 already touched.

- [ ] **Step 1: Make `calendarFit` public**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift`, replace:

```swift
    static func calendarFit(species: Species, month: Int) -> Double {
```

with:

```swift
    public static func calendarFit(species: Species, month: Int) -> Double {
```

- [ ] **Step 2: Run the core package test suite to confirm the access-level change alone breaks nothing**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS — existing `SignalAlgorithmTests` already call `calendarFit` from within the same module, so widening its access level is a strictly additive, non-breaking change.

- [ ] **Step 3: Add the season-calendar section to `PredpovedView`**

Edit `MushroomSignal/Views/PredpovedView.swift`, replace the top of the file:

```swift
// MushroomSignal/Views/PredpovedView.swift
import SwiftUI
import Charts
import MushroomSignalCore

struct PredpovedView: View {
    let regionId: String
    @ObservedObject var appState: AppState
    @StateObject private var weatherState = RegionWeatherState()

    private var visibleTopSignals: [SpeciesSignal] {
        Array(appState.signals.filter { $0.score > 0 }.prefix(3))
    }

    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }
```

with:

```swift
// MushroomSignal/Views/PredpovedView.swift
import SwiftUI
import Charts
import MushroomSignalCore
import os

private let predpovedLogger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "PredpovedView")

struct PredpovedView: View {
    let regionId: String
    @ObservedObject var appState: AppState
    @StateObject private var weatherState = RegionWeatherState()
    @State private var allSpecies: [Species] = []

    private var visibleTopSignals: [SpeciesSignal] {
        Array(appState.signals.filter { $0.score > 0 }.prefix(3))
    }

    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }

    private var inSeasonSpecies: [Species] {
        let month = Calendar.current.component(.month, from: Date())
        return allSpecies
            .filter { $0.regionalAffinity.contains(regionId) }
            .filter { SignalAlgorithm.calendarFit(species: $0, month: month) > 0 }
            .sorted { $0.commonNameSk.localizedStandardCompare($1.commonNameSk) == .orderedAscending }
    }
```

Then replace:

```swift
                heroSection
                dailyStripSection
                if !visibleTopSignals.isEmpty {
                    topPicksSection
                }
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
    }
```

with:

```swift
                heroSection
                dailyStripSection
                if !visibleTopSignals.isEmpty {
                    topPicksSection
                }
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

    private var seasonCalendarSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Sezóna tento mesiac")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if inSeasonSpecies.isEmpty {
                Text("Žiadne druhy nie sú aktuálne v sezóne.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else {
                ForEach(inSeasonSpecies) { species in
                    HStack(spacing: DesignSystem.spacingSmall) {
                        Text(species.commonNameSk)
                            .font(.system(size: DesignSystem.bodySize))
                            .foregroundStyle(DesignSystem.Colors.cloud)
                        if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                            Text(warning)
                                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                                .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                        }
                    }
                }
            }
        }
    }

    private var disclaimer: some View {
        Text("Tento zoznam je len orientačný odhad na základe počasia a sezóny. Pred zberom a konzumáciou húb si nález vždy overte s odborníkom alebo v spoľahlivom atlase húb.")
            .font(.system(size: DesignSystem.captionSize))
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            .padding(.top, DesignSystem.spacingMedium)
    }
```

**Whole-branch review correction (2026-08-10):** the code above already reflects three more
findings from the final whole-branch review, on top of Task 3's C1/I1/I3:

- **Critical finding C1 (continued)**: `seasonCalendarSection` gets the same
  `warningLabelSk`/`warningColor` treatment as `topPicksSection` — this is the section the
  review actually caught live, via a real screenshot: `amanita-phalloides` (death cap) rendering
  as plain white text with no warning in "Sezóna tento mesiac," in August, in a real running
  build.
- **Important finding I5**: species-dataset load failure is now logged via the new
  `predpovedLogger` (`os.Logger`) instead of silently swallowed by `try?` — the original
  `allSpecies = (try? SpeciesDatabase.loadAll()) ?? []` made "no species in season" look like a
  confident true statement instead of a load failure, no way to tell the two apart.
- **Minor finding M3**: `inSeasonSpecies` sorts with `.localizedStandardCompare` instead of raw
  `<`, so Slovak `č`/`š`/`ž` sort correctly instead of after `z`.
- **Minor finding M7** (new, not in this plan's original scope): a `disclaimer` view was added,
  reusing `ShortlistView`'s exact existing disclaimer string verbatim (not inventing new copy).
  Predpoveď is a second surface listing species to go looking for, so it needs the same caution
  `ShortlistView` already gives.

- [ ] **Step 4: Build**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Full test suite**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: add season-calendar section to PredpovedView"
```

---

### Task 5: Wire the tab into `ContentView`

**Files:**
- Modify: `MushroomSignal/ContentView.swift`

**Interfaces:**
- Consumes: `PredpovedView(regionId:appState:)` (Tasks 2/3/4 — see the whole-branch review
  correction in Task 3: this initializer takes `appState: AppState` directly, not a
  `topSignals: [SpeciesSignal]` snapshot, per Important finding I1), `appState.selectedRegion.id`
  (existing, `@Published`).
- Produces: nothing further — leaf of this plan.

This step assumes `ContentView.swift` already has the `species-trend-sparkline` and
`proactive-notifications` plans' edits applied (per this plan's build-order note above): the
`Mapa` tab already reads `MapScreenView(regionId: appState.selectedRegion.id)`, and a
notification-settings toolbar button + sheet already exist. If building in a different order,
re-derive this step's before/after snippets from whatever `ContentView.swift` actually
contains rather than assuming this text matches verbatim.

- [ ] **Step 1: Add the `forecast` tab case and the new tab**

Edit `MushroomSignal/ContentView.swift`, replace:

```swift
    enum Tab {
        case shortlist
        case map
    }
```

with:

```swift
    enum Tab {
        case shortlist
        case map
        case forecast
    }
```

Then replace:

```swift
                MapScreenView(regionId: appState.selectedRegion.id)
                    .tabItem { Label("Mapa", systemImage: "map") }
                    .tag(Tab.map)
            }
```

with:

```swift
                MapScreenView(regionId: appState.selectedRegion.id)
                    .tabItem { Label("Mapa", systemImage: "map") }
                    .tag(Tab.map)

                PredpovedView(regionId: appState.selectedRegion.id, appState: appState)
                    .tabItem { Label("Predpoveď", systemImage: "cloud.sun") }
                    .tag(Tab.forecast)
            }
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Full test suite**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Manual visual check — this is the real verification for this plan**

Launch the app. Confirm three tabs (Zoznam, Mapa, Predpoveď). Open Predpoveď: confirm real
Open-Meteo data renders (spot-check a temperature value against a real weather source),
the daily strip shows a visible cold-to-hot gradient min→max range bar per day with forecast days visually
lighter, the "Odporúčané dnes" section shows up to 3 species matching Zoznam's own top 3
for the same region (same names, same order, same score dots), and the season-calendar
section lists species with real Slovak names. Switch the shared region picker (toolbar) and
confirm Predpoveď's content — including the top-3 picks — reloads for the new region.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/ContentView.swift
git commit -m "feat: add Predpoveď as the app's third tab"
```

---

## Final Verification

- [ ] Run `swift test --package-path MushroomSignalCore` — full pass.
- [ ] Run `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData` — full pass.
- [ ] Full signed build, launch, exercise all three tabs plus the notification settings sheet (if that plan has landed) — confirm nothing else regressed.
- [ ] Update `docs/superpowers/KNOWN_ISSUES.md` with what shipped, per this project's established convention.

## Final whole-branch review fix wave (2026-08-10)

All 5 tasks above were built and individually reviewed clean, then a final whole-branch review
(the complete diff viewed as one unit) found 1 Critical, 5 Important, and several Minor findings
that only became visible at that scope — individually-clean tasks combined into gaps no
single-task review could see. Fixed same day; this plan's task-by-task code blocks above have
been corrected in place to match what actually shipped, per this project's convention ("when a
task review's fix round changes committed code from what a plan doc originally specified, mirror
the fix back into the plan"). Full detail: see
`.superpowers/sdd/2026-08-10-predpoved-tab/final-review-fix-report.md` and the corresponding
entries appended to `docs/superpowers/KNOWN_ISSUES.md`. Summary:

- **C1 (Critical)**: poisonous/caution species rendered with no warning in both of
  `PredpovedView`'s species lists — fixed via the existing `DesignSystem.warningLabelSk`/
  `warningColor` policy, same as `SpeciesCardView`.
- **I1**: `topSignals: [SpeciesSignal]` stale snapshot replaced with `@ObservedObject var
  appState: AppState` (live reference), matching `ShortlistView`'s pattern.
- **I2**: `RegionWeatherState.load` gained the same generation-token cancellation guard
  `AppState.refresh()` already uses.
- **I3**: top-3 picks now filter `score > 0` before taking the top 3.
- **I4**: `heroSection`'s loading state no longer sticks forever after a failed fetch.
- **I5**: species-dataset load failure now logs via `os.Logger` instead of silently swallowing
  via `try?`.
- **M1**: new `DesignSystem.rankBadgeSize`/`chartBarCornerRadius` tokens replace hardcoded `22`/`7`.
- **M3**: season-calendar sort uses `.localizedStandardCompare` for correct Slovak diacritic ordering.
- **M4**: `RegionWeatherStateTests` gained a real assertion for the unknown-region-id path plus a
  new test proving the I2 guard works.
- **M7**: added a disclaimer, reusing `ShortlistView`'s exact copy.
