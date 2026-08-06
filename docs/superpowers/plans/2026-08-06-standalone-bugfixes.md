# Standalone Bugfixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the five known v1 issues that are independent of the v2 map redesign — `.caution` species rendering identically to edible, no working refresh affordance on macOS, stale data surviving under an error banner, unordered overlapping region-switch refreshes, and no logging on any failure path — before v2 work begins.

**Architecture:** Each fix lands in the layer it already belongs to. The caution/warning styling policy is centralized in `MushroomSignalCore`'s `DesignSystem` (Core-testable via `swift test`) and consumed by both the app's `ShortlistView` and the widget's `ShortlistWidgetView`. The refresh-affordance fix is a single SwiftUI toolbar addition. The stale-data and overlapping-refresh fixes both live in `AppState.refresh()` and share one generation-token mechanism. A new `MushroomSignalTests` Xcode unit-test target is added specifically to cover `AppState`'s async state-machine behavior, which has no automated coverage today. Failure-path logging uses `os.Logger`, scoped per-target by bundle ID.

**Tech Stack:** Swift 6 / SwiftUI / WidgetKit, Swift Package Manager, XcodeGen, XCTest, `os.Logger`.

## Global Constraints

- Platform: macOS 14.0+ (Sonoma), native Swift/SwiftUI + WidgetKit only.
- All new/changed UI styling routes through `DesignSystem` (`MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`) — never hardcode ad hoc colors.
- All user-facing UI copy is in Slovak, matching existing strings' tone.
- Never hand-edit `MushroomSignal.xcodeproj` — edit `project.yml`, then run `xcodegen generate`.
- Unsigned/headless builds: append `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` to `xcodebuild` invocations.
- Never run `xcodebuild -runFirstLaunch`.
- Scope is exactly the five standalone items from `docs/superpowers/KNOWN_ISSUES.md`: caution-species labeling, refresh affordance, stale-data-on-error, overlapping-refresh ordering, and failure-path logging (the middle two share one task since they're the same generation-token fix in `AppState.refresh()`). Out of scope, deliberately deferred to v2 per that document's own annotations: the map's network-failure rendering, the three duplicated scoring-pipeline call sites, weather caching, the AppIcon, the dataset native-speaker pass, and the `RegionMapView`/`ShortlistWidgetView` raw-value design-system bypasses (the latter only where this plan's tasks don't already touch the line).
- The widget's `⚠️ obsahuje jedovaté` footer banner (`MushroomSignalWidget/ShortlistWidgetView.swift`) stays poisonous-only — it is not extended to `.caution` species. This plan only fixes the per-row treatment KNOWN_ISSUES.md describes; the footer's severity claim is unchanged.
- `AppState.init` does not get a logging call for a nil `RegionStore` (App-Group-unavailable). The known issue's actual symptom — an ambiguous `"Žiadne údaje"` string — only occurs in the widget, which Task 4 covers; the companion app already shows a distinct error banner. Adding a log there would also fire on every test that legitimately passes `store: nil` to avoid touching real `UserDefaults`/App Group state (Task 3's tests do this), which would be a false-positive failure signal, not a real one.

---

### Task 1: Caution-level species get a distinct warning treatment

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift`
- Modify: `MushroomSignal/Views/ShortlistView.swift`
- Modify: `MushroomSignalWidget/ShortlistWidgetView.swift`

**Interfaces:**
- Produces: `DesignSystem.Colors.caution: Color`, `DesignSystem.warningLabelSk(for: Edibility) -> String?`, `DesignSystem.warningColor(for: Edibility) -> Color`. `Edibility` is the existing public enum from `MushroomSignalCore/Sources/MushroomSignalCore/Models/Species.swift` (`.edible` / `.caution` / `.poisonous`) — no import needed, same module.

- [ ] **Step 1: Write the failing tests**

Append to `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift`:

```swift
    func testWarningLabelSkIsNilOnlyForEdible() {
        XCTAssertNil(DesignSystem.warningLabelSk(for: .edible))
        XCTAssertEqual(DesignSystem.warningLabelSk(for: .caution), "⚠️ Možná zámena")
        XCTAssertEqual(DesignSystem.warningLabelSk(for: .poisonous), "⚠️ Jedovatá")
    }

    func testWarningColorIsDistinctPerEdibilityLevel() {
        XCTAssertEqual(DesignSystem.warningColor(for: .edible), DesignSystem.Colors.cloud)
        XCTAssertEqual(DesignSystem.warningColor(for: .caution), DesignSystem.Colors.caution)
        XCTAssertEqual(DesignSystem.warningColor(for: .poisonous), DesignSystem.Colors.danger)
        XCTAssertNotEqual(DesignSystem.warningColor(for: .caution), DesignSystem.warningColor(for: .poisonous))
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter DesignSystemTests`
Expected: FAIL to compile — `warningLabelSk`, `warningColor`, and `Colors.caution` don't exist yet.

- [ ] **Step 3: Implement the warning-treatment policy**

Replace the full contents of `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`:

```swift
import SwiftUI

public enum DesignSystem {
    public static let goldenRatio: Double = 1.618

    private static let spacingUnit: Double = 8
    public static let spacingSmall: Double = spacingUnit
    public static let spacingMedium: Double = spacingSmall * goldenRatio
    public static let spacingLarge: Double = spacingMedium * goldenRatio
    public static let spacingExtraLarge: Double = spacingLarge * goldenRatio

    public static let cardCornerRadius: Double = 24

    public enum Colors {
        public static let forestDeep = Color(red: 0.11, green: 0.16, blue: 0.11)
        public static let forestMid = Color(red: 0.18, green: 0.25, blue: 0.16)
        public static let bark = Color(red: 0.29, green: 0.20, blue: 0.13)
        public static let water = Color(red: 0.30, green: 0.48, blue: 0.52)
        public static let cloud = Color(red: 0.94, green: 0.92, blue: 0.87)
        public static let mossAccent = Color(red: 0.42, green: 0.56, blue: 0.30)
        public static let danger = Color(red: 0.72, green: 0.24, blue: 0.20)
        public static let caution = Color(red: 0.85, green: 0.60, blue: 0.13)

        public static let cardBackground = LinearGradient(
            colors: [forestMid, forestDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The Slovak warning label for a species' edibility, or nil when no warning applies.
    public static func warningLabelSk(for edibility: Edibility) -> String? {
        switch edibility {
        case .edible: return nil
        case .caution: return "⚠️ Možná zámena"
        case .poisonous: return "⚠️ Jedovatá"
        }
    }

    /// The color a warning label/highlight should use for a species' edibility.
    public static func warningColor(for edibility: Edibility) -> Color {
        switch edibility {
        case .edible: return Colors.cloud
        case .caution: return Colors.caution
        case .poisonous: return Colors.danger
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter DesignSystemTests`
Expected: PASS, all `DesignSystemTests` green.

- [ ] **Step 5: Wire the companion app's list row**

In `MushroomSignal/Views/ShortlistView.swift`, replace:

```swift
            if signal.species.edibility == .poisonous {
                Text("⚠️ Jedovatá")
                    .font(.caption2.bold())
                    .foregroundStyle(DesignSystem.Colors.danger)
            }
```

with:

```swift
            if let warning = DesignSystem.warningLabelSk(for: signal.species.edibility) {
                Text(warning)
                    .font(.caption2.bold())
                    .foregroundStyle(DesignSystem.warningColor(for: signal.species.edibility))
            }
```

- [ ] **Step 6: Wire the widget's list row**

In `MushroomSignalWidget/ShortlistWidgetView.swift`, replace:

```swift
                ForEach(entry.signals, id: \.species.id) { signal in
                    let clampedScore = max(0, min(3, signal.score))
                    let isPoisonous = signal.species.edibility == .poisonous
                    HStack {
                        Text((isPoisonous ? "⚠️ " : "") + signal.species.commonNameSk)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(isPoisonous ? DesignSystem.Colors.danger : DesignSystem.Colors.cloud)
                            .lineLimit(1)
                        Spacer()
                        Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.mossAccent)
                    }
                }
```

with:

```swift
                ForEach(entry.signals, id: \.species.id) { signal in
                    let clampedScore = max(0, min(3, signal.score))
                    let hasWarning = signal.species.edibility != .edible
                    let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
                    HStack {
                        Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
                            .lineLimit(1)
                        Spacer()
                        Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.mossAccent)
                    }
                }
```

Leave the footer block (`if entry.signals.contains(where: { $0.species.edibility == .poisonous })`) untouched — see Global Constraints.

- [ ] **Step 7: Build the app and widget targets**

Run: `xcodegen generate && xcodebuild build -scheme MushroomSignal -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
Expected: `** BUILD SUCCEEDED **`. There is no XCTest target yet for the app/widget UI (Task 3 adds one) — this build is the verification for this step.

- [ ] **Step 8: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift MushroomSignal/Views/ShortlistView.swift MushroomSignalWidget/ShortlistWidgetView.swift
git commit -m "fix: give .caution species a distinct warning treatment"
```

---

### Task 2: Manual refresh control for macOS

**Files:**
- Modify: `MushroomSignal/ContentView.swift`

**Interfaces:**
- Consumes: `AppState.refresh() async` (existing), `AppState.isLoading: Bool` (existing, published).

`ShortlistView`'s `.refreshable` modifier has no pull-to-refresh gesture on macOS, so there is currently no way to retry after a failure. This task adds an explicit toolbar button; `.refreshable` is left in place (harmless, no-op on macOS today) since removing it is out of scope.

- [ ] **Step 1: Add the toolbar refresh button**

In `MushroomSignal/ContentView.swift`, replace:

```swift
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    RegionPickerView(appState: appState)
                }
            }
```

with:

```swift
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    RegionPickerView(appState: appState)
                }
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
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -scheme MushroomSignal -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manually verify the button**

Find the built app path from the build output (`Build/Products/Debug/MushroomSignal.app` under the reported `DerivedData` directory — see project `CLAUDE.md`'s "Headless-launch a signed build directly" note for the exact pattern), then run: `open <path-to>/MushroomSignal.app`
Expected: the toolbar shows a refresh icon next to the region picker; clicking it while a region is selected re-triggers a fetch (button disables briefly while `isLoading` is true). There is no XCTest coverage for this — it is a one-line SwiftUI toolbar addition with no app-level logic, so build success plus this manual check is the verification for this task.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/ContentView.swift
git commit -m "fix: add manual refresh button since .refreshable has no macOS affordance"
```

---

### Task 3: Add MushroomSignalTests target; fix stale data and overlapping-refresh ordering in AppState

**Files:**
- Modify: `project.yml`
- Create: `MushroomSignalTests/StubWeatherClient.swift`
- Create: `MushroomSignalTests/AppStateTests.swift`
- Modify: `MushroomSignal/AppState.swift`

**Interfaces:**
- Produces: `StubWeatherClient` (actor, conforms to `WeatherClient`, takes `[WeatherSnapshot?]` — `nil` entries throw `StubWeatherClient.StubError`, calls beyond the array's length repeat the last entry), `DelayedWeatherClient` (actor, conforms to `WeatherClient`, its first call sleeps 200ms then throws, every later call succeeds immediately — used to make overlapping-refresh ordering deterministic to test).
- Consumes: `AppState(store: RegionStore?, weatherClient: WeatherClient)` (existing init, already supports dependency injection — pass `store: nil` in tests to avoid touching the real App Group/`UserDefaults`), `RegionDatabase.all[0]` (existing, the `bratislavsky` region — 25 of the app's 27 species have this region's affinity, so a successful refresh against it is reliably non-empty regardless of weather/season).

This task adds the project's first Xcode unit-test target — `MushroomSignal`/`MushroomSignalWidget` currently have zero automated coverage, only the `MushroomSignalCore` Swift package does. The target and scheme wiring below is verified working (confirmed via a live trial: `xcodegen generate` + `xcodebuild test -scheme MushroomSignal` actually executed a test in the new target before this plan was written).

- [ ] **Step 1: Add the test target and scheme to project.yml**

In `project.yml`, insert before the `MushroomSignalWidgetExtension:` target:

```yaml
  MushroomSignalTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: MushroomSignalTests
    dependencies:
      - target: MushroomSignal
      - package: MushroomSignalCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.alexandersalinka.MushroomSignalTests
        CODE_SIGN_STYLE: Automatic

```

Then append at the end of the file (new top-level key, same indentation as `targets:`):

```yaml
schemes:
  MushroomSignal:
    build:
      targets:
        MushroomSignal: all
        MushroomSignalTests: [test]
    test:
      targets:
        - MushroomSignalTests
    run:
      config: Debug
    archive:
      config: Release
```

Run: `xcodegen generate`
Expected: `Created project at .../MushroomSignal.xcodeproj` with no errors.

- [ ] **Step 2: Write the test doubles**

Create `MushroomSignalTests/StubWeatherClient.swift`:

```swift
import MushroomSignalCore

actor StubWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}

    private var snapshots: [WeatherSnapshot?]
    private var callIndex = 0

    init(snapshots: [WeatherSnapshot?]) {
        self.snapshots = snapshots
    }

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        let index = min(callIndex, snapshots.count - 1)
        callIndex += 1
        guard let snapshot = snapshots[index] else { throw StubError() }
        return snapshot
    }
}

actor DelayedWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}
    private var callCount = 0

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(200))
            throw StubError()
        }
        return WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
    }
}
```

- [ ] **Step 3: Write the failing tests**

Create `MushroomSignalTests/AppStateTests.swift`:

```swift
import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class AppStateTests: XCTestCase {
    func testRefreshClearsStaleSignalsOnFailureAfterASuccessfulLoad() async {
        let region = RegionDatabase.all[0]
        let snapshot = WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
        let client = StubWeatherClient(snapshots: [snapshot, nil])
        let appState = AppState(store: nil, weatherClient: client)

        await appState.refresh()
        XCTAssertFalse(appState.signals.isEmpty, "precondition: first refresh should have loaded signals")

        await appState.refresh()

        XCTAssertTrue(appState.signals.isEmpty, "a failed refresh must clear the previous region's stale signals")
        XCTAssertNotNil(appState.errorMessage)
    }

    func testOverlappingRefreshesApplyLastStartedWinsOrdering() async {
        let client = DelayedWeatherClient()
        let appState = AppState(store: nil, weatherClient: client)

        async let first: Void = appState.refresh()
        try? await Task.sleep(for: .milliseconds(20))
        async let second: Void = appState.refresh()
        _ = await (first, second)

        XCTAssertNil(appState.errorMessage, "the second (later-started, faster) refresh succeeded and must not be overwritten when the slower first call fails after it")
        XCTAssertFalse(appState.signals.isEmpty)
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:MushroomSignalTests/AppStateTests`
Expected: `** TEST FAILED **` — both tests fail against the current `AppState.swift` (confirmed during plan validation: the stale-data test fails because `signals` isn't cleared on error, the ordering test fails because the slower first call's late failure overwrites the second call's success).

- [ ] **Step 5: Implement the fix**

Replace the full contents of `MushroomSignal/AppState.swift`:

```swift
import Foundation
import os
import MushroomSignalCore

@MainActor
final class AppState: ObservableObject {
    @Published var selectedRegion: Region
    @Published var signals: [SpeciesSignal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store: RegionStore?
    private let weatherClient: WeatherClient
    private var currentRefreshID: UUID?
    private let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "AppState")

    init(store: RegionStore? = RegionStore(), weatherClient: WeatherClient = OpenMeteoClient()) {
        self.store = store
        self.weatherClient = weatherClient
        self.selectedRegion = store?.selectedRegion() ?? RegionDatabase.all[0]
    }

    func selectRegion(_ region: Region) {
        selectedRegion = region
        store?.setSelectedRegion(region)
        Task { await refresh() }
    }

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
            let weather = try await weatherClient.fetchSnapshot(for: region)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let allSignals = allSpecies
                .filter { $0.regionalAffinity.contains(region.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            guard currentRefreshID == refreshID else { return }
            signals = ShortlistRanker.topSpecies(from: allSignals, limit: allSignals.count)
        } catch {
            guard currentRefreshID == refreshID else { return }
            signals = []
            errorMessage = "Nepodarilo sa načítať údaje o počasí. Skúste to znova."
            logger.error("Refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
```

`currentRefreshID` is a generation token: each `refresh()` call stamps its own UUID before its first `await`, and both the success and failure branches check the token still matches before mutating `signals`/`errorMessage`/`isLoading`. A call that finishes after a newer call has already started silently discards its own result instead of overwriting the newer one — this fixes both the stale-data-on-error issue and the last-finished-wins ordering issue with one mechanism, since they're the same race manifesting on the failure path vs. the success path.

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO -only-testing:MushroomSignalTests/AppStateTests`
Expected: `** TEST SUCCEEDED **`, both tests green. (Confirmed stable across 3 consecutive runs during plan validation — the 200ms/20ms margin is generous, not flaky-tight.)

- [ ] **Step 7: Commit**

```bash
git add project.yml MushroomSignal.xcodeproj MushroomSignalTests MushroomSignal/AppState.swift
git commit -m "fix: clear stale signals on refresh failure and apply last-started-wins ordering to overlapping refreshes"
```

---

### Task 4: Failure-path logging in the widget's timeline provider

**Files:**
- Modify: `MushroomSignalWidget/MushroomSignalWidget.swift`

**Interfaces:**
- Consumes: `RegionStore.init?(appGroupId:)` (existing, returns nil when the App Group is unavailable), `OpenMeteoClient.fetchSnapshot(for:)` and `SpeciesDatabase.loadAll()` (existing, both throwing).

The widget's `"Žiadne údaje"` string currently means one of four things — network failure, JSON decode failure, App Group unavailable, or genuinely nothing in season — with no way to tell which. This task splits `buildEntry()` so the App-Group-unavailable fallback logs distinctly from network/decode failures, and logs the real thrown error for the latter. The genuinely-nothing-in-season case still produces zero log output, since it isn't a failure.

- [ ] **Step 1: Split buildEntry() and add logging**

In `MushroomSignalWidget/MushroomSignalWidget.swift`, add the import and a module-level logger after the existing imports:

```swift
import WidgetKit
import SwiftUI
import MushroomSignalCore
import os

private let widgetLogger = Logger(subsystem: "com.alexandersalinka.MushroomSignal.Widget", category: "TimelineProvider")
```

Replace the `buildEntry()` method:

```swift
    private func buildEntry() async -> ShortlistEntry {
        let region = RegionStore()?.selectedRegion() ?? RegionDatabase.all[0]

        do {
            let weather = try await OpenMeteoClient().fetchSnapshot(for: region)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let signals = allSpecies
                .filter { $0.regionalAffinity.contains(region.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            let shortlist = ShortlistRanker.topSpecies(from: signals, limit: 3)
            return ShortlistEntry(date: Date(), region: region, signals: shortlist)
        } catch {
            return ShortlistEntry(date: Date(), region: region, signals: [])
        }
    }
```

with:

```swift
    private func buildEntry() async -> ShortlistEntry {
        guard let store = RegionStore() else {
            widgetLogger.error("RegionStore unavailable — App Group entitlement missing or misconfigured; using default region")
            return await fetchEntry(region: RegionDatabase.all[0])
        }
        return await fetchEntry(region: store.selectedRegion())
    }

    private func fetchEntry(region: Region) async -> ShortlistEntry {
        do {
            let weather = try await OpenMeteoClient().fetchSnapshot(for: region)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let signals = allSpecies
                .filter { $0.regionalAffinity.contains(region.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            let shortlist = ShortlistRanker.topSpecies(from: signals, limit: 3)
            return ShortlistEntry(date: Date(), region: region, signals: shortlist)
        } catch {
            widgetLogger.error("Timeline refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return ShortlistEntry(date: Date(), region: region, signals: [])
        }
    }
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild build -scheme MushroomSignal -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
Expected: `** BUILD SUCCEEDED **`. There is no widget-extension test target in this plan (out of scope — one target's worth of test infra was already added in Task 3 for the app; a second for the widget extension is a bigger addition than this known issue warrants). Build success is this task's verification; log output itself can be confirmed later by triggering a real failure (e.g. airplane mode) and checking Console.app filtered to subsystem `com.alexandersalinka.MushroomSignal.Widget`, but that manual check is optional, not required to close this task.

- [ ] **Step 3: Commit**

```bash
git add MushroomSignalWidget/MushroomSignalWidget.swift
git commit -m "fix: log widget timeline failures instead of silently collapsing to an empty entry"
```
