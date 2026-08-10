# Proactive Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alert the user via a local macOS notification when a chosen species' score crosses a chosen threshold in a chosen region, checked on the widget's periodic background refresh — without the app needing to be open.

**Architecture:** A new App-Group-scoped `NotificationPreferences` store (mirroring `WeatherSnapshotCache`'s pattern) persists watched `(species, region, threshold, lastKnownScore)` tuples. A pure `WatchedAlertEvaluator` fetches current weather per distinct watched region and scores each alert via the existing `SignalPipeline`. The widget's `ShortlistProvider.getTimeline` — the only code in this repo that runs periodically without the app open — calls the evaluator and posts via `UNUserNotificationCenter` before completing its timeline. A new settings sheet, opened from a `ContentView` toolbar button, lets the user manage watches.

**Tech Stack:** Swift, Foundation, `UserNotifications`, SwiftUI, XCTest, App Group `UserDefaults`.

**Depends on:** nothing — fully independent of the weather-client-extension and trend-sparkline plans.

**Build order note:** this plan, `2026-08-10-species-trend-sparkline.md`, and `2026-08-10-predpoved-tab.md` all edit `MushroomSignal/ContentView.swift`. This plan's edit (Task 4 Step 6) doesn't overlap textually with the trend-sparkline plan's edit, so order relative to that plan doesn't matter — but the Predpoveď-tab plan's `ContentView.swift` edit is written assuming this plan and the trend-sparkline plan have both already landed. Recommended overall order: weather-client-extension → species-trend-sparkline → this plan → predpoved-tab.

## Global Constraints

- All new UI styling routes through `DesignSystem` — no hardcoded colors/sizes/spacing.
- No changes to `SignalAlgorithm`, `SignalPipeline`, or scoring weights — this plan only adds new call sites of the existing `SignalPipeline.rankedSignals`.
- No new entitlements needed — confirmed by direct inspection of both `.entitlements` files and `project.yml`: local notifications via `UNUserNotificationCenter` need only runtime `requestAuthorization` from the host app on macOS, no capability/entitlement declaration, and the widget extension can post using authorization already granted to the host app.
- A notification-posting failure must never regress the widget's primary shortlist display — always isolate failures so `completion(timeline)` still fires with a valid entry.
- Threshold scale is `1...4` (current score range is 0-4, not the old shelved spec's stale 0-3).
- `xcodegen generate` is required before any Xcode build once new files exist under `MushroomSignal/`/`MushroomSignalWidget/`.
- Always pass `-derivedDataPath DerivedData` to every `xcodebuild` invocation.

---

### Task 1: `WatchedAlert`, `NotificationPreferences`, `NotificationThreshold`

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Notifications/WatchedAlert.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Notifications/NotificationPreferences.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Notifications/NotificationThreshold.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/WatchedAlertTests.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/NotificationPreferencesTests.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/NotificationThresholdTests.swift`

**Interfaces:**
- Consumes: `RegionStoreConstants.appGroupId: String` (existing, public static var — the same App-Group-resolution logic `RegionStore`/`WeatherSnapshotCache` already use).
- Produces: `WatchedAlert { id, speciesId, regionId, threshold, lastKnownScore }` (Codable, Identifiable), `NotificationPreferences.watchedAlerts() -> [WatchedAlert]` / `.setWatchedAlerts(_:)`, `NotificationThreshold.shouldNotify(previousScore:newScore:threshold:) -> Bool`. Tasks 2-4 all consume `WatchedAlert`; Task 2 consumes `NotificationThreshold`; Task 4 consumes `NotificationPreferences` directly.

- [ ] **Step 1: Write the failing `WatchedAlert` and `NotificationThreshold` tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/WatchedAlertTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class WatchedAlertTests: XCTestCase {
    func testIdCombinesSpeciesAndRegion() {
        let alert = WatchedAlert(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)
        XCTAssertEqual(alert.id, "boletus-edulis|zilinsky")
    }

    func testRoundTripsThroughJSON() throws {
        let alert = WatchedAlert(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3, lastKnownScore: 2)
        let data = try JSONEncoder().encode(alert)
        let decoded = try JSONDecoder().decode(WatchedAlert.self, from: data)
        XCTAssertEqual(decoded, alert)
    }
}
```

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/NotificationThresholdTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class NotificationThresholdTests: XCTestCase {
    func testCrossesUpwardReturnsTrue() {
        XCTAssertTrue(NotificationThreshold.shouldNotify(previousScore: 2, newScore: 3, threshold: 3))
    }

    func testStaysAboveReturnsFalse() {
        XCTAssertFalse(NotificationThreshold.shouldNotify(previousScore: 3, newScore: 4, threshold: 3), "already notified once at/above threshold — don't repeat every refresh")
    }

    func testDropsThenRisesReturnsTrue() {
        XCTAssertTrue(NotificationThreshold.shouldNotify(previousScore: 1, newScore: 3, threshold: 3))
    }

    func testStaysBelowReturnsFalse() {
        XCTAssertFalse(NotificationThreshold.shouldNotify(previousScore: 1, newScore: 2, threshold: 3))
    }

    func testNilBaselineReturnsFalse() {
        XCTAssertFalse(NotificationThreshold.shouldNotify(previousScore: nil, newScore: 4, threshold: 3), "first-ever observation establishes a silent baseline, doesn't notify immediately")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter WatchedAlertTests`
Run: `swift test --package-path MushroomSignalCore --filter NotificationThresholdTests`
Expected: both FAIL to compile — neither type exists yet.

- [ ] **Step 3: Create `WatchedAlert`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Notifications/WatchedAlert.swift`:

```swift
import Foundation

/// A user's request to be notified when `speciesId`'s score crosses `threshold` in `regionId`.
/// `lastKnownScore` is the score observed on the most recent check — used by
/// `NotificationThreshold` to detect an upward crossing rather than re-notifying every refresh.
public struct WatchedAlert: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(speciesId)|\(regionId)" }
    public let speciesId: String
    public let regionId: String
    public let threshold: Int
    public var lastKnownScore: Int?

    public init(speciesId: String, regionId: String, threshold: Int, lastKnownScore: Int? = nil) {
        self.speciesId = speciesId
        self.regionId = regionId
        self.threshold = threshold
        self.lastKnownScore = lastKnownScore
    }
}
```

- [ ] **Step 4: Create `NotificationThreshold`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Notifications/NotificationThreshold.swift`:

```swift
import Foundation

public enum NotificationThreshold {
    /// True only on an upward crossing (previous score below threshold, new score at/above
    /// it) — never fires on a refresh where the score was already at/above threshold, and
    /// never fires on the first-ever observation (nil previous score), which instead
    /// establishes a silent baseline.
    public static func shouldNotify(previousScore: Int?, newScore: Int, threshold: Int) -> Bool {
        guard let previousScore else { return false }
        return previousScore < threshold && newScore >= threshold
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter WatchedAlertTests`
Run: `swift test --package-path MushroomSignalCore --filter NotificationThresholdTests`
Expected: both PASS.

- [ ] **Step 6: Write the failing `NotificationPreferences` tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/NotificationPreferencesTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class NotificationPreferencesTests: XCTestCase {
    func testReturnsEmptyWhenNothingStored() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let prefs = NotificationPreferences(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(prefs.watchedAlerts().isEmpty)
    }

    func testStoreThenRetrieveRoundTripsAlerts() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let prefs = NotificationPreferences(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let alert = WatchedAlert(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)
        prefs.setWatchedAlerts([alert])

        XCTAssertEqual(prefs.watchedAlerts(), [alert])
    }

    func testSetWatchedAlertsFullyReplacesPreviousValue() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let prefs = NotificationPreferences(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        prefs.setWatchedAlerts([WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 2)])
        prefs.setWatchedAlerts([WatchedAlert(speciesId: "b", regionId: "kosicky", threshold: 4)])

        XCTAssertEqual(prefs.watchedAlerts().map(\.speciesId), ["b"])
    }
}
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `swift test --package-path MushroomSignalCore --filter NotificationPreferencesTests`
Expected: FAIL to compile — `NotificationPreferences` doesn't exist yet.

- [ ] **Step 8: Create `NotificationPreferences`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Notifications/NotificationPreferences.swift`:

```swift
import Foundation

/// Persists watched-species alerts, App-Group-scoped so the widget (which performs the actual
/// threshold checks) and the app (where alerts are configured) always see the same list.
/// Mirrors `WeatherSnapshotCache`'s pattern — JSON round-trip via Data, not a primitive-value
/// store, since this persists a structured, Codable array.
public struct NotificationPreferences {
    private let defaults: UserDefaults
    private static let key = "notificationPreferences.watchedAlerts"

    public init?(appGroupId: String = RegionStoreConstants.appGroupId) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        self.defaults = defaults
    }

    public func watchedAlerts() -> [WatchedAlert] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([WatchedAlert].self, from: data)) ?? []
    }

    /// Full replace — the caller is responsible for merging with the existing list first if
    /// it wants to upsert rather than overwrite.
    public func setWatchedAlerts(_ alerts: [WatchedAlert]) {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter NotificationPreferencesTests`
Expected: PASS.

- [ ] **Step 10: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS, no regressions.

- [ ] **Step 11: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Notifications/ MushroomSignalCore/Tests/MushroomSignalCoreTests/WatchedAlertTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/NotificationPreferencesTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/NotificationThresholdTests.swift
git commit -m "feat: add WatchedAlert, NotificationPreferences, NotificationThreshold"
```

---

### Task 2: `WatchedAlertEvaluator`

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Notifications/WatchedAlertEvaluator.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/WatchedAlertEvaluatorTests.swift`

**Interfaces:**
- Consumes: `WatchedAlert` (Task 1), `NotificationThreshold.shouldNotify` (Task 1), `SignalPipeline.rankedSignals(species:region:weather:month:flushTriggered:limit:) -> [SpeciesSignal]` (existing, region-aware overload — filters by `regionalAffinity` before scoring), `WeatherClient.fetchSnapshots(for:) -> [String: WeatherSnapshot]` (existing, batched) keyed by `GridPoint.id`, `RegionDatabase.find(id:) -> Region?` (existing).
- Produces: `WatchedAlertUpdate { alert: WatchedAlert, newScore: Int, shouldNotify: Bool }` and `WatchedAlertEvaluator.evaluate(alerts:species:weatherClient:month:) async -> [WatchedAlertUpdate]`. Task 3 (widget hook) consumes both directly.

- [ ] **Step 1: Write the failing tests**

Create `MushroomSignalCore/Tests/MushroomSignalCoreTests/WatchedAlertEvaluatorTests.swift`:

```swift
import XCTest
@testable import MushroomSignalCore

final class WatchedAlertEvaluatorTests: XCTestCase {
    private struct StubClient: WeatherClient {
        struct StubError: Error, Sendable {}
        let snapshots: [String: WeatherSnapshot]

        func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
            guard let snapshot = snapshots[region.id] else { throw StubError() }
            return snapshot
        }
        func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] { snapshots }
        func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] { [] }
    }

    private func species(id: String, regionalAffinity: Set<String> = ["zilinsky", "kosicky"]) -> Species {
        Species(id: id, commonNameSk: id, latinName: id, edibility: .edible, fruitingMonths: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12], idealTempMinC: 0, idealTempMaxC: 40, idealHumidityMinPercent: 0, idealHumidityMaxPercent: 100, rainfallSensitivity: .low, habitat: "test", regionalAffinity: regionalAffinity)
    }

    private func snapshot(regionId: String) -> WeatherSnapshot {
        WeatherSnapshot(regionId: regionId, averageTempLast10DaysC: 20, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 15, fetchedAt: .now)
    }

    func testFetchesWeatherOncePerDistinctRegionNotPerAlert() async {
        let alerts = [
            WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 2),
            WatchedAlert(speciesId: "b", regionId: "zilinsky", threshold: 2),
            WatchedAlert(speciesId: "c", regionId: "kosicky", threshold: 2)
        ]
        let client = StubClient(snapshots: ["zilinsky": snapshot(regionId: "zilinsky"), "kosicky": snapshot(regionId: "kosicky")])
        let allSpecies = [species(id: "a"), species(id: "b"), species(id: "c")]

        let updates = await WatchedAlertEvaluator.evaluate(alerts: alerts, species: allSpecies, weatherClient: client, month: 7)

        XCTAssertEqual(updates.count, 3, "one update per alert, even though only 2 distinct regions needed fetching")
    }

    func testMissingWeatherForARegionSkipsOnlyThatRegionsAlerts() async {
        let alerts = [
            WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 2),
            WatchedAlert(speciesId: "b", regionId: "kosicky", threshold: 2)
        ]
        let client = StubClient(snapshots: ["zilinsky": snapshot(regionId: "zilinsky")]) // kosicky missing
        let allSpecies = [species(id: "a"), species(id: "b")]

        let updates = await WatchedAlertEvaluator.evaluate(alerts: alerts, species: allSpecies, weatherClient: client, month: 7)

        XCTAssertEqual(updates.map(\.alert.speciesId), ["a"])
    }

    func testShouldNotifyReflectsThresholdCrossing() async {
        let alert = WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 3, lastKnownScore: 1)
        let client = StubClient(snapshots: ["zilinsky": snapshot(regionId: "zilinsky")])

        let updates = await WatchedAlertEvaluator.evaluate(alerts: [alert], species: [species(id: "a")], weatherClient: client, month: 7)

        // idealTempMinC 0...40 and idealHumidity 0...100 mean this fixture species always
        // scores full marks when in season — month 7 is in fruitingMonths, so expect score 4.
        XCTAssertEqual(updates.first?.newScore, 4)
        XCTAssertTrue(updates.first?.shouldNotify ?? false, "previous score 1 crossing up to 4 with threshold 3 should notify")
    }

    func testEmptyAlertsReturnsEmptyWithoutFetchingAnything() async {
        let client = StubClient(snapshots: [:])
        let updates = await WatchedAlertEvaluator.evaluate(alerts: [], species: [], weatherClient: client, month: 7)
        XCTAssertTrue(updates.isEmpty)
    }

    func testSkipsAlertWhenSpeciesHasNoAffinityForWatchedRegion() async {
        let alert = WatchedAlert(speciesId: "a", regionId: "zilinsky", threshold: 2)
        let client = StubClient(snapshots: ["zilinsky": snapshot(regionId: "zilinsky")])
        let outOfRegionSpecies = species(id: "a", regionalAffinity: ["kosicky"])

        let updates = await WatchedAlertEvaluator.evaluate(alerts: [alert], species: [outOfRegionSpecies], weatherClient: client, month: 7)

        XCTAssertTrue(updates.isEmpty, "species without affinity for the watched region should never be scored or notified")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter WatchedAlertEvaluatorTests`
Expected: FAIL to compile — `WatchedAlertEvaluator` doesn't exist yet.

- [ ] **Step 3: Create `WatchedAlertEvaluator`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/Notifications/WatchedAlertEvaluator.swift`:

```swift
import Foundation

public struct WatchedAlertUpdate: Sendable {
    public let alert: WatchedAlert
    public let newScore: Int
    public let shouldNotify: Bool
}

/// Scores each watched alert against current weather, reusing SignalPipeline — no new scoring
/// logic. Fetches weather for every DISTINCT watched region in a single batched request (not
/// once per alert, not one request per region), since several alerts commonly share a region
/// and this runs ahead of the widget's completion(timeline) call. Uses the region-aware
/// SignalPipeline overload so a species outside its regionalAffinity for the watched region is
/// never scored — the same filtering every other consumer (AppState, the widget's own
/// shortlist, the map) applies; an alert whose species has no affinity for its watched region
/// is skipped, matching how that combination can't occur anywhere else in the app.
/// flushTriggered is always false, matching the same simplification the map's
/// DominantSpeciesResolver-era code used: evaluating the flush trigger per watched region would
/// need a second, batched daily-breakdown fetch, out of scope for this pass (see
/// KNOWN_ISSUES.md).
public enum WatchedAlertEvaluator {
    public static func evaluate(
        alerts: [WatchedAlert],
        species: [Species],
        weatherClient: WeatherClient,
        month: Int
    ) async -> [WatchedAlertUpdate] {
        guard !alerts.isEmpty else { return [] }

        let speciesByID = Dictionary(uniqueKeysWithValues: species.map { ($0.id, $0) })
        let distinctRegions = Set(alerts.map(\.regionId)).compactMap { RegionDatabase.find(id: $0) }
        let points = distinctRegions.map { GridPoint(id: $0.id, latitude: $0.latitude, longitude: $0.longitude) }
        let snapshotsByRegion = (try? await weatherClient.fetchSnapshots(for: points)) ?? [:]

        var updates: [WatchedAlertUpdate] = []
        for alert in alerts {
            guard let speciesForAlert = speciesByID[alert.speciesId],
                  let region = RegionDatabase.find(id: alert.regionId),
                  let snapshot = snapshotsByRegion[alert.regionId],
                  let signal = SignalPipeline.rankedSignals(species: [speciesForAlert], region: region, weather: snapshot, month: month, flushTriggered: false, limit: 1).first else { continue }
            let notify = NotificationThreshold.shouldNotify(previousScore: alert.lastKnownScore, newScore: signal.score, threshold: alert.threshold)
            updates.append(WatchedAlertUpdate(alert: alert, newScore: signal.score, shouldNotify: notify))
        }
        return updates
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter WatchedAlertEvaluatorTests`
Expected: PASS, all 5 tests.

- [ ] **Step 5: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Notifications/WatchedAlertEvaluator.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/WatchedAlertEvaluatorTests.swift
git commit -m "feat: add WatchedAlertEvaluator for per-region threshold checking"
```

---

### Task 3: Widget hook — post notifications from `ShortlistProvider.getTimeline`

**Files:**
- Create: `MushroomSignalWidget/NotificationPoster.swift`
- Modify: `MushroomSignalWidget/MushroomSignalWidget.swift`

**Interfaces:**
- Consumes: `WatchedAlertEvaluator.evaluate(alerts:species:weatherClient:month:)` and `WatchedAlertUpdate` (Task 2), `NotificationPreferences` (Task 1).
- Produces: `NotificationPoster.checkAndPostWatchedAlerts() async` — no other task depends on it (leaf of this plan besides the settings UI, which is independent).

This task has no dedicated automated test — posting a real system notification can't be unit
tested. Verified via a real signed build in the manual step below, per this project's
established convention for widget-extension behavior (see `CLAUDE.md`'s long history of
widget-signing gotchas).

- [ ] **Step 1: Create `NotificationPoster`**

Create `MushroomSignalWidget/NotificationPoster.swift`:

```swift
import Foundation
import UserNotifications
import MushroomSignalCore
import os

private let notificationLogger = Logger(subsystem: "com.alexandersalinka.MushroomSignal.Widget", category: "NotificationPoster")

enum NotificationPoster {
    /// Checks every watched alert against current weather and posts a local notification for
    /// any that just crossed its threshold upward. Always updates lastKnownScore for every
    /// alert it successfully evaluates, whether or not it notified — this is how the
    /// upward-crossing-only logic in NotificationThreshold has a baseline to compare against
    /// on the next refresh. Deliberately isolates all failures (never throws) so a bug here
    /// can never prevent the widget's own completion(timeline) call.
    static func checkAndPostWatchedAlerts() async {
        guard let preferences = NotificationPreferences() else {
            notificationLogger.error("NotificationPreferences unavailable — App Group entitlement missing or misconfigured")
            return
        }
        let alerts = preferences.watchedAlerts()
        guard !alerts.isEmpty else { return }

        guard let allSpecies = try? SpeciesDatabase.loadAll() else {
            notificationLogger.error("Failed to load species dataset for notification check")
            return
        }

        let month = Calendar.current.component(.month, from: Date())
        let updates = await WatchedAlertEvaluator.evaluate(alerts: alerts, species: allSpecies, weatherClient: OpenMeteoClient(), month: month)
        let updatesByAlertID = Dictionary(uniqueKeysWithValues: updates.map { ($0.alert.id, $0) })

        // Rebuild in the original stored order (not the update dictionary's unspecified
        // order) so the settings list doesn't silently reshuffle after every widget refresh.
        // An alert missing from `updates` (e.g. its region's weather fetch failed) is carried
        // over unchanged rather than dropped, since setWatchedAlerts below is a full replace.
        var finalAlerts: [WatchedAlert] = []
        finalAlerts.reserveCapacity(alerts.count)

        for var alert in alerts {
            guard let update = updatesByAlertID[alert.id] else {
                finalAlerts.append(alert)
                continue
            }
            alert.lastKnownScore = update.newScore
            finalAlerts.append(alert)

            guard update.shouldNotify else { continue }
            let speciesName = allSpecies.first { $0.id == alert.speciesId }?.commonNameSk ?? alert.speciesId
            let regionName = RegionDatabase.find(id: alert.regionId)?.nameSk ?? alert.regionId
            let content = UNMutableNotificationContent()
            content.title = "Hubám sa dnes darí"
            content.body = "\(speciesName) — \(regionName)"
            content.sound = .default
            let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                notificationLogger.error("Failed to post notification for \(alert.id, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        preferences.setWatchedAlerts(finalAlerts)
    }
}
```

- [ ] **Step 2: Hook it into `getTimeline`, awaited before `completion`**

Edit `MushroomSignalWidget/MushroomSignalWidget.swift`, replace:

```swift
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortlistEntry>) -> Void) {
        let limit = context.family == .systemLarge ? 4 : 3
        Task {
            let entry = await buildEntry(limit: limit)
            let nextRefresh = Calendar.current.date(byAdding: .hour, value: 12, to: Date()) ?? Date().addingTimeInterval(12 * 3600)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
```

with:

```swift
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortlistEntry>) -> Void) {
        let limit = context.family == .systemLarge ? 4 : 3
        Task {
            let entry = await buildEntry(limit: limit)
            // Awaited BEFORE completion() — WidgetKit may suspend this extension process
            // once completion() is called, so posting a notification after that point risks
            // it silently never happening.
            await NotificationPoster.checkAndPostWatchedAlerts()
            let nextRefresh = Calendar.current.date(byAdding: .hour, value: 12, to: Date()) ?? Date().addingTimeInterval(12 * 3600)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }
```

- [ ] **Step 3: Regenerate the Xcode project (new file) and build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Run the full test suite (confirms the shortlist entry itself is unaffected)**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalWidget/NotificationPoster.swift MushroomSignalWidget/MushroomSignalWidget.swift MushroomSignal.xcodeproj
git commit -m "feat: post local notifications for watched alerts from the widget's periodic refresh"
```

---

### Task 4: Settings UI

**Files:**
- Create: `MushroomSignal/NotificationSettingsState.swift`
- Create: `MushroomSignal/Views/NotificationSettingsView.swift`
- Modify: `MushroomSignal/ContentView.swift`
- Create: `MushroomSignalTests/NotificationSettingsStateTests.swift`

**Interfaces:**
- Consumes: `NotificationPreferences`, `WatchedAlert` (Task 1).
- Produces: nothing further consumed by other tasks — this is the user-facing entry point, functionally inert until Task 3 lands but independently buildable/reviewable, and can be built before or after Tasks 2/3.

- [ ] **Step 1: Write the failing `NotificationSettingsState` tests**

Create `MushroomSignalTests/NotificationSettingsStateTests.swift`:

```swift
import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class NotificationSettingsStateTests: XCTestCase {
    private func makePreferences() -> (NotificationPreferences, String) {
        let suiteName = "test.suite.\(UUID().uuidString)"
        return (NotificationPreferences(appGroupId: suiteName)!, suiteName)
    }

    func testAddWatchPersistsToPreferences() {
        let (prefs, suiteName) = makePreferences()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let state = NotificationSettingsState(preferences: prefs)

        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)

        XCTAssertEqual(state.watchedAlerts.count, 1)
        XCTAssertEqual(prefs.watchedAlerts().count, 1)
    }

    func testAddingSameSpeciesRegionUpdatesInsteadOfDuplicating() {
        let (prefs, suiteName) = makePreferences()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let state = NotificationSettingsState(preferences: prefs)

        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 2)
        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 4)

        XCTAssertEqual(state.watchedAlerts.count, 1)
        XCTAssertEqual(state.watchedAlerts.first?.threshold, 4)
    }

    func testRemoveWatchPersists() {
        let (prefs, suiteName) = makePreferences()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let state = NotificationSettingsState(preferences: prefs)
        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)

        state.removeWatch(state.watchedAlerts[0])

        XCTAssertTrue(state.watchedAlerts.isEmpty)
        XCTAssertTrue(prefs.watchedAlerts().isEmpty)
    }

    func testUpdatingThresholdPreservesLastKnownScore() {
        let (prefs, suiteName) = makePreferences()
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }
        let state = NotificationSettingsState(preferences: prefs)
        state.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 4)
        var updated = state.watchedAlerts[0]
        updated.lastKnownScore = 2
        prefs.setWatchedAlerts([updated])
        let reloaded = NotificationSettingsState(preferences: prefs)

        reloaded.addOrUpdateWatch(speciesId: "boletus-edulis", regionId: "zilinsky", threshold: 3)

        XCTAssertEqual(reloaded.watchedAlerts.first?.lastKnownScore, 2, "editing an existing watch's threshold must not discard its recorded baseline score")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/NotificationSettingsStateTests`
Expected: `** BUILD FAILED **` — `NotificationSettingsState` doesn't exist yet.

- [ ] **Step 3: Create `NotificationSettingsState`**

Create `MushroomSignal/NotificationSettingsState.swift`:

```swift
import Foundation
import UserNotifications
import MushroomSignalCore

@MainActor
final class NotificationSettingsState: ObservableObject {
    @Published var watchedAlerts: [WatchedAlert] = []
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let preferences: NotificationPreferences?

    init(preferences: NotificationPreferences? = NotificationPreferences()) {
        self.preferences = preferences
        self.watchedAlerts = preferences?.watchedAlerts() ?? []
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        guard authorizationStatus == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refreshAuthorizationStatus()
    }

    func addOrUpdateWatch(speciesId: String, regionId: String, threshold: Int) {
        let id = WatchedAlert(speciesId: speciesId, regionId: regionId, threshold: threshold).id
        let existingScore = watchedAlerts.first { $0.id == id }?.lastKnownScore
        let newAlert = WatchedAlert(speciesId: speciesId, regionId: regionId, threshold: threshold, lastKnownScore: existingScore)
        watchedAlerts.removeAll { $0.id == newAlert.id }
        watchedAlerts.append(newAlert)
        preferences?.setWatchedAlerts(watchedAlerts)
    }

    func removeWatch(_ alert: WatchedAlert) {
        watchedAlerts.removeAll { $0.id == alert.id }
        preferences?.setWatchedAlerts(watchedAlerts)
    }
}
```

- [ ] **Step 4: Regenerate the Xcode project (new file) and run the tests**

Run: `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/NotificationSettingsStateTests`
Expected: `** TEST SUCCEEDED **`, all 4 tests pass.

- [ ] **Step 5: Create `NotificationSettingsView`**

Create `MushroomSignal/Views/NotificationSettingsView.swift`:

```swift
import SwiftUI
import MushroomSignalCore

struct NotificationSettingsView: View {
    @StateObject private var state = NotificationSettingsState()
    @Environment(\.dismiss) private var dismiss
    @State private var allSpecies: [Species] = []
    @State private var selectedSpeciesId: String = ""
    @State private var selectedRegionId: String = RegionStore()?.selectedRegion().id ?? RegionStoreConstants.defaultRegionId
    @State private var threshold: Int = 3

    private var filteredSpecies: [Species] {
        allSpecies.filter { $0.regionalAffinity.contains(selectedRegionId) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if state.authorizationStatus != .authorized {
                    Section {
                        Text(state.authorizationStatus == .denied ? "Upozornenia sú zakázané. Povoľte ich v Nastaveniach systému." : "Upozornenia nie sú povolené.")
                            .font(.system(size: DesignSystem.captionSize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.8))
                        if state.authorizationStatus == .notDetermined {
                            Button("Povoliť upozornenia") {
                                Task { await state.requestAuthorizationIfNeeded() }
                            }
                            .tint(DesignSystem.Colors.mossAccent)
                        }
                    }
                }

                Section("Pridať sledovanie") {
                    Picker("Kraj", selection: $selectedRegionId) {
                        ForEach(RegionDatabase.all) { region in
                            Text(region.nameSk).tag(region.id)
                        }
                    }
                    Picker("Druh", selection: $selectedSpeciesId) {
                        ForEach(filteredSpecies) { species in
                            Text(species.commonNameSk).tag(species.id)
                        }
                    }
                    Picker("Prah", selection: $threshold) {
                        ForEach(1...4, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Button("Pridať") {
                        guard !selectedSpeciesId.isEmpty else { return }
                        state.addOrUpdateWatch(speciesId: selectedSpeciesId, regionId: selectedRegionId, threshold: threshold)
                    }
                    .tint(DesignSystem.Colors.mossAccent)
                }

                Section("Sledované druhy") {
                    ForEach(state.watchedAlerts) { alert in
                        HStack {
                            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                                Text(allSpecies.first { $0.id == alert.speciesId }?.commonNameSk ?? alert.speciesId)
                                    .font(.system(size: DesignSystem.bodySize))
                                Text(RegionDatabase.find(id: alert.regionId)?.nameSk ?? alert.regionId)
                                    .font(.system(size: DesignSystem.captionSize))
                                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            }
                            Spacer()
                            Text("≥\(alert.threshold)")
                                .font(.system(size: DesignSystem.captionSize))
                                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            Button {
                                state.removeWatch(alert)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .tint(DesignSystem.Colors.danger)
                            .help("Odstrániť sledovanie")
                        }
                        .swipeActions {
                            Button("Odstrániť", role: .destructive) {
                                state.removeWatch(alert)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Upozornenia")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavrieť") { dismiss() }
                }
            }
            .task {
                allSpecies = (try? SpeciesDatabase.loadAll()) ?? []
                if selectedSpeciesId.isEmpty {
                    selectedSpeciesId = filteredSpecies.first?.id ?? ""
                }
                await state.refreshAuthorizationStatus()
            }
            .onChange(of: selectedRegionId) { _, _ in
                if !filteredSpecies.contains(where: { $0.id == selectedSpeciesId }) {
                    selectedSpeciesId = filteredSpecies.first?.id ?? ""
                }
            }
        }
    }
}
```

**Note (post final-review fix):** `selectedRegionId` now defaults to the app's actual currently-selected
region (via `RegionStore`) rather than `RegionDatabase.all[0]`'s array-order default, and the species
picker is filtered to `filteredSpecies` (species with `regionalAffinity` for the selected region) —
both an `onChange(of: selectedRegionId)` and the initial `.task` keep `selectedSpeciesId` in sync with
that filtered list. An explicit trash-icon delete button was added alongside `.swipeActions` since
swipe-to-delete isn't a universally reliable gesture on macOS `Form`/`List` rows. The `.denied` vs
`.notDetermined` copy split avoids showing a "Povoliť upozornenia" button that silently no-ops after a
real denial. See the 2026-08-10 final-review-fix report for the full rationale.

- [ ] **Step 6: Wire the settings sheet into `ContentView`**

Edit `MushroomSignal/ContentView.swift`, replace:

```swift
struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var selectedTab: Tab = .shortlist
```

with:

```swift
struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var selectedTab: Tab = .shortlist
    @State private var showingNotificationSettings = false
```

Then replace:

```swift
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        Label("Obnoviť", systemImage: "arrow.clockwise")
                    }
                    .disabled(appState.isLoading)
                    .help("Obnoviť údaje o počasí")
                }
            }
        }
        .task { await appState.refresh() }
        .frame(minWidth: 420, minHeight: 480)
        .background(WindowTransparencyConfigurator())
```

with:

```swift
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await appState.refresh() }
                    } label: {
                        Label("Obnoviť", systemImage: "arrow.clockwise")
                    }
                    .disabled(appState.isLoading)
                    .help("Obnoviť údaje o počasí")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingNotificationSettings = true
                    } label: {
                        Label("Upozornenia", systemImage: "gearshape")
                    }
                    .help("Nastavenia upozornení")
                }
            }
        }
        .task { await appState.refresh() }
        .frame(minWidth: 420, minHeight: 480)
        .background(WindowTransparencyConfigurator())
        .sheet(isPresented: $showingNotificationSettings) {
            NotificationSettingsView()
        }
```

- [ ] **Step 7: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Full test suite**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 9: Manual visual check**

Launch the app. Click the new toolbar gear icon. Confirm: the permission-request affordance
appears if not yet authorized, adding a watch shows it in the list, removing it via swipe
works, and the sheet dismisses via "Zavrieť".

- [ ] **Step 10: Commit**

```bash
git add MushroomSignal/NotificationSettingsState.swift MushroomSignal/Views/NotificationSettingsView.swift MushroomSignal/ContentView.swift MushroomSignalTests/NotificationSettingsStateTests.swift MushroomSignal.xcodeproj
git commit -m "feat: add notification watch settings UI"
```

---

## Final Verification

- [ ] Run `swift test --package-path MushroomSignalCore` — full pass.
- [ ] Run `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData` — full pass.
- [ ] **Real signed build**, launch the app, add a watch for a species/region/threshold combination you can confirm is currently near or above threshold. Force or wait for a widget refresh (or temporarily lower the `nextRefresh` interval for testing, then revert). Confirm a real macOS notification appears with correct Slovak copy. This cannot be verified by unit tests alone — it is the one real acceptance criterion for this whole plan.
- [ ] Confirm a second refresh with the same still-above-threshold score does NOT re-notify (threshold-crossing-only behavior).
- [ ] Update `docs/superpowers/KNOWN_ISSUES.md` with what shipped, per this project's established convention.
