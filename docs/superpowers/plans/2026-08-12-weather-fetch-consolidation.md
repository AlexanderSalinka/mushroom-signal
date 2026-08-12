# Weather Fetch Consolidation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the Predpoveď tab's 3 separate Open-Meteo network calls
(`AppState`'s `fetchSnapshot` + `fetchDailyBreakdown(pastDays:10)`, `RegionWeatherState`'s
separate `fetchDailyBreakdown(pastDays:30,forecastDays:5)`) into one, owned by `AppState`.

**Architecture:** `AppState.refresh()` makes a single `fetchDailyBreakdown(pastDays:30,
forecastDays:5)` call. A new pure function, `WeatherSnapshot.derive(...)`, replaces the
separate `fetchSnapshot` network round-trip by computing the same averages client-side
from the fetched array. `RegionWeatherState` is deleted entirely — `AppState` becomes
the single source of both signals and the daily weather array, and `PredpovedView` reads
both directly from it instead of owning a second `@StateObject`. A new `DailyWeatherCache`
(sibling to the existing `WeatherSnapshotCache`, not a merge of it) extends the stale-data
fallback to the chart/hero, matching what the shortlist already had.

**Tech Stack:** Swift, SwiftUI, `os.Logger`, `UserDefaults` (App Group) — no new
dependencies.

## Global Constraints

- Per `docs/superpowers/specs/2026-08-12-weather-fetch-consolidation-design.md`: the
  widget (`MushroomSignalWidget/`, including `ShortlistProvider`) is explicitly **out of
  scope** — it keeps calling `fetchSnapshot` + `fetchDailyBreakdown(pastDays:10)`
  unchanged. Do not touch any file under `MushroomSignalWidget/` in this plan.
- `WeatherSnapshotCache` (existing) is read by `AppState` (this plan) and by the widget's
  `ShortlistProvider` (out of scope, untouched) — it is **not** merged with the new
  `DailyWeatherCache`; they are two independent, sibling caches, each with a single
  writer (`AppState.refresh()`), written together from the same fetch so they can never
  drift out of sync with each other.
- The map's `fetchSnapshots(for points:)` batched call (`MapScreenState`) is untouched —
  a completely separate code path.
- No SwiftUI View-level unit test infrastructure in this codebase (confirmed:
  `MushroomSignalTests/` only covers `@ObservableObject` state classes, never a `View`
  struct directly). `PredpovedView`'s changes in Task 5 are verified by building and
  visually checking the running app, not new View tests.
- XcodeGen does NOT auto-detect new/removed `.swift` files in the `MushroomSignal` app
  target — run `xcodegen generate` after Task 5 deletes `RegionWeatherState.swift`
  (removing a file also requires regenerating, same as adding one). Tasks 1-4 are
  entirely within the `MushroomSignalCore` Swift Package, which auto-discovers file
  changes — no `xcodegen generate` needed for those.
- Never hand-edit `MushroomSignal.xcodeproj` directly — only `project.yml` +
  `xcodegen generate`.
- **Every `xcodebuild build`/`xcodebuild test` invocation mutates `MushroomSignal/Info.plist`
  and `MushroomSignalWidget/Info.plist`**, overwriting their version placeholders with
  hardcoded literal values — before every `git add`/`git commit` in Task 5 (the only
  task touching the Xcode app target), run
  `git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist` first if
  `git status` shows them modified.
- All new UI/data styling routes through `DesignSystem` where applicable — not directly
  relevant to this plan (no new UI is added, only data-layer changes), noted for
  completeness.

---

## Task 1: `WeatherSnapshot.derive` — client-side averaging

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/WeatherSnapshotTests.swift` (new file — no existing tests for this type today; confirmed via `ls MushroomSignalCore/Tests/MushroomSignalCoreTests/`)

**Interfaces:**
- Produces: `WeatherSnapshot.derive(regionId: String, from dailyWeather: [DailyWeather],
  windowDays: Int = 10, asOf today: Date, calendar: Calendar = .current) ->
  WeatherSnapshot?` — consumed by Task 4 (`AppState.refresh()`).

**Background (confirmed in code):** `WeatherSnapshot.swift` already has one factory
extension, `WeatherSnapshot.singleDay(regionId:day:totalPrecipitationLast10DaysMm:)`, for
the per-day trend chart. This task adds a second factory alongside it, following the same
`public extension WeatherSnapshot` pattern — not a new file, not a new type.

- [ ] **Step 1: Write the failing tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/WeatherSnapshotTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class WeatherSnapshotTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func day(_ offset: Int, meanTemp: Double, humidity: Double, precip: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(Double(offset) * 86400), meanTempC: meanTemp, maxTempC: meanTemp + 5, minTempC: meanTemp - 5, precipitationMm: precip, humidityPercent: humidity)
    }

    func testReturnsNilForEmptyArray() {
        XCTAssertNil(WeatherSnapshot.derive(regionId: "zilinsky", from: [], asOf: today))
    }

    func testAveragesExactlyTheTrailingWindowDays() {
        let days = (-9...0).map { day($0, meanTemp: 20, humidity: 70, precip: 1) }
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 10, asOf: today)
        XCTAssertEqual(snapshot?.averageTempLast10DaysC, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot?.averageHumidityLast10DaysPercent, 70, accuracy: 0.001)
        XCTAssertEqual(snapshot?.totalPrecipitationLast10DaysMm, 10, accuracy: 0.001)
        XCTAssertEqual(snapshot?.regionId, "zilinsky")
    }

    func testOnlyUsesTheMostRecentWindowDaysWhenMoreAreAvailable() {
        var days = (-19...(-10)).map { day($0, meanTemp: 0, humidity: 0, precip: 0) } // older, should be excluded
        days += (-9...0).map { day($0, meanTemp: 20, humidity: 70, precip: 1) } // most recent 10, should be used
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 10, asOf: today)
        XCTAssertEqual(snapshot?.averageTempLast10DaysC, 20, accuracy: 0.001, "older days outside the window must not pull the average down")
    }

    func testUsesFewerThanWindowDaysWhenFewerAreAvailable() {
        let days = [day(-2, meanTemp: 10, humidity: 60, precip: 3), day(-1, meanTemp: 20, humidity: 80, precip: 5), day(0, meanTemp: 30, humidity: 100, precip: 7)]
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 10, asOf: today)
        XCTAssertEqual(snapshot?.averageTempLast10DaysC, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot?.totalPrecipitationLast10DaysMm, 15, accuracy: 0.001)
    }

    func testExcludesForecastDaysFromTheAverage() {
        var days = (-9...0).map { day($0, meanTemp: 20, humidity: 70, precip: 1) }
        days += [day(1, meanTemp: 100, humidity: 100, precip: 100), day(2, meanTemp: 100, humidity: 100, precip: 100)] // forecast days, must be excluded
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 10, asOf: today)
        XCTAssertEqual(snapshot?.averageTempLast10DaysC, 20, accuracy: 0.001, "forecast (future) days must never be included in a historical average")
    }

    func testRespectsACustomWindowDaysValue() {
        var days = (-6...0).map { day($0, meanTemp: 20, humidity: 70, precip: 1) } // most recent 7
        days += (-13...(-7)).map { day($0, meanTemp: 0, humidity: 0, precip: 0) } // older, excluded at windowDays: 7
        let snapshot = WeatherSnapshot.derive(regionId: "zilinsky", from: days, windowDays: 7, asOf: today)
        XCTAssertEqual(snapshot?.averageTempLast10DaysC, 20, accuracy: 0.001)
        XCTAssertEqual(snapshot?.totalPrecipitationLast10DaysMm, 7, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --package-path MushroomSignalCore --filter WeatherSnapshotTests
```

Expected: FAIL to build — `WeatherSnapshot.derive` doesn't exist yet.

- [ ] **Step 3: Implement `WeatherSnapshot.derive`**

In `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift`, find the
existing `public extension WeatherSnapshot { ... }` block (containing `singleDay`) and add
this factory inside the same extension, after `singleDay`:

```swift
    /// Derives a WeatherSnapshot from an already-fetched daily array — replaces the old
    /// dedicated fetchSnapshot network call (see the weather-fetch-consolidation design,
    /// 2026-08-12). Averages/sums the most recent `windowDays` calendar days up to and
    /// including `asOf` (never forecast days), matching the same past-day filtering
    /// RecentWeatherWindow and WeatherRainChartView.visibleDays already use elsewhere in
    /// this codebase. Returns nil if no historical data is available.
    static func derive(regionId: String, from dailyWeather: [DailyWeather], windowDays: Int = 10, asOf today: Date, calendar: Calendar = .current) -> WeatherSnapshot? {
        let todayStart = calendar.startOfDay(for: today)
        let window = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
            .suffix(windowDays)
        guard !window.isEmpty else { return nil }

        let temps = window.map(\.meanTempC)
        let humidity = window.map(\.humidityPercent)
        let precipitation = window.map(\.precipitationMm)

        return WeatherSnapshot(
            regionId: regionId,
            averageTempLast10DaysC: temps.reduce(0, +) / Double(temps.count),
            averageHumidityLast10DaysPercent: humidity.reduce(0, +) / Double(humidity.count),
            totalPrecipitationLast10DaysMm: precipitation.reduce(0, +),
            fetchedAt: today
        )
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --package-path MushroomSignalCore --filter WeatherSnapshotTests
```

Expected: PASS, all 6 tests green.

- [ ] **Step 5: Run the full Core suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
```

Expected: all green (159 + 6 = 165).

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/WeatherSnapshotTests.swift
git commit -m "feat: add WeatherSnapshot.derive for client-side snapshot averaging"
```

---

## Task 2: `DailyWeatherCache` — sibling cache for the daily array

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/DailyWeatherCache.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DailyWeatherCacheTests.swift`

**Interfaces:**
- Consumes: `RegionStoreConstants.appGroupId` (existing, same App Group suite
  `WeatherSnapshotCache` already uses).
- Produces: `DailyWeatherCache.init?(appGroupId: String = RegionStoreConstants.appGroupId)`,
  `DailyWeatherCache.dailyWeather(for regionId: String) -> [DailyWeather]?`,
  `DailyWeatherCache.store(_ dailyWeather: [DailyWeather], for regionId: String)` —
  consumed by Task 4 (`AppState.refresh()`).

**Not a change to `WeatherSnapshotCache`** — this is a new, independent file, deliberately
mirroring `WeatherSnapshotCache.swift`'s exact structure (confirmed by reading it: a
`private let defaults: UserDefaults`, a failable `appGroupId`-based init, get/store
methods, a private `key(for:)` helper) so the two caches read identically in code review,
without one depending on or wrapping the other.

- [ ] **Step 1: Write the failing tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/DailyWeatherCacheTests.swift`,
mirroring `WeatherSnapshotCacheTests.swift`'s exact test names/structure:

```swift
import XCTest
@testable import MushroomSignalCore

final class DailyWeatherCacheTests: XCTestCase {
    private func makeCache() -> (DailyWeatherCache, String) {
        let suiteName = "test.suite.\(UUID().uuidString)"
        return (DailyWeatherCache(appGroupId: suiteName)!, suiteName)
    }

    private func sampleDay(temp: Double) -> DailyWeather {
        DailyWeather(date: .now, meanTempC: temp, maxTempC: temp + 5, minTempC: temp - 5, precipitationMm: 2, humidityPercent: 65)
    }

    func testReturnsNilWhenNothingCachedForRegion() {
        let (cache, suiteName) = makeCache()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertNil(cache.dailyWeather(for: "zilinsky"))
    }

    func testStoreThenRetrieveRoundTripsTheArray() {
        let (cache, suiteName) = makeCache()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let days = [sampleDay(temp: 15), sampleDay(temp: 20)]

        cache.store(days, for: "zilinsky")

        XCTAssertEqual(cache.dailyWeather(for: "zilinsky"), days)
    }

    func testNewerStoreForSameRegionOverwritesOlder() {
        let (cache, suiteName) = makeCache()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        cache.store([sampleDay(temp: 10)], for: "zilinsky")
        cache.store([sampleDay(temp: 25)], for: "zilinsky")

        XCTAssertEqual(cache.dailyWeather(for: "zilinsky")?.first?.meanTempC, 25)
    }

    func testCachesPerRegionIndependently() {
        let (cache, suiteName) = makeCache()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        cache.store([sampleDay(temp: 10)], for: "zilinsky")
        cache.store([sampleDay(temp: 30)], for: "kosicky")

        XCTAssertEqual(cache.dailyWeather(for: "zilinsky")?.first?.meanTempC, 10)
        XCTAssertEqual(cache.dailyWeather(for: "kosicky")?.first?.meanTempC, 30)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --package-path MushroomSignalCore --filter DailyWeatherCacheTests
```

Expected: FAIL to build — `DailyWeatherCache` doesn't exist yet.

- [ ] **Step 3: Implement `DailyWeatherCache`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Weather/DailyWeatherCache.swift`:

```swift
import Foundation

/// Persists the last successful daily weather array per region — the array-shaped
/// counterpart to WeatherSnapshotCache, added so the chart/hero can fall back to stale
/// data the same way the shortlist already does via WeatherSnapshotCache. Deliberately a
/// separate cache, not a merged one: WeatherSnapshotCache is also read by the widget
/// (ShortlistProvider), which doesn't need the daily array — extending
/// WeatherSnapshotCache's shape would be a wider, riskier change for no benefit to that
/// consumer. Same App Group UserDefaults suite, same get/store/key pattern.
public struct DailyWeatherCache {
    private let defaults: UserDefaults

    public init?(appGroupId: String = RegionStoreConstants.appGroupId) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        self.defaults = defaults
    }

    public func dailyWeather(for regionId: String) -> [DailyWeather]? {
        guard let data = defaults.data(forKey: key(for: regionId)) else { return nil }
        return try? JSONDecoder().decode([DailyWeather].self, from: data)
    }

    public func store(_ dailyWeather: [DailyWeather], for regionId: String) {
        guard let data = try? JSONEncoder().encode(dailyWeather) else { return }
        defaults.set(data, forKey: key(for: regionId))
    }

    private func key(for regionId: String) -> String {
        "dailyWeatherCache.\(regionId)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --package-path MushroomSignalCore --filter DailyWeatherCacheTests
```

Expected: PASS, all 4 tests green.

- [ ] **Step 5: Run the full Core suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
```

Expected: all green (165 + 4 = 169).

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Weather/DailyWeatherCache.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/DailyWeatherCacheTests.swift
git commit -m "feat: add DailyWeatherCache for the daily-array stale-fallback"
```

---

## Task 3: Test-stub support for sequenced `fetchDailyBreakdown` calls

**Files:**
- Modify: `MushroomSignalTests/StubWeatherClient.swift`

**Interfaces:**
- Produces: `StubWeatherClient.init(dailyWeatherSequence: [[DailyWeather]?], ...)` — a new
  initializer parameter, consumed by Task 4's rewritten `AppStateTests.swift`.
  `DelayedWeatherClient`'s success/failure/delay behavior moves from `fetchSnapshot` to
  `fetchDailyBreakdown` — consumed by the same task.

**Why this is needed (confirmed in code):** `StubWeatherClient.fetchSnapshot` already
supports a per-call sequence via `snapshots: [WeatherSnapshot?]` + an internal
`callIndex` (first call returns `snapshots[0]`, second call `snapshots[1]`, etc. — used by
`AppStateTests.testRefreshFallsBackToCachedWeatherOnFailureAfterASuccessfulLoad` to make
the *first* `refresh()` succeed and the *second* fail). `fetchDailyBreakdown` has no such
sequencing today — it always returns the same fixed `dailyWeather` array or always throws,
based on a single fixed `dailyShouldThrow` boolean. Once `AppState.refresh()` stops
calling `fetchSnapshot` at all (Task 4), every test that needs "succeeds then fails"
behavior needs that sequencing on `fetchDailyBreakdown` instead — the old `fetchSnapshot`
sequencing becomes irrelevant to `AppState.refresh()`'s behavior, but should NOT be
deleted, since `RegionWeatherState`'s test file (deleted in Task 5, not this one) still
runs until then, and other current callers of `StubWeatherClient` may still exist by name
even if unused post-refactor — this task only *adds* the new capability, it does not
remove the old `snapshots:` parameter or its behavior.

- [ ] **Step 1: Add `dailyWeatherSequence` to `StubWeatherClient`**

In `MushroomSignalTests/StubWeatherClient.swift`, find the current `StubWeatherClient`
actor:

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

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        let index = min(callIndex, snapshots.count - 1)
        callIndex += 1
        guard let snapshot = snapshots[index] else { throw StubError() }
        return snapshot
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        if gridShouldThrow { throw StubError() }
        return gridSnapshots
    }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        if dailyShouldThrow { throw StubError() }
        return dailyWeather
    }
}
```

Replace it with (adds `dailyWeatherSequence`/`dailyCallIndex`, keeps every existing
parameter and behavior unchanged — `dailyWeather`/`dailyShouldThrow` still work exactly
as before for any test that doesn't pass the new parameter, since `dailyWeatherSequence`
defaults to `nil` and the old fixed-array/throw-flag path is used whenever it's absent):

```swift
actor StubWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}

    private var snapshots: [WeatherSnapshot?]
    private var callIndex = 0
    private let gridSnapshots: [String: WeatherSnapshot]
    private let gridShouldThrow: Bool
    private let dailyWeather: [DailyWeather]
    private let dailyShouldThrow: Bool
    private var dailyWeatherSequence: [[DailyWeather]?]?
    private var dailyCallIndex = 0

    init(snapshots: [WeatherSnapshot?], gridSnapshots: [String: WeatherSnapshot] = [:], gridShouldThrow: Bool = false, dailyWeather: [DailyWeather] = [], dailyShouldThrow: Bool = false, dailyWeatherSequence: [[DailyWeather]?]? = nil) {
        self.snapshots = snapshots
        self.gridSnapshots = gridSnapshots
        self.gridShouldThrow = gridShouldThrow
        self.dailyWeather = dailyWeather
        self.dailyShouldThrow = dailyShouldThrow
        self.dailyWeatherSequence = dailyWeatherSequence
    }

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        let index = min(callIndex, snapshots.count - 1)
        callIndex += 1
        guard let snapshot = snapshots[index] else { throw StubError() }
        return snapshot
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        if gridShouldThrow { throw StubError() }
        return gridSnapshots
    }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        if let sequence = dailyWeatherSequence {
            let index = min(dailyCallIndex, sequence.count - 1)
            dailyCallIndex += 1
            guard let result = sequence[index] else { throw StubError() }
            return result
        }
        if dailyShouldThrow { throw StubError() }
        return dailyWeather
    }
}
```

- [ ] **Step 2: Move `DelayedWeatherClient`'s delay/throw behavior to `fetchDailyBreakdown`**

In the same file, find `DelayedWeatherClient`:

```swift
actor DelayedWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}
    private var callCount = 0

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(200))
            throw StubError()
        }
        return WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        [:]
    }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        []
    }
}
```

Replace with (the "first call is slow and fails, second call succeeds immediately"
behavior moves to `fetchDailyBreakdown`, since that's what `AppState.refresh()` now
actually calls; `fetchSnapshot` becomes a trivial always-throw since nothing should call
it anymore after Task 4 — kept only because the type must still conform to the
`WeatherClient` protocol):

```swift
actor DelayedWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}
    private var callCount = 0

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        throw StubError()
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        [:]
    }

    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(200))
            throw StubError()
        }
        return [DailyWeather(date: .now, meanTempC: 15, maxTempC: 20, minTempC: 10, precipitationMm: 2, humidityPercent: 75)]
    }
}
```

- [ ] **Step 3: Build the test target to confirm it compiles**

```bash
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: builds and runs (existing tests that use these stubs may now behave
differently — that's expected and is exactly what Task 4 will fix; a compile failure
here would mean a syntax error in this task's edit, which is what this step checks for,
not full behavioral correctness yet).

- [ ] **Step 4: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignalTests/StubWeatherClient.swift
git commit -m "test: add sequenced fetchDailyBreakdown support to StubWeatherClient"
```

---

## Task 4: `AppState.refresh()` — single fetch, derived snapshot, dual cache

**Files:**
- Modify: `MushroomSignal/AppState.swift`
- Modify: `MushroomSignalTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `WeatherSnapshot.derive(regionId:from:windowDays:asOf:calendar:)` (Task 1),
  `DailyWeatherCache.dailyWeather(for:)`/`.store(_:for:)` (Task 2),
  `StubWeatherClient(dailyWeatherSequence:)`/`DelayedWeatherClient` (Task 3).
- Produces: `AppState.dailyWeather: [DailyWeather]` (new `@Published` property) —
  consumed by Task 5 (`PredpovedView`).

**Empirical verification required before deleting `fetchSnapshot`'s call site** (per the
design spec's explicit uncertainty flag — do this first, before touching
`AppState.swift`):

- [ ] **Step 1: Verify `WeatherSnapshot.derive` matches the old `fetchSnapshot`'s real values**

Create a throwaway script (anywhere outside the repo, e.g. your scratch directory — this
step produces no committed code) that: constructs a real `OpenMeteoClient()`, calls
`fetchSnapshot(for:)` for one real region (e.g. `RegionDatabase.all[4]`, Žilinský), then
separately calls `fetchDailyBreakdown(for:pastDays:30,forecastDays:5)` for the same
region and feeds the result into `WeatherSnapshot.derive(regionId:from:asOf: Date())`.
Print both snapshots' three numeric fields side by side. Confirm they match within ~1°C /
~2% humidity / ~1mm precipitation (small differences are expected and acceptable — the
old endpoint used `past_days=10, forecast_days=1` while `derive`'s default `windowDays:
10` uses "the most recent 10 calendar days up to and including today," a slightly
different but equally valid window definition per the design spec). If the values
diverge by more than that, STOP and report the actual numbers — do not proceed to Step 2
on an unverified assumption.

- [ ] **Step 2: Rewrite `AppState.refresh()`**

In `MushroomSignal/AppState.swift`, add two new stored properties alongside the existing
ones (`weatherCache`, etc.):

```swift
    private let weatherCache: WeatherSnapshotCache?
    private let dailyWeatherCache: DailyWeatherCache?
```

Update `init(...)` to accept and store it, mirroring the existing `weatherCache`
parameter exactly:

```swift
    init(
        store: RegionStore? = RegionStore(),
        weatherCache: WeatherSnapshotCache? = WeatherSnapshotCache(),
        dailyWeatherCache: DailyWeatherCache? = DailyWeatherCache(),
        weatherClient: WeatherClient = OpenMeteoClient(),
        widgetReloader: WidgetReloading = SystemWidgetCenter(),
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.weatherCache = weatherCache
        self.dailyWeatherCache = dailyWeatherCache
        self.weatherClient = weatherClient
        self.widgetReloader = widgetReloader
        self.now = now
        self.selectedRegion = store?.selectedRegion() ?? RegionDatabase.all[0]
        if store == nil {
            logger.error("RegionStore init failed — region selection will not persist across launches or sync to the widget")
        }
    }
```

Add the new published property near the existing `@Published var signals`:

```swift
    @Published var signals: [SpeciesSignal] = []
    @Published var dailyWeather: [DailyWeather] = []
```

Replace `refresh()`'s entire body with:

```swift
    func refresh() async {
        let refreshID = UUID()
        currentRefreshID = refreshID
        isLoading = true
        errorMessage = nil
        defer {
            if currentRefreshID == refreshID {
                isLoading = false
            }
        }

        let region = selectedRegion
        do {
            let daily = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 30, forecastDays: 5)
            guard let weather = WeatherSnapshot.derive(regionId: region.id, from: daily, asOf: now()) else {
                throw WeatherClientError.emptyDailyData
            }
            weatherCache?.store(weather)
            dailyWeatherCache?.store(daily, for: region.id)
            let flushTriggered = FlushTriggerDetector.triggered(in: daily, asOf: now())
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: now())
            let ranked = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: weather, month: month, flushTriggered: flushTriggered)
            guard currentRefreshID == refreshID else { return }
            signals = ranked
            dailyWeather = daily
            isShowingStaleData = false
        } catch {
            guard currentRefreshID == refreshID else { return }
            if let cachedSnapshot = weatherCache?.snapshot(for: region.id),
               let cachedDaily = dailyWeatherCache?.dailyWeather(for: region.id),
               let allSpecies = try? SpeciesDatabase.loadAll() {
                let month = Calendar.current.component(.month, from: now())
                signals = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: cachedSnapshot, month: month, flushTriggered: false)
                dailyWeather = cachedDaily
                isShowingStaleData = true
                errorMessage = "Zobrazujú sa staršie údaje z \(Self.staleTimeFormatter.string(from: cachedSnapshot.fetchedAt))."
            } else {
                signals = []
                dailyWeather = []
                isShowingStaleData = false
                errorMessage = "Nepodarilo sa načítať údaje o počasí. Skúste to znova."
            }
            logger.error("Refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
```

Note: the two caches are only used together — if either is missing on a failure, the
hard-failure branch runs (deliberate, see the design spec's "Deliberate behavior note").

- [ ] **Step 3: Rewrite the two fallback-related `AppStateTests`**

In `MushroomSignalTests/AppStateTests.swift`, replace
`testRefreshFallsBackToCachedWeatherOnFailureAfterASuccessfulLoad`:

```swift
    func testRefreshFallsBackToCachedWeatherOnFailureAfterASuccessfulLoad() async {
        let region = RegionDatabase.all[0]
        let day = DailyWeather(date: .now, meanTempC: 15, maxTempC: 20, minTempC: 10, precipitationMm: 5, humidityPercent: 75)
        let client = StubWeatherClient(snapshots: [nil], dailyWeatherSequence: [[day], nil])
        let suiteName = "test.suite.\(UUID().uuidString)"
        let weatherCache = WeatherSnapshotCache(appGroupId: suiteName)!
        let dailyCache = DailyWeatherCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let appState = AppState(store: nil, weatherCache: weatherCache, dailyWeatherCache: dailyCache, weatherClient: client)

        await appState.refresh()
        XCTAssertFalse(appState.signals.isEmpty, "precondition: first refresh should have loaded signals")

        await appState.refresh()

        XCTAssertFalse(appState.signals.isEmpty, "a failed refresh must fall back to the cached snapshot instead of blanking the list")
        XCTAssertFalse(appState.dailyWeather.isEmpty, "the daily array must also fall back to its cache, not just signals")
        XCTAssertTrue(appState.isShowingStaleData, "the fallback must be flagged as stale so the UI can indicate it, not present it as fresh")
        XCTAssertNotNil(appState.errorMessage)
    }
```

Replace `testRefreshClearsSignalsOnFailureWhenNoCachedSnapshotExists`:

```swift
    func testRefreshClearsSignalsOnFailureWhenNoCachedSnapshotExists() async {
        let client = StubWeatherClient(snapshots: [nil], dailyWeatherSequence: [nil])
        let suiteName = "test.suite.\(UUID().uuidString)"
        let weatherCache = WeatherSnapshotCache(appGroupId: suiteName)!
        let dailyCache = DailyWeatherCache(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let appState = AppState(store: nil, weatherCache: weatherCache, dailyWeatherCache: dailyCache, weatherClient: client)

        await appState.refresh()

        XCTAssertTrue(appState.signals.isEmpty, "with nothing cached yet, a failed refresh has nothing to fall back to")
        XCTAssertTrue(appState.dailyWeather.isEmpty)
        XCTAssertFalse(appState.isShowingStaleData)
        XCTAssertNotNil(appState.errorMessage)
    }
```

`testOverlappingRefreshesApplyLastStartedWinsOrdering` and
`testSelectRegionReloadsWidgetTimelines` need no code change — the first already uses
`DelayedWeatherClient` (Task 3 already moved its behavior to the method `AppState` now
actually calls), the second only asserts on the widget-reload count, not on refresh
success/failure.

- [ ] **Step 4: Verify `testRefreshAppliesFlushTriggerFromDailyBreakdown` still passes as-is**

This test's local `TriggeringWeatherClient` struct's `fetchSnapshot` implementation is
now dead code (never called), but the test doesn't need editing — it only asserts that a
specific reason string appears in `appState.signals`, and its `fetchDailyBreakdown` fixture
(one day, 3 days before `referenceDate`, `meanTempC: 22, maxTempC: 27, minTempC: 17,
precipitationMm: 5, humidityPercent: 70`) now drives BOTH `WeatherSnapshot.derive`'s
averaging (a single-day array, so the derived snapshot is exactly that one day's values:
`averageTempLast10DaysC: 22, averageHumidityLast10DaysPercent: 70,
totalPrecipitationLast10DaysMm: 5`) and `FlushTriggerDetector.triggered`, instead of the
old hardcoded `fetchSnapshot` return value (`16/75/1`). Run this specific test after Step
2's changes and confirm it still passes:

```bash
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/AppStateTests/testRefreshAppliesFlushTriggerFromDailyBreakdown
```

Expected: PASS. If it fails, the derived snapshot's temp(22)/humidity(70) values are
landing outside some in-season species' ideal ranges where the old hardcoded 16/75 values
didn't — in that case, adjust the fixture day's `meanTempC`/`humidityPercent` values (not
the assertion) to a combination that keeps at least one high/medium-rainfall-sensitivity
in-season species scoring with both `tempScore > 0` and `humidityScore > 0`, matching the
original test's intent.

- [ ] **Step 5: Build and run the full test suite**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: build succeeds, Core suite green (169), app suite green (24, same count — no
tests added or removed, only rewritten).

- [ ] **Step 6: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignal/AppState.swift MushroomSignalTests/AppStateTests.swift
git commit -m "feat: consolidate AppState.refresh() to a single weather fetch"
```

---

## Task 5: Delete `RegionWeatherState`, wire `PredpovedView` to `AppState`

**Files:**
- Delete: `MushroomSignal/RegionWeatherState.swift`
- Delete: `MushroomSignalTests/RegionWeatherStateTests.swift`
- Modify: `MushroomSignal/Views/PredpovedView.swift`

**Interfaces:**
- Consumes: `AppState.dailyWeather: [DailyWeather]` (Task 4), `AppState.isLoading:
  Bool`/`AppState.errorMessage: String?` (existing).
- Produces: no new interface — `PredpovedView`'s own public surface (`regionId:`,
  `appState:`) is unchanged; only its internals change.

- [ ] **Step 1: Delete `RegionWeatherState.swift` and its test file**

```bash
rm MushroomSignal/RegionWeatherState.swift
rm MushroomSignalTests/RegionWeatherStateTests.swift
```

- [ ] **Step 2: Remove `PredpovedView`'s `@StateObject` and region-watching `.task`**

In `MushroomSignal/Views/PredpovedView.swift`, find:

```swift
struct PredpovedView: View {
    let regionId: String
    @ObservedObject var appState: AppState
    @StateObject private var weatherState = RegionWeatherState()
    @State private var allSpecies: [Species] = []
```

Change to:

```swift
struct PredpovedView: View {
    let regionId: String
    @ObservedObject var appState: AppState
    @State private var allSpecies: [Species] = []
```

Find and delete the region-watching `.task`:

```swift
        .task(id: regionId) {
            await weatherState.load(regionId: regionId)
        }
```

Region changes already trigger `AppState.refresh()` via `selectRegion(_:)` — no
replacement trigger is needed here.

- [ ] **Step 3: Replace every `weatherState.*` reference with `appState.*`**

Find and update `todayEntry`:

```swift
    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return weatherState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }
```

becomes:

```swift
    private var todayEntry: DailyWeather? {
        let calendar = Calendar.current
        return appState.dailyWeather.first { calendar.isDateInToday($0.date) }
    }
```

Find the two error banners in `body`:

```swift
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
```

Delete the second block entirely — only `appState.errorMessage` remains (both banners
were reporting the same underlying fetch, now genuinely one fetch):

```swift
                if let error = appState.errorMessage {
                    Text(error)
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(appState.isShowingStaleData ? DesignSystem.Colors.caution : DesignSystem.Colors.danger)
                }
```

Find the chart call site:

```swift
                ForestPanel { WeatherRainChartView(dailyWeather: weatherState.dailyWeather, today: Date()) }
```

becomes:

```swift
                ForestPanel { WeatherRainChartView(dailyWeather: appState.dailyWeather, today: Date()) }
```

Find the hero's loading/error gate:

```swift
                ForestPanel {
                    if weatherState.isLoading && weatherState.dailyWeather.isEmpty {
                        Text("Načítavam predpoveď…")
                            .font(.system(size: DesignSystem.bodySize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                    } else if weatherState.errorMessage != nil {
                        Text("Predpoveď nie je k dispozícii.")
                            .font(.system(size: DesignSystem.bodySize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                    } else {
                        MushroomSignalHeroView(signals: appState.signals, dailyWeather: weatherState.dailyWeather, region: region, today: Date())
                    }
                }
```

becomes:

```swift
                ForestPanel {
                    if appState.isLoading && appState.dailyWeather.isEmpty {
                        Text("Načítavam predpoveď…")
                            .font(.system(size: DesignSystem.bodySize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                    } else if appState.errorMessage != nil && !appState.isShowingStaleData {
                        Text("Predpoveď nie je k dispozícii.")
                            .font(.system(size: DesignSystem.bodySize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                    } else {
                        MushroomSignalHeroView(signals: appState.signals, dailyWeather: appState.dailyWeather, region: region, today: Date())
                    }
                }
```

Note the added `&& !appState.isShowingStaleData` on the error branch — `appState.errorMessage`
is now also set on a *stale-fallback* (non-hard-failure) path, which still has real
`dailyWeather`/`signals` to show; without this guard the hero would show "unavailable"
even when a stale-but-present fallback succeeded. This is a real behavior difference from
the old `weatherState.errorMessage` (which was only ever set on a hard failure with
nothing to show), not a copy-paste — reasoned about explicitly here, not assumed.

Find `heroSection`'s loading/no-data branches:

```swift
            } else if weatherState.isLoading {
                Text("Načítavam počasie…")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else if weatherState.errorMessage == nil {
                Text("Žiadne údaje o počasí pre dnešný deň.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
```

becomes:

```swift
            } else if appState.isLoading {
                Text("Načítavam počasie…")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            } else if appState.errorMessage == nil {
                Text("Žiadne údaje o počasí pre dnešný deň.")
                    .font(.system(size: DesignSystem.bodySize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            }
```

No other logic change here — this section only branches on `isLoading`/whether an error
exists at all, not on the stale-vs-hard-failure distinction the hero panel's gate needed.

- [ ] **Step 4: Regenerate the Xcode project and build**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
```

Fix any compile errors before proceeding — in particular, confirm no other file still
references `RegionWeatherState` or `weatherState` (the deleted `@StateObject`'s name).

- [ ] **Step 5: Visually verify the running app**

```bash
pkill -f "MushroomSignal.app" 2>/dev/null
open DerivedData/Build/Products/Debug/MushroomSignal.app
```

Navigate to Predpoveď. Take a screenshot and confirm, by actually looking at it:
1. The chart, hero panel, and top temp readout all still render real data (not blank).
2. Only ONE error banner area exists in the layout (not two stacked ones as before).
3. Switch regions in the toolbar picker — confirm the whole tab refreshes with the new
   region's data (this now goes through `AppState.refresh()`'s single fetch, not a
   separate `RegionWeatherState.load` — confirm it still actually updates).

- [ ] **Step 6: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: Core suite green (169, unchanged from Task 4), app suite green at 18 (24 minus
the 6 tests `RegionWeatherStateTests.swift` contained, all now meaningless since the type
no longer exists).

- [ ] **Step 7: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignal/RegionWeatherState.swift MushroomSignalTests/RegionWeatherStateTests.swift MushroomSignal/Views/PredpovedView.swift project.yml MushroomSignal.xcodeproj
git commit -m "feat: delete RegionWeatherState, wire PredpovedView to AppState directly"
```
