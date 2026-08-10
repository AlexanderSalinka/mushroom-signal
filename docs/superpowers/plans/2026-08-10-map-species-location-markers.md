# Map Species-Location Markers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Draw an on-map indicator, at a coarsened `SlovakiaGrid` point set, of which active species currently dominates there — reusing the app's existing `●●○○` score-dot glyph instead of the rejected solid-region-fill approach.

**Architecture:** Extract the score-dots glyph (currently inlined in `SpeciesCardView`) into a shared `ScoreDotsView`. Coarsen `SlovakiaGrid` from 39 to ~11 points. Replace `MapScreenState.dominantSpecies(at:) -> Species?` with `dominantSignal(at:) -> SpeciesSignal?` (exposing score, not just the winner), inlining what `DominantSpeciesResolver` did and deleting that now-redundant wrapper. Render fixed-size `Annotation` markers (not `MapCircle`, which is what made an earlier attempt look "very very crazy" at some zoom levels) in `InteractiveMapView`, colored via the existing `speciesColors` legend palette.

**Tech Stack:** Swift, SwiftUI, MapKit (`Annotation`), XCTest, Swift Package Manager (`MushroomSignalCore`) + XcodeGen-generated Xcode project (`MushroomSignal`/`MushroomSignalTests`).

## Global Constraints

- All new UI styling routes through `DesignSystem` — no hardcoded colors/sizes/spacing (project `CLAUDE.md`).
- No changes to `SignalPipeline`, `SignalAlgorithm`, or ranking/scoring logic — the marker reuses the exact same scoring already used for the legend and shortlist (spec Out of Scope).
- No tap interaction on markers — map stays read-only display (spec Out of Scope).
- No widget changes, no 3-tab split, no kraj-boundary redrawing — all explicitly out of scope for this pass (spec Out of Scope).
- `XcodeGen does NOT auto-detect new/changed .swift files` — any task that adds a file under `MushroomSignal/` requires `xcodegen generate` before the next Xcode build, or the build silently links a stub missing the new code (project `CLAUDE.md`).
- Core-package (`MushroomSignalCore/`) source changes need no `xcodegen generate` — Swift Package Manager auto-discovers its own sources; only files under the Xcode-project targets (`MushroomSignal/`, `MushroomSignalTests/`) need regeneration.
- Always pass `-derivedDataPath DerivedData` to every `xcodebuild` invocation (project `CLAUDE.md`).

---

### Task 1: Coarsen `SlovakiaGrid`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift:10-11`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SlovakiaGridTests.swift:5-9`

**Interfaces:**
- Consumes: nothing new.
- Produces: `SlovakiaGrid.generate() -> [GridPoint]` — same signature, now returns ~11 points (confirmed range 8...16) instead of ~39 (confirmed range 30...50). `MapScreenState.init` (unchanged this task) already calls this and assigns the result to `gridPoints`, so the coarser point set flows through automatically once this task lands.

- [ ] **Step 1: Update the point-count test to the new expected range first**

Edit `MushroomSignalCore/Tests/MushroomSignalCoreTests/SlovakiaGridTests.swift`, replace:

```swift
    func testGeneratePointCountLandsInExpectedRange() {
        let points = SlovakiaGrid.generate()
        XCTAssertGreaterThanOrEqual(points.count, 30)
        XCTAssertLessThanOrEqual(points.count, 50)
    }
```

with:

```swift
    func testGeneratePointCountLandsInExpectedRange() {
        let points = SlovakiaGrid.generate()
        XCTAssertGreaterThanOrEqual(points.count, 8)
        XCTAssertLessThanOrEqual(points.count, 16)
    }
```

- [ ] **Step 2: Run the test to verify it fails against the current (uncoarsened) constants**

Run: `swift test --package-path MushroomSignalCore --filter SlovakiaGridTests/testGeneratePointCountLandsInExpectedRange`
Expected: FAIL — `points.count` is 39, greater than the new upper bound of 16.

- [ ] **Step 3: Coarsen the grid constants**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift`, replace:

```swift
    private static let latitudeStep = 0.4
    private static let longitudeStep = 0.6
```

with:

```swift
    private static let latitudeStep = 0.8
    private static let longitudeStep = 1.2
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter SlovakiaGridTests/testGeneratePointCountLandsInExpectedRange`
Expected: PASS (11 points at these constants).

- [ ] **Step 5: Run the full `SlovakiaGridTests` suite to confirm no regression in the other two tests**

Run: `swift test --package-path MushroomSignalCore --filter SlovakiaGridTests`
Expected: PASS — `testEveryPointFallsWithinBoundingBox` and `testPointIDsAreUnique` are unaffected by the point-count change (they assert per-point properties, not count).

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SlovakiaGridTests.swift
git commit -m "feat: coarsen SlovakiaGrid spacing from 39 to ~11 points"
```

---

### Task 2: Extract `ScoreDotsView`

**Files:**
- Create: `MushroomSignal/Views/ScoreDotsView.swift`
- Modify: `MushroomSignal/Views/SpeciesCardView.swift:45-49`

**Interfaces:**
- Consumes: nothing new.
- Produces: `ScoreDotsView(score: Int, color: Color, dotSize: Double) -> some View` — a SwiftUI `View` rendering the `●●○○` glyph, clamped to `0...4`. Task 4 consumes this directly for map markers.

This project's established convention (see `docs/superpowers/specs/2026-08-08-map-region-scoping-design.md`'s own Testing section, and this feature's spec) is that pure SwiftUI rendering views get a build + manual visual check, not a dedicated XCTest — there's no view-snapshot testing infrastructure in this repo. This task follows that convention rather than inventing one.

- [ ] **Step 1: Create `ScoreDotsView.swift`**

```swift
// MushroomSignal/Views/ScoreDotsView.swift
import SwiftUI

struct ScoreDotsView: View {
    let score: Int
    let color: Color
    let dotSize: Double

    var body: some View {
        let clamped = max(0, min(4, score))
        Text(String(repeating: "●", count: clamped) + String(repeating: "○", count: 4 - clamped))
            .font(.system(size: dotSize))
            .foregroundStyle(color)
    }
}
```

- [ ] **Step 2: Regenerate the Xcode project so the new file is picked up**

Run: `xcodegen generate`
Expected: completes without error; `MushroomSignal.xcodeproj` now references `ScoreDotsView.swift` (XcodeGen does not auto-detect new files — this step is required, not optional, per this project's `CLAUDE.md`).

- [ ] **Step 3: Build to verify the new file compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Replace `SpeciesCardView`'s inlined score-dots with `ScoreDotsView`**

Edit `MushroomSignal/Views/SpeciesCardView.swift`, replace:

```swift
                if let signal {
                    let clampedScore = max(0, min(4, signal.score))
                    Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 4 - clampedScore))
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(DesignSystem.Colors.mossAccent)
                    if let reason = signal.reason {
```

with:

```swift
                if let signal {
                    ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize)
                    if let reason = signal.reason {
```

- [ ] **Step 5: Build again to verify the refactor compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manual visual check — no regression**

Launch the app (`DerivedData/Build/Products/Debug/MushroomSignal.app`), open Zoznam. Confirm species cards with a live signal still render the identical `●●○○`-style dot cluster in the same position/size/color as before this change — this is a pure refactor, zero visual difference expected.

- [ ] **Step 7: Commit**

```bash
git add MushroomSignal/Views/ScoreDotsView.swift MushroomSignal/Views/SpeciesCardView.swift MushroomSignal.xcodeproj
git commit -m "refactor: extract ScoreDotsView from SpeciesCardView's inlined score dots"
```

---

### Task 3: `MapScreenState.dominantSignal(at:)` — expose score, not just the winner

**Files:**
- Modify: `MushroomSignal/MapScreenState.swift:66-72`
- Modify: `MushroomSignalTests/MapScreenStateTests.swift:42-56`
- Delete: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/DominantSpeciesResolver.swift`
- Delete: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalPipeline.swift:5` (doc-comment reword)
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift:32-33` (doc-comment reword)

**Interfaces:**
- Consumes: `SignalPipeline.rankedSignals(candidates:weather:month:flushTriggered:limit:) -> [SpeciesSignal]` (existing, unchanged).
- Produces: `MapScreenState.dominantSignal(at pointID: String) -> SpeciesSignal?`, replacing `dominantSpecies(at:) -> Species?` (removed). `SpeciesSignal` has `species: Species`, `score: Int`, `reason: String?` — Task 4 consumes `signal.species.id` and `signal.score`.

- [ ] **Step 1: Rewrite `MapScreenStateTests.swift`'s two `dominantSpecies` tests against `dominantSignal`, plus one new score-zero case**

Edit `MushroomSignalTests/MapScreenStateTests.swift`, replace:

```swift
    func testDominantSpeciesReturnsNilWithNoActiveSpecies() async {
        // Load a real snapshot first so the assertion below exercises the "no active species"
        // path specifically, not the separate "no snapshot for this point" early-return.
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot]))
        await state.loadGrid()

        XCTAssertNil(state.dominantSpecies(at: "grid-00"))
    }

    func testDominantSpeciesReturnsNilWhenSnapshotMissing() {
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil]))
        state.toggleSpecies("boletus-edulis")
        XCTAssertNil(state.dominantSpecies(at: "grid-00"), "no snapshot was ever loaded for this point")
    }
```

with:

```swift
    func testDominantSignalReturnsNilWithNoActiveSpecies() async {
        // Load a real snapshot first so the assertion below exercises the "no active species"
        // path specifically, not the separate "no snapshot for this point" early-return.
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot]))
        await state.loadGrid()

        XCTAssertNil(state.dominantSignal(at: "grid-00"))
    }

    func testDominantSignalReturnsNilWhenSnapshotMissing() {
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil]))
        state.toggleSpecies("boletus-edulis")
        XCTAssertNil(state.dominantSignal(at: "grid-00"), "no snapshot was ever loaded for this point")
    }

    func testDominantSignalReturnsNilWhenActiveSpeciesScoresZero() async {
        // Uses the real bundled species dataset (MapScreenState.allSpecies isn't injectable) and
        // picks whichever species is genuinely out of season for "today" (calendarFit == 0 is the
        // only way SignalAlgorithm.computeSignal can resolve to a hard score of 0), rather than
        // hardcoding a month/species pair that would only hold on some calendar dates.
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot]))
        await state.loadGrid()

        let month = Calendar.current.component(.month, from: Date())
        let previousMonth = month == 1 ? 12 : month - 1
        let nextMonth = month == 12 ? 1 : month + 1
        guard let outOfSeasonSpecies = state.allSpecies.first(where: {
            !$0.fruitingMonths.contains(month) && !$0.fruitingMonths.contains(previousMonth) && !$0.fruitingMonths.contains(nextMonth)
        }) else {
            XCTFail("expected at least one species in the real dataset out of season for the current month")
            return
        }

        state.toggleSpecies(outOfSeasonSpecies.id)
        XCTAssertNil(state.dominantSignal(at: "grid-00"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail to build (the API doesn't exist yet)**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/MapScreenStateTests`
Expected: `** BUILD FAILED **` — `value of type 'MapScreenState' has no member 'dominantSignal'`. This is the correct red signal for a rename/behavior-change task.

- [ ] **Step 3: Replace `dominantSpecies(at:)` with `dominantSignal(at:)` in `MapScreenState.swift`**

Edit `MushroomSignal/MapScreenState.swift`, replace:

```swift
    func dominantSpecies(at pointID: String) -> Species? {
        guard let snapshot = snapshots[pointID] else { return nil }
        let active = allSpecies.filter { activeSpeciesOrder.contains($0.id) }
        guard !active.isEmpty else { return nil }
        let month = Calendar.current.component(.month, from: Date())
        return DominantSpeciesResolver.resolve(activeSpecies: active, weather: snapshot, month: month)
    }
```

with:

```swift
    func dominantSignal(at pointID: String) -> SpeciesSignal? {
        guard let snapshot = snapshots[pointID] else { return nil }
        let active = allSpecies.filter { activeSpeciesOrder.contains($0.id) }
        guard !active.isEmpty else { return nil }
        let month = Calendar.current.component(.month, from: Date())
        guard let top = SignalPipeline.rankedSignals(candidates: active, weather: snapshot, month: month, flushTriggered: false, limit: 1).first,
              top.score > 0 else {
            return nil
        }
        return top
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/MapScreenStateTests`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Delete `DominantSpeciesResolver` and its dedicated test file**

```bash
git rm MushroomSignalCore/Sources/MushroomSignalCore/Signal/DominantSpeciesResolver.swift
git rm MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift
```

- [ ] **Step 6: Reword the two remaining doc-comment mentions of `DominantSpeciesResolver`**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalPipeline.swift`, replace:

```swift
/// The one shared score→rank path for turning candidate species into a ranked shortlist.
/// Used by the app's `AppState.refresh()`, the widget's `ShortlistProvider`, and (via
/// `DominantSpeciesResolver`) the map's per-point dominant-species resolution — previously
/// each reimplemented filter→score→rank independently (see KNOWN_ISSUES.md).
```

with:

```swift
/// The one shared score→rank path for turning candidate species into a ranked shortlist.
/// Used by the app's `AppState.refresh()`, the widget's `ShortlistProvider`, and
/// `MapScreenState.dominantSignal(at:)` for the map's per-point dominant-species resolution —
/// previously each reimplemented filter→score→rank independently (see KNOWN_ISSUES.md).
```

Edit `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift`, replace:

```swift
        // The lower-level overload takes pre-filtered candidates directly (used by
        // DominantSpeciesResolver, whose "active species" list isn't region-derived).
```

with:

```swift
        // The lower-level overload takes pre-filtered candidates directly (used by
        // MapScreenState.dominantSignal(at:), whose "active species" list isn't region-derived).
```

- [ ] **Step 7: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS, no missing-symbol errors, no leftover references to the deleted type.

- [ ] **Step 8: Run the full Xcode test suite**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 9: Commit**

```bash
git add MushroomSignal/MapScreenState.swift MushroomSignalTests/MapScreenStateTests.swift MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalPipeline.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift
git commit -m "refactor: replace dominantSpecies(at:) with dominantSignal(at:), inline DominantSpeciesResolver"
```

---

### Task 4: Render markers on the map, update `KNOWN_ISSUES.md`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift` (add token near line 53)
- Modify: `MushroomSignal/Views/InteractiveMapView.swift`
- Modify: `docs/superpowers/KNOWN_ISSUES.md`

**Interfaces:**
- Consumes: `ScoreDotsView` (Task 2), `MapScreenState.dominantSignal(at:) -> SpeciesSignal?` and `MapScreenState.speciesColors: [String: Color]` (Task 3, `speciesColors` unchanged this pass), `MapScreenState.gridPoints: [GridPoint]` (Task 1, now coarsened).
- Produces: `DesignSystem.mapMarkerDotSize: Double` — no other task depends on this; it's a leaf token.

This task has no dedicated automated test — same rendering-view convention as Task 2. The manual visual check in Step 5 is this task's real verification.

- [ ] **Step 1: Add the `mapMarkerDotSize` token**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`, replace:

```swift
    /// InteractiveMapView's legend swatch diameter.
    public static let legendDotSize: Double = 8
```

with:

```swift
    /// InteractiveMapView's legend swatch diameter.
    public static let legendDotSize: Double = 8
    /// Score-dot glyph size inside a map marker — a decorative map-icon scale, matching the
    /// precedent set by `legendDotSize`. Not subject to the 20pt body-text floor, which governs
    /// readable text, not small status glyphs.
    public static let mapMarkerDotSize: Double = 6
```

- [ ] **Step 2: Run the core package test suite to verify the addition compiles cleanly**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS (no test asserts this token's value — it's a design constant, not behavior — but this confirms the package still builds).

- [ ] **Step 3: Add the marker `ForEach` to `InteractiveMapView`'s `Map` content**

Edit `MushroomSignal/Views/InteractiveMapView.swift`, replace:

```swift
                ForEach(Array(RegionDatabase.all.enumerated()), id: \.element.id) { index, region in
                    if let boundary = RegionBoundaries.polygon(for: region.id) {
                        MapPolygon(coordinates: boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                            .foregroundStyle(.clear)
                            .stroke(DesignSystem.Colors.regionPalette[index % DesignSystem.Colors.regionPalette.count], lineWidth: 1.5)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
```

with:

```swift
                ForEach(Array(RegionDatabase.all.enumerated()), id: \.element.id) { index, region in
                    if let boundary = RegionBoundaries.polygon(for: region.id) {
                        MapPolygon(coordinates: boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                            .foregroundStyle(.clear)
                            .stroke(DesignSystem.Colors.regionPalette[index % DesignSystem.Colors.regionPalette.count], lineWidth: 1.5)
                    }
                }

                ForEach(mapState.gridPoints) { point in
                    if let signal = mapState.dominantSignal(at: point.id), let color = mapState.speciesColors[signal.species.id] {
                        Annotation(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)) {
                            ScoreDotsView(score: signal.score, color: color, dotSize: DesignSystem.mapMarkerDotSize)
                                .padding(.horizontal, DesignSystem.spacingTight)
                                .padding(.vertical, DesignSystem.spacingTight / 2)
                                .background(Capsule().fill(DesignSystem.Colors.forestDeep.opacity(0.85)))
                        } label: { EmptyView() }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat))
```

`Annotation` renders at a fixed screen size regardless of map zoom — unlike `MapCircle` (used by the region-border layer's precursor, and by an earlier abandoned overlay attempt), whose geographic radius grows/shrinks with zoom. This is why markers stay small at every zoom level rather than needing radius tuning.

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **` (`xcodegen generate` is a no-op here since no files were added/removed this task, but running it is cheap and keeps the habit consistent — skip only if you've confirmed no `MushroomSignal/`-tree files changed name/location).

- [ ] **Step 5: Manual visual check — this is the real verification for this task**

Launch the app (`DerivedData/Build/Products/Debug/MushroomSignal.app`), open Mapa, toggle 2-3 species active in Knižnica druhov. Confirm:
- Small dot-cluster markers appear at a restrained number of points (not a swarm — 11 max, fewer if some resolve to nil).
- Marker colors match the legend's species→color mapping exactly.
- Marker size stays visually small and fixed as you zoom the map in/out (not growing/shrinking).
- Toggling a species on/off in Knižnica druhov visibly updates which markers appear/disappear and their colors.
- No marker appears at a point with no resolved signal (missing snapshot, no active species, or a resolved score of 0 — all three should render nothing there).

- [ ] **Step 6: Update `KNOWN_ISSUES.md`**

Edit `docs/superpowers/KNOWN_ISSUES.md`, add a new section directly above `## Open Issues`:

```markdown
## Fixed (2026-08-10 map-markers pass)

- **`SlovakiaGrid`/`dominantSpecies`/`speciesColors` machinery was live but never drawn on the
  map** — fixed. `SlovakiaGrid` coarsened from 39 to ~11 points (`latitudeStep`/`longitudeStep`
  0.4/0.6 → 0.8/1.2). New shared `ScoreDotsView` extracts the `●●○○` glyph out of
  `SpeciesCardView` so the card and the new map markers render it identically.
  `MapScreenState.dominantSpecies(at:) -> Species?` replaced with
  `dominantSignal(at:) -> SpeciesSignal?`, exposing score alongside the winning species;
  `DominantSpeciesResolver` (a thin wrapper adding no value beyond calling `SignalPipeline`
  directly) deleted along with its dedicated test file. `InteractiveMapView` now renders a fixed
  screen-size `Annotation` marker (deliberately not `MapCircle`, whose geographic radius scaling
  is what made an earlier grid-overlay attempt look "very very crazy") at each grid point with a
  resolved non-nil signal, colored via the existing legend palette.
```

Then add a new bullet under `## Open Issues` (append to the end of the list):

```markdown
- **`RegionBoundaries`' hand-approximated kraj polygon coordinates render jagged ("broken
  glass") borders** — deferred follow-up from the 2026-08-09 map-markers spec, confirmed
  real by Alexander. Redrawing them for smoother edges is a future pass, not blocking.
```

- [ ] **Step 7: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift MushroomSignal/Views/InteractiveMapView.swift docs/superpowers/KNOWN_ISSUES.md
git commit -m "feat: render per-point species-dominance markers on the map"
```

---

## Final Verification

- [ ] Run `swift test --package-path MushroomSignalCore` — full pass.
- [ ] Run `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData` — full pass.
- [ ] Full signed build launch: confirm Zoznam cards, Mapa's species library cards, and the new map markers all render `●●○○`-style dots identically via the one shared `ScoreDotsView`.
- [ ] Confirm `grep -rn "DominantSpeciesResolver" --include="*.swift" .` (excluding `.build`/`DerivedData`) returns no results — fully removed, not just unreferenced.
- [ ] Confirm `docs/superpowers/KNOWN_ISSUES.md` reflects what shipped and the one new deferred follow-up (jagged borders), matching this project's established convention of tracking gaps there rather than only in conversation memory.
