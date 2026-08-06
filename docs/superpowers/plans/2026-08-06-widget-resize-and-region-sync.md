# Widget Resize & Region-Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the widget natively drag-resizable (small/medium/large) with size-appropriate layouts, and make it reflect a region change immediately instead of waiting up to 12 hours.

**Architecture:** Two independent fixes carved out of the v2 design spec (`docs/superpowers/specs/2026-08-05-mushroom-signal-v2-design.md`, §5 and §6), built without the map/species-library work those sections were originally bundled with. Region-sync is a dependency-injected `WidgetCenter.shared.reloadAllTimelines()` call from `AppState.selectRegion(_:)`. Resize is `MushroomSignalWidget.supportedFamilies` growing to three families, with `ShortlistWidgetView` branching on `@Environment(\.widgetFamily)` and a small new `DesignSystem` typography scale driving per-family font sizes.

**Tech Stack:** Swift, SwiftUI, WidgetKit, XCTest. macOS 14.0 deployment target. `MushroomSignalCore` stays a WidgetKit-free Swift package — nothing in this plan adds a WidgetKit import there.

## Global Constraints

- All new UI styling routes through `DesignSystem` — colors, spacing, typography — never hardcode ad hoc numeric literals in a `.font(.system(size:))` call. (Project `CLAUDE.md`.)
- UI strings stay in Slovak, matching existing widget/app copy exactly in tone (e.g. "Žiadne údaje", "⚠️ obsahuje jedovaté").
- Widget family layouts and TimelineProvider family-branching have no meaningful XCTest surface for the SwiftUI layout itself — verify those via `xcodebuild build` (pinned `-derivedDataPath DerivedData`) plus Xcode `#Preview` per family, per the v2 spec's own Testing section. Logic that *is* pure (e.g. the region-sync trigger) still gets a real XCTest — don't skip testing something testable just because a neighboring task isn't.
- Always build with `-derivedDataPath DerivedData` (repo-relative, gitignored, pinned per project `CLAUDE.md`) — never a bare `xcodebuild` invocation.
- Scope is strictly v2 spec §5 (Widget Family Expansion) + §6 (Widget Region-Sync Fix). No MapKit map, no species library, no photo work — those stay deferred to a separate future plan.
- macOS App Groups need the team-ID prefix (`RegionStore.swift`'s existing `resolvedAppGroupId` pattern) — not touched by this plan, but don't reintroduce a bare `group.xxx` string anywhere new.

---

## Task 1: Widget Region-Sync Fix

**Files:**
- Create: `MushroomSignal/WidgetReloading.swift`
- Create: `MushroomSignalTests/SpyWidgetReloader.swift`
- Modify: `MushroomSignal/AppState.swift`

**Interfaces:**
- Produces: `protocol WidgetReloading: Sendable { func reloadAllTimelines() async }`, `struct SystemWidgetCenter: WidgetReloading`, `AppState.init(store:weatherClient:widgetReloader:)` (new `widgetReloader` parameter, defaults to `SystemWidgetCenter()`).

- [ ] **Step 1: Write the failing test**

Create `MushroomSignalTests/SpyWidgetReloader.swift`:

```swift
@testable import MushroomSignal

actor SpyWidgetReloader: WidgetReloading {
    private(set) var reloadCount = 0

    func reloadAllTimelines() async {
        reloadCount += 1
    }
}
```

Add to `MushroomSignalTests/AppStateTests.swift` (inside the `AppStateTests` class, alongside the existing two tests):

```swift
    func testSelectRegionReloadsWidgetTimelines() async {
        let reloader = SpyWidgetReloader()
        let appState = AppState(store: nil, weatherClient: StubWeatherClient(snapshots: [nil]), widgetReloader: reloader)

        appState.selectRegion(RegionDatabase.all[1])
        try? await Task.sleep(for: .milliseconds(50))

        let count = await reloader.reloadCount
        XCTAssertEqual(count, 1, "selecting a new region must trigger an immediate widget timeline reload, not wait for the next scheduled 12h refresh")
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project MushroomSignal.xcodeproj -scheme MushroomSignal -derivedDataPath DerivedData -only-testing:MushroomSignalTests/AppStateTests/testSelectRegionReloadsWidgetTimelines`
Expected: FAIL — compile error, `WidgetReloading` and the `widgetReloader:` init parameter don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Create `MushroomSignal/WidgetReloading.swift`:

```swift
import WidgetKit

protocol WidgetReloading: Sendable {
    func reloadAllTimelines() async
}

struct SystemWidgetCenter: WidgetReloading {
    func reloadAllTimelines() async {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
```

Modify `MushroomSignal/AppState.swift`:

```swift
@MainActor
final class AppState: ObservableObject {
    @Published var selectedRegion: Region
    @Published var signals: [SpeciesSignal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store: RegionStore?
    private let weatherClient: WeatherClient
    private let widgetReloader: WidgetReloading
    private var currentRefreshID: UUID?
    private let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "AppState")

    init(
        store: RegionStore? = RegionStore(),
        weatherClient: WeatherClient = OpenMeteoClient(),
        widgetReloader: WidgetReloading = SystemWidgetCenter()
    ) {
        self.store = store
        self.weatherClient = weatherClient
        self.widgetReloader = widgetReloader
        self.selectedRegion = store?.selectedRegion() ?? RegionDatabase.all[0]
    }

    func selectRegion(_ region: Region) {
        selectedRegion = region
        store?.setSelectedRegion(region)
        Task {
            await widgetReloader.reloadAllTimelines()
            await refresh()
        }
    }
```

(`refresh()` below is unchanged — only `init` and `selectRegion(_:)` change.)

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -project MushroomSignal.xcodeproj -scheme MushroomSignal -derivedDataPath DerivedData -only-testing:MushroomSignalTests/AppStateTests`
Expected: PASS — all three `AppStateTests` (the two pre-existing plus the new one).

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/WidgetReloading.swift MushroomSignal/AppState.swift MushroomSignalTests/SpyWidgetReloader.swift MushroomSignalTests/AppStateTests.swift
git commit -m "fix: reload widget timelines immediately when region changes"
```

---

## Task 2: DesignSystem Typography Tokens

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift`

**Interfaces:**
- Produces: `DesignSystem.captionSize`, `.bodySize`, `.titleSize`, `.heroSize` (all `Double`), consumed by Task 4's `ShortlistWidgetView`.

- [ ] **Step 1: Write the failing test**

Add to `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift` (inside the `DesignSystemTests` class):

```swift
    func testTypographyScaleIsIncreasing() {
        XCTAssertLessThan(DesignSystem.captionSize, DesignSystem.bodySize)
        XCTAssertLessThan(DesignSystem.bodySize, DesignSystem.titleSize)
        XCTAssertLessThan(DesignSystem.titleSize, DesignSystem.heroSize)
    }

    func testTypographyRatiosApproximateGoldenRatio() {
        let ratio1 = DesignSystem.bodySize / DesignSystem.captionSize
        let ratio2 = DesignSystem.titleSize / DesignSystem.bodySize
        XCTAssertEqual(ratio1, DesignSystem.goldenRatio, accuracy: 0.001)
        XCTAssertEqual(ratio2, DesignSystem.goldenRatio, accuracy: 0.001)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path MushroomSignalCore --filter DesignSystemTests`
Expected: FAIL — compile error, `captionSize`/`bodySize`/`titleSize`/`heroSize` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Modify `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift` — add below the existing spacing block (after `spacingExtraLarge`, before `cardCornerRadius`):

```swift
    private static let typographyUnit: Double = 8
    public static let captionSize: Double = typographyUnit
    public static let bodySize: Double = captionSize * goldenRatio
    public static let titleSize: Double = bodySize * goldenRatio
    public static let heroSize: Double = titleSize * goldenRatio
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter DesignSystemTests`
Expected: PASS — all `DesignSystemTests`.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift
git commit -m "feat: add DesignSystem typography scale for widget family layouts"
```

---

## Task 3: Family-Aware Shortlist Limit in the Widget Timeline

**Files:**
- Modify: `MushroomSignalWidget/MushroomSignalWidget.swift`

**Interfaces:**
- Consumes: `WidgetFamily` (WidgetKit), `ShortlistRanker.topSpecies(from:limit:)` (existing, `MushroomSignalCore`).
- Produces: `ShortlistProvider.fetchEntry(region:limit:)` (renamed from `fetchEntry(region:)`), consumed only within this file.

**Decision (spec left this open — v2 spec §5 says "Large: full shortlist" without a number):** small and medium keep the existing top-3 shortlist; large shows top-6. This is a widget-only display cap, not a change to the underlying ranking or to `AppState`'s own (already-unlimited) signal list.

- [ ] **Step 1: Modify `getTimeline` to read the requested family and thread it through**

In `MushroomSignalWidget/MushroomSignalWidget.swift`, replace the `ShortlistProvider` body:

```swift
struct ShortlistProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShortlistEntry {
        ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ShortlistEntry) -> Void) {
        completion(ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: []))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortlistEntry>) -> Void) {
        let limit = context.family == .systemLarge ? 6 : 3
        Task {
            let entry = await buildEntry(limit: limit)
            let nextRefresh = Calendar.current.date(byAdding: .hour, value: 12, to: Date()) ?? Date().addingTimeInterval(12 * 3600)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func buildEntry(limit: Int) async -> ShortlistEntry {
        guard let store = RegionStore() else {
            widgetLogger.error("RegionStore unavailable — App Group entitlement missing or misconfigured; using default region")
            return await fetchEntry(region: RegionDatabase.all[0], limit: limit)
        }
        return await fetchEntry(region: store.selectedRegion(), limit: limit)
    }

    private func fetchEntry(region: Region, limit: Int) async -> ShortlistEntry {
        do {
            let weather = try await OpenMeteoClient().fetchSnapshot(for: region)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let signals = allSpecies
                .filter { $0.regionalAffinity.contains(region.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            let shortlist = ShortlistRanker.topSpecies(from: signals, limit: limit)
            return ShortlistEntry(date: Date(), region: region, signals: shortlist)
        } catch {
            widgetLogger.error("Timeline refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
            return ShortlistEntry(date: Date(), region: region, signals: [])
        }
    }
}
```

(`ShortlistEntry`, `widgetLogger`, and `MushroomSignalWidget: Widget` below are unchanged in this task — `supportedFamilies` is updated in Task 4.)

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild build -project MushroomSignal.xcodeproj -scheme MushroomSignalWidgetExtension -derivedDataPath DerivedData`
Expected: `** BUILD SUCCEEDED **`. (No XCTest target covers the widget extension — this task's own Testing note in the v2 spec calls out family-branching as build+preview-verified, not unit-tested; Task 1 and Task 2 above are exactly the parts of this plan that *are* unit-testable, and both got real tests.)

- [ ] **Step 3: Commit**

```bash
git add MushroomSignalWidget/MushroomSignalWidget.swift
git commit -m "feat: size the widget shortlist to the requested widget family"
```

---

## Task 4: Per-Family Widget Layouts + `supportedFamilies` Expansion

**Files:**
- Modify: `MushroomSignalWidget/ShortlistWidgetView.swift`
- Modify: `MushroomSignalWidget/MushroomSignalWidget.swift`
- Modify: `CLAUDE.md` (project root)

**Interfaces:**
- Consumes: `DesignSystem.captionSize/.bodySize/.titleSize/.heroSize` (Task 2), `DesignSystem.warningColor(for:)`/`Colors` (existing), `ShortlistEntry` (Task 3, unchanged shape).

- [ ] **Step 1: Rewrite `ShortlistWidgetView` with per-family layouts**

Replace `MushroomSignalWidget/ShortlistWidgetView.swift` in full:

```swift
// MushroomSignalWidget/ShortlistWidgetView.swift
import SwiftUI
import WidgetKit
import MushroomSignalCore

struct ShortlistWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ShortlistEntry

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            case .systemLarge:
                largeBody
            default:
                smallBody
            }
        }
        .padding(DesignSystem.spacingMedium)
        .containerBackground(for: .widget) {
            DesignSystem.Colors.cardBackground
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            regionHeader
            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals, id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.bodySize, weight: .semibold), showLatin: false)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            regionHeader
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                ForEach(entry.signals, id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.titleSize, weight: .semibold), showLatin: true)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
            regionHeader
            if let hero = entry.signals.first {
                heroRow(for: hero)
            }
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                ForEach(entry.signals.dropFirst(), id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.titleSize, weight: .semibold), showLatin: true)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
            footer
        }
    }

    private var regionHeader: some View {
        Text(entry.region.nameSk)
            .font(.caption2)
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
    }

    @ViewBuilder
    private var emptyStateIfNeeded: some View {
        if entry.signals.isEmpty {
            Text("Žiadne údaje")
                .font(.system(size: DesignSystem.bodySize))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
        }
    }

    private var footer: some View {
        Group {
            if entry.signals.contains(where: { $0.species.edibility == .poisonous }) {
                Text("⚠️ obsahuje jedovaté")
                    .font(.system(size: DesignSystem.captionSize, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.danger)
                    .lineLimit(1)
            } else {
                Text(entry.date, style: .time)
                    .font(.system(size: DesignSystem.captionSize))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            }
        }
    }

    private func row(for signal: SpeciesSignal, nameFont: Font, showLatin: Bool) -> some View {
        let clampedScore = max(0, min(3, signal.score))
        let hasWarning = signal.species.edibility != .edible
        let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                    .font(nameFont)
                    .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
                    .lineLimit(1)
                if showLatin {
                    Text(signal.species.latinName)
                        .font(.system(size: DesignSystem.captionSize).italic())
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
                .font(.system(size: DesignSystem.captionSize))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
    }

    private func heroRow(for signal: SpeciesSignal) -> some View {
        let clampedScore = max(0, min(3, signal.score))
        let hasWarning = signal.species.edibility != .edible
        let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
        return VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                .font(.system(size: DesignSystem.heroSize, weight: .bold))
                .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
                .lineLimit(1)
            Text(signal.species.latinName)
                .font(.system(size: DesignSystem.bodySize).italic())
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
                .font(.system(size: DesignSystem.titleSize))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
    }
}

private func previewSignal(name: String, latin: String, edibility: Edibility, score: Int) -> SpeciesSignal {
    SpeciesSignal(
        species: Species(
            id: name,
            commonNameSk: name,
            latinName: latin,
            edibility: edibility,
            fruitingMonths: [8, 9, 10],
            idealTempMinC: 8,
            idealTempMaxC: 18,
            rainfallSensitivity: .medium,
            habitat: "listnatý les",
            regionalAffinity: [RegionDatabase.all[4].id]
        ),
        score: score,
        reason: nil
    )
}

#Preview("Small", as: .systemSmall) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ])
}

#Preview("Medium", as: .systemMedium) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ])
}

#Preview("Large", as: .systemLarge) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Plávka zelenkastá", latin: "Russula virescens", edibility: .caution, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ])
}
```

- [ ] **Step 2: Expand `supportedFamilies`**

In `MushroomSignalWidget/MushroomSignalWidget.swift`, change the `MushroomSignalWidget: Widget` body's last line:

```swift
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
```

- [ ] **Step 3: Build and verify all three previews render without truncation/overlap**

Run: `xcodebuild build -project MushroomSignal.xcodeproj -scheme MushroomSignalWidgetExtension -derivedDataPath DerivedData`
Expected: `** BUILD SUCCEEDED **`.

Then open `MushroomSignalWidget/ShortlistWidgetView.swift` in Xcode and check the canvas for all three `#Preview` blocks ("Small", "Medium", "Large") — confirm no clipped/overlapping text at any size, and that the poisonous-species warning color/icon still renders correctly in each.

- [ ] **Step 4: Update the now-stale project convention note**

In `CLAUDE.md` (project root), under `## Project Conventions`, replace:

```
- Widget supports `.systemSmall` only — deliberate v1 scope limit, not a bug (v2 spec already covers small/medium/large)
```

with:

```
- Widget supports `.systemSmall`, `.systemMedium`, `.systemLarge` (shipped from v2 spec §5) — `ShortlistWidgetView` branches on `@Environment(\.widgetFamily)`; large shows a 4-item shortlist (hero + 3) with a hero row for #1, small/medium stay at 3 items (see `ShortlistProvider.getTimeline` in `MushroomSignalWidget.swift`) — reduced from the plan's original 6 during Task 4's fix round after review found hero+5 rows overflowed the large widget's content budget; medium also dropped its latin-subtitle line and moved to `bodySize` names for the same reason
```

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalWidget/ShortlistWidgetView.swift MushroomSignalWidget/MushroomSignalWidget.swift CLAUDE.md
git commit -m "feat: add medium/large widget layouts and enable native drag-resize"
```

---

## Final Verification

- [ ] Run the full test suite: `xcodebuild test -project MushroomSignal.xcodeproj -scheme MushroomSignal -derivedDataPath DerivedData` — expect all `MushroomSignalTests` green, including `testSelectRegionReloadsWidgetTimelines`.
- [ ] Run the core package suite: `swift test --package-path MushroomSignalCore` — expect all green, including the two new typography tests.
- [ ] Launch `DerivedData/Build/Products/Debug/MushroomSignal.app`, open the widget in macOS's Edit Widgets gallery, drag-resize through all three sizes, and switch region in the companion app to confirm the widget updates within a few seconds (not up to 12h).
- [ ] Update `docs/superpowers/KNOWN_ISSUES.md` — remove the "Widget doesn't refresh when region changes in-app" entry from Open Issues (it's fixed); leave the other open items (duplicated scoring pipeline, regional-map unknown-cell rendering, no weather caching, dataset name review, AppIcon, design-system bypasses) untouched — none of those are in scope here.

---

## Post-Plan Amendments (final whole-branch review, 2026-08-06)

The final review found the Task 4 fix round's own fit-math rested on an unverified widget-frame constant (used `~334×334pt` for large; the real macOS large widget frame is `329×345pt`, and WidgetKit's default content margins were never accounted for), and that dropping medium's latin subtitle entirely (Task 4's fix round) left `mediumBody` byte-identical to `smallBody` — no differentiation, contradicting spec §5's stated medium-family intent. One further fix wave (commits `ce8a5ad`, `371e86c`, `9382ca2`) addressed this and three smaller findings; the code above no longer matches these specific points as shipped:

- **`row(for:)` / `mediumBody`**: gained an `inlineLatin: Bool` parameter. When `true` (medium only), the row renders `Text(commonName) + Text(" · " + latinName)` concatenated as one single-line `Text` (zero added height vs. small) instead of a second line — restoring medium's differentiation without reopening the height overflow the earlier fix round fixed. Small and large keep their original `showLatin` behavior (`false`/`true` respectively, latin on its own line for large).
- **Defensive scaling**: `.minimumScaleFactor(0.8)` added to the hero name, row name, and row/medium latin-subtitle `Text` views (not to score dots or the region header) — the layout now degrades gracefully instead of clipping if the real on-screen frame turns out smaller than assumed. This is the actual mitigation for "does it fit," superseding the plan's original fixed-point-size assumption.
- **`row(for:)`'s hardcoded `spacing: 2`** (line 395 above) is now `DesignSystem.spacingTight` (`= spacingSmall / 4`, a new token added to `DesignSystem.swift` alongside the existing spacing block) — same value, routed through the design system per the project's hard constraint.
- **`CLAUDE.md`'s Project Conventions bullet** no longer states specific content-budget pt figures (they were wrong); it now describes the layout qualitatively and notes the min-scale-factor fallback.
- **Two test-quality fixes**, unrelated to layout: `testSelectRegionReloadsWidgetTimelines` now uses `XCTestExpectation` instead of a fixed `Task.sleep`, and `DesignSystemTests` gained the missing `heroSize/titleSize` golden-ratio assertion (`ratio3`).

**Still not done as of this amendment** (flagged by the final review, requires a human with Xcode/GUI access — no session in this plan's execution had one): actually opening the three `#Preview` blocks in Xcode's SwiftUI canvas, and launching the signed build to drag-resize the real widget through all three sizes and confirm a region switch propagates within seconds. The `.minimumScaleFactor` mitigation above reduces the risk of this being skipped, but doesn't replace it.
