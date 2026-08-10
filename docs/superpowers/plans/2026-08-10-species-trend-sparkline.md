# Species Trend Sparkline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a ~10-day-past + 4-day-forecast score trend chart per species in `SpeciesDetailView`, so a flush building or fading is visible instead of inferred from a single number.

**Architecture:** A pure `SpeciesTrendCalculator` runs the existing `SignalAlgorithm.computeSignal` once per day (via a new single-day `WeatherSnapshot` factory) over a fetched `[DailyWeather]` window. A small `SpeciesTrendState` view-model wires this to `SpeciesDetailView`, rendered with Swift Charts. `SpeciesDetailView` needs a region to fetch weather for, which requires threading a `regionId` through `MapScreenView`/`SpeciesLibraryView` (Mapa's presentation path currently has none).

**Tech Stack:** Swift, Foundation, SwiftUI, Swift Charts (macOS 13+, available at this project's macOS 14.0 deployment target, unused elsewhere in the repo), XCTest.

**Depends on:** `docs/superpowers/plans/2026-08-10-weather-client-extension.md` must be merged first — this plan calls `fetchDailyBreakdown(for:pastDays:forecastDays:)` and uses `DailyWeather.humidityPercent`/`minTempC`, both introduced there.

## Global Constraints

- All new UI styling routes through `DesignSystem` — no hardcoded colors/sizes/spacing.
- No changes to `SignalAlgorithm`, `SignalPipeline`, or `FlushTriggerDetector`'s own logic — this plan only adds new *call sites* of the existing scoring function, never a new algorithm.
- `xcodegen generate` is required before any Xcode build in this plan — Task 2 adds a new file under `MushroomSignal/`.
- Always pass `-derivedDataPath DerivedData` to every `xcodebuild` invocation.

---

### Task 1: `WeatherSnapshot.singleDay` + `SpeciesTrendCalculator`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SpeciesTrendCalculator.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesTrendCalculatorTests.swift`

**Interfaces:**
- Consumes: `SignalAlgorithm.computeSignal(species:weather:month:flushTriggered:) -> SpeciesSignal` (existing, unchanged), `FlushTriggerDetector.triggered(in:asOf:calendar:) -> Bool` (existing, unchanged), `DailyWeather` (extended by the weather-client-extension plan — has `minTempC`/`humidityPercent` now).
- Produces: `WeatherSnapshot.singleDay(regionId:day:) -> WeatherSnapshot` and `SpeciesTrendCalculator.trend(species:dailyWeather:regionId:today:) -> [TrendPoint]`, where `TrendPoint { date: Date, score: Int, isForecast: Bool }`. Task 2 consumes both.

- [ ] **Step 1: Write the failing tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesTrendCalculatorTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class SpeciesTrendCalculatorTests: XCTestCase {
    private func species(fruitingMonths: Set<Int> = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], rainfallSensitivity: RainfallSensitivity = .low) -> Species {
        Species(id: "test", commonNameSk: "Test", latinName: "Testus", edibility: .edible, fruitingMonths: fruitingMonths, idealTempMinC: 10, idealTempMaxC: 25, idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90, rainfallSensitivity: rainfallSensitivity, habitat: "test", regionalAffinity: [])
    }

    private func day(daysFromReference: Int, reference: Date, maxTempC: Double = 20, meanTempC: Double = 15, minTempC: Double = 10, precipitationMm: Double = 10, humidityPercent: Double = 75) -> DailyWeather {
        DailyWeather(date: reference.addingTimeInterval(Double(daysFromReference) * 86400), meanTempC: meanTempC, maxTempC: maxTempC, minTempC: minTempC, precipitationMm: precipitationMm, humidityPercent: humidityPercent)
    }

    // 2026-08-07 00:00:00 UTC — matches FlushTriggerDetectorTests' reference date, so day
    // boundaries line up cleanly with 86400s-multiple offsets.
    private let today = Date(timeIntervalSince1970: 1_754_524_800)

    func testTrendReturnsOnePointPerInputDay() {
        let days = (0..<10).map { day(daysFromReference: -$0, reference: today) }
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: days, regionId: "zilinsky", today: today)
        XCTAssertEqual(points.count, 10)
    }

    func testOffSeasonDayScoresZero() {
        let outOfSeason = species(fruitingMonths: [1]) // January only; "today" is August 2026
        let days = [day(daysFromReference: -1, reference: today)]
        let points = SpeciesTrendCalculator.trend(species: outOfSeason, dailyWeather: days, regionId: "zilinsky", today: today)
        XCTAssertEqual(points.first?.score, 0)
    }

    func testFlushTriggerBoostsScoreForHighSensitivitySpecies() {
        let highSensitivity = species(rainfallSensitivity: .high)

        // Baseline: no day in range qualifies (maxTempC 20 < the 26 threshold).
        let daysWithoutTrigger = (0..<10).map { day(daysFromReference: -$0, reference: today, precipitationMm: 10, humidityPercent: 95) }
        let pointsWithoutTrigger = SpeciesTrendCalculator.trend(species: highSensitivity, dailyWeather: daysWithoutTrigger, regionId: "zilinsky", today: today)

        // 5 days before "today" now qualifies (maxTempC >= 26, precip >= 5) — inside the
        // detector's 2-7 day lag window when evaluated as-of "today" (index 0).
        var daysWithTrigger = daysWithoutTrigger
        daysWithTrigger[5] = day(daysFromReference: -5, reference: today, maxTempC: 30, precipitationMm: 10, humidityPercent: 95)
        let pointsWithTrigger = SpeciesTrendCalculator.trend(species: highSensitivity, dailyWeather: daysWithTrigger, regionId: "zilinsky", today: today)

        XCTAssertGreaterThan(pointsWithTrigger[0].score, pointsWithoutTrigger[0].score, "a qualifying flush day in the window should raise today's trend score for a high-rainfall-sensitivity species")
    }

    func testDayAfterTodayIsMarkedAsForecast() {
        let forecastDay = day(daysFromReference: 1, reference: today)
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: [forecastDay], regionId: "zilinsky", today: today)
        XCTAssertEqual(points.first?.isForecast, true)
    }

    func testDayBeforeTodayIsNotMarkedAsForecast() {
        let pastDay = day(daysFromReference: -1, reference: today)
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: [pastDay], regionId: "zilinsky", today: today)
        XCTAssertEqual(points.first?.isForecast, false)
    }

    func testTodayItselfIsNotMarkedAsForecast() {
        let todayPoint = day(daysFromReference: 0, reference: today)
        let points = SpeciesTrendCalculator.trend(species: species(), dailyWeather: [todayPoint], regionId: "zilinsky", today: today)
        XCTAssertEqual(points.first?.isForecast, false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter SpeciesTrendCalculatorTests`
Expected: FAIL to compile — `WeatherSnapshot.singleDay` and `SpeciesTrendCalculator` don't exist yet.

- [ ] **Step 3: Add `WeatherSnapshot.singleDay`**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift`, append after the closing brace of the `WeatherSnapshot` struct:

```swift

public extension WeatherSnapshot {
    /// Builds a WeatherSnapshot from ONE day's readings, reusing SignalAlgorithm's existing
    /// fit functions for trend-chart scoring. Deliberate simplification, not a true 10-day
    /// rolling aggregate like every other WeatherSnapshot in this app — a trend dot may not
    /// exactly equal what the shortlist showed that historical day. The value here is
    /// direction (improving/fading), not exact historical reproduction. See
    /// docs/superpowers/specs/2026-08-10-sparkline-notifications-predpoved-design.md.
    static func singleDay(regionId: String, day: DailyWeather) -> WeatherSnapshot {
        WeatherSnapshot(
            regionId: regionId,
            averageTempLast10DaysC: day.meanTempC,
            averageHumidityLast10DaysPercent: day.humidityPercent,
            totalPrecipitationLast10DaysMm: day.precipitationMm,
            fetchedAt: day.date
        )
    }
}
```

- [ ] **Step 4: Create `SpeciesTrendCalculator`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SpeciesTrendCalculator.swift`:

```swift
import Foundation

public struct TrendPoint: Equatable, Sendable {
    public let date: Date
    public let score: Int
    public let isForecast: Bool

    public init(date: Date, score: Int, isForecast: Bool) {
        self.date = date
        self.score = score
        self.isForecast = isForecast
    }
}

/// Turns a daily-weather series into a per-day score series for one species, reusing
/// SignalAlgorithm.computeSignal via WeatherSnapshot.singleDay — no new scoring logic.
public enum SpeciesTrendCalculator {
    public static func trend(
        species: Species,
        dailyWeather: [DailyWeather],
        regionId: String,
        today: Date = Date()
    ) -> [TrendPoint] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = calendar.startOfDay(for: today)

        return dailyWeather.map { day in
            let snapshot = WeatherSnapshot.singleDay(regionId: regionId, day: day)
            let month = calendar.component(.month, from: day.date)
            let flushTriggered = FlushTriggerDetector.triggered(in: dailyWeather, asOf: day.date, calendar: calendar)
            let signal = SignalAlgorithm.computeSignal(species: species, weather: snapshot, month: month, flushTriggered: flushTriggered)
            let dayStart = calendar.startOfDay(for: day.date)
            return TrendPoint(date: day.date, score: signal.score, isForecast: dayStart > todayStart)
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter SpeciesTrendCalculatorTests`
Expected: PASS, all 6 tests.

- [ ] **Step 6: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS, no regressions.

- [ ] **Step 7: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift MushroomSignalCore/Sources/MushroomSignalCore/Signal/SpeciesTrendCalculator.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesTrendCalculatorTests.swift
git commit -m "feat: add SpeciesTrendCalculator for per-day trend scoring"
```

---

### Task 2: Thread a `regionId` into `SpeciesDetailView` (Mapa currently has none)

**Files:**
- Modify: `MushroomSignal/ContentView.swift`
- Modify: `MushroomSignal/Views/MapScreenView.swift`
- Modify: `MushroomSignal/Views/SpeciesLibraryView.swift`
- Modify: `MushroomSignal/Views/ShortlistView.swift`

**Interfaces:**
- Consumes: `AppState.selectedRegion: Region` (existing, `@Published`).
- Produces: `MapScreenView(regionId: String)` and `SpeciesLibraryView(mapState:regionId:)` gain a new required parameter. Task 3 consumes `SpeciesDetailView`'s new `regionId: String` property.

`ShortlistView` already has `appState` and can supply `appState.selectedRegion.id` directly —
only `MapScreenView`/`SpeciesLibraryView` need new plumbing. Confirmed via direct read:
`MapScreenView` currently creates its own `MapScreenState` with zero region awareness, and
`ContentView` instantiates it with no parameters.

- [ ] **Step 1: Thread `regionId` through `ContentView` → `MapScreenView`**

Edit `MushroomSignal/ContentView.swift`, replace:

```swift
                MapScreenView()
                    .tabItem { Label("Mapa", systemImage: "map") }
                    .tag(Tab.map)
```

with:

```swift
                MapScreenView(regionId: appState.selectedRegion.id)
                    .tabItem { Label("Mapa", systemImage: "map") }
                    .tag(Tab.map)
```

- [ ] **Step 2: Accept and forward `regionId` in `MapScreenView`**

Edit `MushroomSignal/Views/MapScreenView.swift`, replace:

```swift
struct MapScreenView: View {
    @StateObject private var mapState = MapScreenState()
    @State private var mapHeight: CGFloat = DesignSystem.mapDefaultHeight
```

with:

```swift
struct MapScreenView: View {
    let regionId: String
    @StateObject private var mapState = MapScreenState()
    @State private var mapHeight: CGFloat = DesignSystem.mapDefaultHeight
```

Then replace:

```swift
                SpeciesLibraryView(mapState: mapState)
                    .padding(.top, DesignSystem.spacingMedium - DesignSystem.spacingSmall)
```

with:

```swift
                SpeciesLibraryView(mapState: mapState, regionId: regionId)
                    .padding(.top, DesignSystem.spacingMedium - DesignSystem.spacingSmall)
```

- [ ] **Step 3: Accept and forward `regionId` in `SpeciesLibraryView`**

Edit `MushroomSignal/Views/SpeciesLibraryView.swift`, replace:

```swift
struct SpeciesLibraryView: View {
    @ObservedObject var mapState: MapScreenState
    @State private var detailSpecies: Species?
```

with:

```swift
struct SpeciesLibraryView: View {
    @ObservedObject var mapState: MapScreenState
    let regionId: String
    @State private var detailSpecies: Species?
```

Then replace:

```swift
        .sheet(item: $detailSpecies) { species in
            SpeciesDetailView(species: species, photos: mapState.photosBySpeciesID[species.id] ?? [])
        }
```

with:

```swift
        .sheet(item: $detailSpecies) { species in
            SpeciesDetailView(species: species, photos: mapState.photosBySpeciesID[species.id] ?? [], regionId: regionId)
        }
```

- [ ] **Step 4: Pass `regionId` from `ShortlistView`**

Edit `MushroomSignal/Views/ShortlistView.swift`, replace:

```swift
                        } label: {
                            SpeciesCardView(species: signal.species, photo: photosBySpeciesID[signal.species.id]?.first, signal: signal, isActiveOnMap: nil)
                        }
                        .buttonStyle(.plain)
                    }
                }
```

with the same content (this step doesn't change the card-tap Button — it changes the `.sheet` below). Instead, replace:

```swift
        .sheet(item: $detailSpecies) { species in
            SpeciesDetailView(species: species, photos: photosBySpeciesID[species.id] ?? [])
        }
```

with:

```swift
        .sheet(item: $detailSpecies) { species in
            SpeciesDetailView(species: species, photos: photosBySpeciesID[species.id] ?? [], regionId: appState.selectedRegion.id)
        }
```

- [ ] **Step 5: Build (will fail — `SpeciesDetailView` doesn't accept `regionId` yet, that's Task 3)**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD FAILED **` — `extra argument 'regionId' in call`. This is expected; Task 3 adds the parameter `SpeciesDetailView` needs to accept it. Do not attempt to make this task's build pass in isolation — Tasks 2 and 3 are split for reviewability but are one compiling unit together.

- [ ] **Step 6: Commit (staged together with Task 3 — see Task 3's commit step)**

No separate commit here; continue directly to Task 3, then commit both together. (This is the one deliberate exception to "commit at the end of every task" in this plan — Task 2 alone does not compile.)

---

### Task 3: `SpeciesTrendState` + chart UI in `SpeciesDetailView`

**Files:**
- Create: `MushroomSignal/SpeciesTrendState.swift`
- Modify: `MushroomSignal/Views/SpeciesDetailView.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`
- Modify: `MushroomSignalTests/StubWeatherClient.swift`
- Create: `MushroomSignalTests/SpeciesTrendStateTests.swift`

**Interfaces:**
- Consumes: `SpeciesTrendCalculator.trend(...)` and `TrendPoint` (Task 1), `WeatherClient.fetchDailyBreakdown(for:pastDays:forecastDays:)` (weather-client-extension plan), `RegionDatabase.find(id:) -> Region?` (existing).
- Produces: `SpeciesTrendState` — no other task depends on it (leaf of this plan).

- [ ] **Step 1: Add a `trendChartHeight` design token**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`, replace:

```swift
    /// Score-dot glyph size inside a map marker — a decorative map-icon scale, matching the
    /// precedent set by `legendDotSize`. Not subject to the 20pt body-text floor, which governs
    /// readable text, not small status glyphs.
    public static let mapMarkerDotSize: Double = 6
```

with:

```swift
    /// Score-dot glyph size inside a map marker — a decorative map-icon scale, matching the
    /// precedent set by `legendDotSize`. Not subject to the 20pt body-text floor, which governs
    /// readable text, not small status glyphs.
    public static let mapMarkerDotSize: Double = 6
    /// Height of the trend/weather charts (SpeciesDetailView's score trend, Predpoveď's daily
    /// weather strip) — shared so both charts read as one visual family.
    public static let trendChartHeight: Double = 120
```

- [ ] **Step 2: Extend `StubWeatherClient` with injectable daily weather**

Read `MushroomSignalTests/StubWeatherClient.swift` (already updated by the weather-client-extension
plan to the 3-arg `fetchDailyBreakdown` signature, returning `[]` unconditionally). Replace:

```swift
actor StubWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}

    private var snapshots: [WeatherSnapshot?]
    private var callIndex = 0
    private let gridSnapshots: [String: WeatherSnapshot]
    private let gridShouldThrow: Bool

    init(snapshots: [WeatherSnapshot?], gridSnapshots: [String: WeatherSnapshot] = [:], gridShouldThrow: Bool = false) {
        self.snapshots = snapshots
        self.gridSnapshots = gridSnapshots
        self.gridShouldThrow = gridShouldThrow
    }
```

with:

```swift
actor StubWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}

    private var snapshots: [WeatherSnapshot?]
    private var callIndex = 0
    private let gridSnapshots: [String: WeatherSnapshot]
    private let gridShouldThrow: Bool
    private let dailyWeather: [DailyWeather]
    private let dailyShouldThrow: Bool

    init(snapshots: [WeatherSnapshot?], gridSnapshots: [String: WeatherSnapshot] = [:], gridShouldThrow: Bool = false, dailyWeather: [DailyWeather] = [], dailyShouldThrow: Bool = false) {
        self.snapshots = snapshots
        self.gridSnapshots = gridSnapshots
        self.gridShouldThrow = gridShouldThrow
        self.dailyWeather = dailyWeather
        self.dailyShouldThrow = dailyShouldThrow
    }
```

Then replace:

```swift
    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        []
    }
```

(the version inside `StubWeatherClient` only — leave `DelayedWeatherClient`'s copy of this
method unchanged) with:

```swift
    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        if dailyShouldThrow { throw StubError() }
        return dailyWeather
    }
```

- [ ] **Step 3: Write the failing `SpeciesTrendState` tests**

Create `MushroomSignalTests/SpeciesTrendStateTests.swift`:

```swift
import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class SpeciesTrendStateTests: XCTestCase {
    private func species() -> Species {
        Species(id: "test", commonNameSk: "Test", latinName: "Testus", edibility: .edible, fruitingMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], idealTempMinC: 0, idealTempMaxC: 40, idealHumidityMinPercent: 0, idealHumidityMaxPercent: 100, rainfallSensitivity: .low, habitat: "test", regionalAffinity: [])
    }

    func testLoadPopulatesPointsOnSuccess() async {
        let day = DailyWeather(date: .now, meanTempC: 15, maxTempC: 20, minTempC: 10, precipitationMm: 5, humidityPercent: 70)
        let client = StubWeatherClient(snapshots: [nil], dailyWeather: [day])
        let state = SpeciesTrendState(weatherClient: client)

        await state.load(species: species(), regionId: "zilinsky")

        XCTAssertEqual(state.points.count, 1)
        XCTAssertNil(state.errorMessage)
    }

    func testLoadClearsPointsAndSetsErrorOnFailure() async {
        let client = StubWeatherClient(snapshots: [nil], dailyShouldThrow: true)
        let state = SpeciesTrendState(weatherClient: client)

        await state.load(species: species(), regionId: "zilinsky")

        XCTAssertTrue(state.points.isEmpty)
        XCTAssertNotNil(state.errorMessage)
    }

    func testLoadWithUnknownRegionIdLeavesPointsEmpty() async {
        let client = StubWeatherClient(snapshots: [nil])
        let state = SpeciesTrendState(weatherClient: client)

        await state.load(species: species(), regionId: "not-a-real-region")

        XCTAssertTrue(state.points.isEmpty)
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/SpeciesTrendStateTests`
Expected: `** BUILD FAILED **` — `SpeciesTrendState` doesn't exist yet.

- [ ] **Step 5: Create `SpeciesTrendState`**

Create `MushroomSignal/SpeciesTrendState.swift`:

```swift
import Foundation
import MushroomSignalCore

@MainActor
final class SpeciesTrendState: ObservableObject {
    @Published var points: [TrendPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let weatherClient: WeatherClient

    init(weatherClient: WeatherClient = OpenMeteoClient()) {
        self.weatherClient = weatherClient
    }

    func load(species: Species, regionId: String) async {
        guard let region = RegionDatabase.find(id: regionId) else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let dailyWeather = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 10, forecastDays: 4)
            points = SpeciesTrendCalculator.trend(species: species, dailyWeather: dailyWeather, regionId: regionId)
        } catch {
            points = []
            errorMessage = "Nepodarilo sa načítať trend."
        }
    }
}
```

- [ ] **Step 6: Regenerate the Xcode project (new file) and run the tests**

Run: `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/SpeciesTrendStateTests`
Expected: `** TEST SUCCEEDED **`, all 3 tests pass.

- [ ] **Step 7: Add the `regionId` parameter and chart section to `SpeciesDetailView`**

Edit `MushroomSignal/Views/SpeciesDetailView.swift`, replace:

```swift
// MushroomSignal/Views/SpeciesDetailView.swift
import SwiftUI
import MushroomSignalCore

struct SpeciesDetailView: View {
    let species: Species
    let photos: [SpeciesPhoto]
    @Environment(\.dismiss) private var dismiss
    @State private var showingCredits = false
```

with:

```swift
// MushroomSignal/Views/SpeciesDetailView.swift
import SwiftUI
import Charts
import MushroomSignalCore

struct SpeciesDetailView: View {
    let species: Species
    let photos: [SpeciesPhoto]
    let regionId: String
    @Environment(\.dismiss) private var dismiss
    @State private var showingCredits = false
    @StateObject private var trendState = SpeciesTrendState()
```

Then replace:

```swift
                    if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                        Text(warning)
                            .font(.system(size: DesignSystem.bodySize, weight: .bold))
                            .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                    }

                    detailRow(title: "Biotop", value: species.habitat)
```

with:

```swift
                    if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                        Text(warning)
                            .font(.system(size: DesignSystem.bodySize, weight: .bold))
                            .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                    }

                    if !trendState.points.isEmpty {
                        trendChart
                    }

                    detailRow(title: "Biotop", value: species.habitat)
```

Then replace:

```swift
            .sheet(isPresented: $showingCredits) {
                PhotoCreditsView(photos: photos)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
```

with:

```swift
            .sheet(isPresented: $showingCredits) {
                PhotoCreditsView(photos: photos)
            }
        }
        .task { await trendState.load(species: species, regionId: regionId) }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text("Trend")
                .font(.system(size: DesignSystem.captionSize, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Chart(trendState.points, id: \.date) { point in
                LineMark(x: .value("Deň", point.date), y: .value("Skóre", point.score))
                    .foregroundStyle(DesignSystem.Colors.mossAccent)
                PointMark(x: .value("Deň", point.date), y: .value("Skóre", point.score))
                    .foregroundStyle(DesignSystem.Colors.mossAccent.opacity(point.isForecast ? 0.5 : 1.0))
            }
            .chartYScale(domain: 0...4)
            .frame(height: DesignSystem.trendChartHeight)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
```

- [ ] **Step 8: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **` — this also resolves Task 2's expected build failure, since `SpeciesDetailView` now accepts `regionId`.

- [ ] **Step 9: Full test suite**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 10: Manual visual check — this is the real verification for the chart**

Launch the app. Open a species detail sheet from both Zoznam and Mapa. Confirm: a "Trend" section
appears with a line/point chart, past points are solid, forecast points are lighter, the Y axis
stays readable at the 0-4 score range, and opening the sheet from either tab works (confirms the
`regionId` plumbing from Task 2 reaches both paths).

- [ ] **Step 11: Commit (Tasks 2 and 3 together — Task 2 alone did not compile)**

```bash
git add MushroomSignal/ContentView.swift MushroomSignal/Views/MapScreenView.swift MushroomSignal/Views/SpeciesLibraryView.swift MushroomSignal/Views/ShortlistView.swift MushroomSignal/Views/SpeciesDetailView.swift MushroomSignal/SpeciesTrendState.swift MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift MushroomSignalTests/StubWeatherClient.swift MushroomSignalTests/SpeciesTrendStateTests.swift MushroomSignal.xcodeproj
git commit -m "feat: show a per-species score trend chart in SpeciesDetailView"
```

---

## Final Verification

- [ ] Run `swift test --package-path MushroomSignalCore` — full pass.
- [ ] Run `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData` — full pass.
- [ ] Full signed build, launch, open species detail sheets from both Zoznam and Mapa, confirm the trend chart renders with real data in both, forecast days visually distinguished from past days.
- [ ] Update `docs/superpowers/KNOWN_ISSUES.md` with what shipped, per this project's established convention.
