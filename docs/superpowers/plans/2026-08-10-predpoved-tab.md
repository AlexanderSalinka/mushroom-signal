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

    func testLoadWithUnknownRegionIdLeavesDailyWeatherEmpty() async {
        let client = StubWeatherClient(snapshots: [nil])
        let state = RegionWeatherState(weatherClient: client)

        await state.load(regionId: "not-a-real-region")

        XCTAssertTrue(state.dailyWeather.isEmpty)
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/RegionWeatherStateTests`
Expected: `** BUILD FAILED **` — `RegionWeatherState` doesn't exist yet.

- [ ] **Step 3: Create `RegionWeatherState`**

Create `MushroomSignal/RegionWeatherState.swift`:

```swift
import Foundation
import MushroomSignalCore

@MainActor
final class RegionWeatherState: ObservableObject {
    @Published var dailyWeather: [DailyWeather] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let weatherClient: WeatherClient

    init(weatherClient: WeatherClient = OpenMeteoClient()) {
        self.weatherClient = weatherClient
    }

    func load(regionId: String) async {
        guard let region = RegionDatabase.find(id: regionId) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            dailyWeather = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 10, forecastDays: 5)
        } catch {
            dailyWeather = []
            errorMessage = "Nepodarilo sa načítať počasie."
        }
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project (new file) and run the tests**

Run: `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/RegionWeatherStateTests`
Expected: `** TEST SUCCEEDED **`, all 4 tests pass.

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
            } else {
                Text("Načítavam počasie…")
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
                .foregroundStyle(isForecastDay(day) ? DesignSystem.Colors.mossAccent.opacity(0.5) : DesignSystem.Colors.mossAccent)
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
- Consumes: `AppState.signals: [SpeciesSignal]` (existing, `@Published`) — the exact same ranked list Zoznam and the widget already display, via the shared `SignalPipeline`. No new fetch, no new scoring call — real reuse, per Alexander's explicit ask.
- Produces: `PredpovedView` gains a new required `topSignals: [SpeciesSignal]` stored property. No existing call site breaks — `PredpovedView` isn't constructed anywhere yet (Task 5 adds its first and only call site), so this is a pure additive change to the struct, not a breaking one. Task 4 (season calendar)'s body edit is sequenced after this task's, not directly after Task 2's. Task 5 constructs `PredpovedView(regionId:topSignals:)` with both arguments already, from the start.

This task has no dedicated automated test — pure SwiftUI rendering, same convention as every other view in this project.

- [ ] **Step 1: Add `topSignals` and the picks section to `PredpovedView`**

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
    let topSignals: [SpeciesSignal]
    @StateObject private var weatherState = RegionWeatherState()
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
                heroSection
                dailyStripSection
                if !topSignals.isEmpty {
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
            ForEach(Array(topSignals.prefix(3).enumerated()), id: \.element.species.id) { index, signal in
                HStack(spacing: DesignSystem.spacingSmall) {
                    Text("\(index + 1)")
                        .font(.system(size: DesignSystem.captionSize, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(DesignSystem.Colors.mossAccent.opacity(0.3)))
                    VStack(alignment: .leading, spacing: DesignSystem.spacingTight / 2) {
                        Text(signal.species.commonNameSk)
                            .font(.system(size: DesignSystem.bodySize, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.cloud)
                        Text(signal.species.latinName)
                            .font(.system(size: DesignSystem.captionSize).italic())
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
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

Edit `MushroomSignal/Views/PredpovedView.swift`, replace:

```swift
struct PredpovedView: View {
    let regionId: String
    let topSignals: [SpeciesSignal]
    @StateObject private var weatherState = RegionWeatherState()

    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }
```

with:

```swift
struct PredpovedView: View {
    let regionId: String
    let topSignals: [SpeciesSignal]
    @StateObject private var weatherState = RegionWeatherState()
    @State private var allSpecies: [Species] = []

    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }

    private var inSeasonSpecies: [Species] {
        let month = Calendar.current.component(.month, from: Date())
        return allSpecies
            .filter { $0.regionalAffinity.contains(regionId) }
            .filter { SignalAlgorithm.calendarFit(species: $0, month: month) > 0 }
            .sorted { $0.commonNameSk < $1.commonNameSk }
    }
```

Then replace:

```swift
                heroSection
                dailyStripSection
                if !topSignals.isEmpty {
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
                if !topSignals.isEmpty {
                    topPicksSection
                }
                seasonCalendarSection
            }
            .padding(DesignSystem.spacingLarge)
        }
        .mushroomGlassBackground()
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
        .task {
            allSpecies = (try? SpeciesDatabase.loadAll()) ?? []
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
                    Text(species.commonNameSk)
                        .font(.system(size: DesignSystem.bodySize))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                }
            }
        }
    }
```

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
- Consumes: `PredpovedView(regionId:topSignals:)` (Tasks 2/3/4), `appState.selectedRegion.id` and `appState.signals` (both existing, `@Published`).
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

                PredpovedView(regionId: appState.selectedRegion.id, topSignals: appState.signals)
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
the daily strip shows a visible min→max range bar per day with forecast days visually
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
