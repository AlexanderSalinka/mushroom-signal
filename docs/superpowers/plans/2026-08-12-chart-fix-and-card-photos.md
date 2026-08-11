# Chart Fix + Compact Card Photos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix `WeatherRainChartView`'s double-Y-axis rendering bug and finish the
already-scaffolded photo feature on `CompactSpeciesCardView`'s "Odporúčané dnes" cards.

**Architecture:** Two independent, unrelated fixes bundled in one small plan per
`docs/superpowers/specs/2026-08-12-chart-fix-and-card-photos-design.md` (pre-approved,
no further design review needed). Task 1 is a one-line SwiftUI Charts modifier. Task 2
wires an existing-but-unused `photo` parameter through to a real `CachedAsyncImage`
render, mirroring the exact photo-resolution pattern `ShortlistView.swift` already uses
for `SpeciesCardView`.

**Tech Stack:** SwiftUI, Swift Charts (`import Charts`), the existing `CachedAsyncImage`
+ `PhotoCache` + `SpeciesPhotoDatabase` infrastructure — no new dependencies.

## Global Constraints

- All new UI styling routes through `DesignSystem` — no ad hoc colors/spacing (project
  `CLAUDE.md`).
- 20pt text floor does NOT apply to `CompactSpeciesCardView` — it has a documented,
  Alexander-approved exception (see the doc comment already on the type and
  `DesignSystem.swift` ~line 78-81). Do not "fix" this while touching the file.
- This codebase has no SwiftUI View-level unit test infrastructure (confirmed:
  `MushroomSignalTests/` only covers `@ObservableObject` state classes — `AppState`,
  `RegionWeatherState`, etc. — never a `View` struct directly). Do not invent a new
  testing pattern for this plan; verify View changes by building and visually checking
  the running app, exactly as the codebase already does for `SpeciesCardView` and
  similar. Every task still ends with the full existing suite green (regression check).
- Never hand-edit `MushroomSignal.xcodeproj` — this plan touches no `project.yml`
  targets and adds no new files, so `xcodegen generate` is not needed for either task.

---

## Task 1: `WeatherRainChartView` — fix the double Y-axis

**Files:**
- Modify: `MushroomSignal/Views/WeatherRainChartView.swift:135-153`

**Interfaces:** None — purely internal to this view, no signature changes.

**Root cause (confirmed against the running app and the code):** two separate `Chart`
views are stacked in a `VStack` — a `LineMark` temp chart (lines 124-133) and a
`BarMark` rain chart (lines 135-153). Only the X-axis was unified between them (the
temp chart has `.chartXAxis(.hidden)`, the rain chart has the real one). Neither has
`.chartYAxis(.hidden)`, so each renders its own independent auto-ranged Y-axis, and
they visually collide — the temp axis's "0" (from its 0-40°C auto-range) sits directly
above the rain axis's own "5"/"10"/"0" (from its separate 0-10mm auto-range), merging
into unreadable overlapping labels.

- [ ] **Step 1: Confirm current (broken) behavior**

Build and run the app, navigate to the Predpoveď tab, look at the "Posledných 7 dní +
predpoveď" chart. Confirm the Y-axis labels on the right overlap/collide (e.g. a "0"
and "5" merging into what reads as "05", with extra numbers floating below the last
temp gridline). This is the bug this task fixes — confirm it's actually present before
changing anything.

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
pkill -f "MushroomSignal.app" 2>/dev/null
open DerivedData/Build/Products/Debug/MushroomSignal.app
```

- [ ] **Step 2: Add `.chartYAxis(.hidden)` to the rain chart only**

In `MushroomSignal/Views/WeatherRainChartView.swift`, find the rain `BarMark` chart
(currently starts at line 135):

```swift
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
```

Change it to add `.chartYAxis(.hidden)` right after the `.frame(height:)` modifier and
before `.chartXAxis`:

```swift
                Chart(visibleDays, id: \.date) { day in
                    BarMark(
                        x: .value("Deň", day.date, unit: .day),
                        y: .value("Zrážky", day.precipitationMm)
                    )
                    .foregroundStyle(DesignSystem.Colors.water)
                    .cornerRadius(DesignSystem.chartBarCornerRadius * 0.5)
                }
                .frame(height: DesignSystem.chartRainPanelHeight)
                .chartYAxis(.hidden)
                .chartXAxis {
```

Do not touch the temp `LineMark` chart (lines 124-133) — its default Y-axis (0-40°C)
is the one that already reads correctly and should stay visible. Do not touch
`.chartXAxis`, `.chartOverlay`, or anything below line 153 — this is a single-line
addition, nothing else in this view changes.

- [ ] **Step 3: Rebuild and visually verify the fix**

```bash
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
pkill -f "MushroomSignal.app" 2>/dev/null
open DerivedData/Build/Products/Debug/MushroomSignal.app
```

Navigate to Predpoveď again. Confirm: exactly one set of Y-axis labels (0/10/20/30/40,
the temp scale), no overlapping/duplicate numbers. Rain bars still render, still
proportional to their own data (a day with more rain still shows a taller bar than a
day with less) — only the redundant axis labels are gone, not the bars themselves.
Take a screenshot and look at it directly; a passing build is not sufficient evidence
this task is done.

- [ ] **Step 4: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: both green, same pass counts as before this change (this task touches no
testable logic, only chart chrome — the suite should be unaffected, its purpose here is
to confirm nothing else broke).

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/Views/WeatherRainChartView.swift
git commit -m "fix: hide the rain chart's own Y-axis so it stops colliding with the temp chart's"
```

---

## Task 2: `CompactSpeciesCardView` — wire real photos

**Files:**
- Modify: `MushroomSignal/Views/CompactSpeciesCardView.swift` (full body rewrite)
- Modify: `MushroomSignal/Views/PredpovedView.swift:9-13` (add `@State`), `:139-148`
  (add `.task`), `:161` (call site)

**Interfaces:**
- Consumes: `SpeciesPhotoDatabase.loadAll() throws -> [SpeciesPhoto]` (existing,
  `MushroomSignalCore/Sources/MushroomSignalCore/Data/SpeciesPhotoDatabase.swift`).
  `SpeciesPhoto` has `let speciesId: String` and `let imageURL: URL` (existing,
  `MushroomSignalCore/Sources/MushroomSignalCore/Models/SpeciesPhoto.swift`).
  `CachedAsyncImage<Content, PlaceholderContent>(url: URL?, content:, placeholder:)`
  (existing, `MushroomSignal/Views/CachedAsyncImage.swift`) — pass `nil` for the 7
  species with no photo, it falls through to the `placeholder` closure exactly like a
  network failure would (no new failure mode).
- Produces: `CompactSpeciesCardView`'s public interface (`species:`, `signal:`,
  `rank:`, `photo:`) is unchanged — only its internal body and `PredpovedView`'s call
  site change. No other file depends on this task's internals.

**Current state (confirmed in code):** `CompactSpeciesCardView` already declares
`let photo: SpeciesPhoto?` but never renders it — the body draws a flat gradient+grain
fill instead. `PredpovedView.swift:161` already calls it with `photo: nil` hardcoded.
`ShortlistView.swift:23,35` shows the exact pattern to mirror for resolving a photo by
species id — a `[String: [SpeciesPhoto]]` dictionary loaded once via `.task`, looked up
with `photosBySpeciesID[id]?.first`.

- [ ] **Step 1: Add photo lookup state to `PredpovedView`**

In `MushroomSignal/Views/PredpovedView.swift`, the struct currently starts:

```swift
struct PredpovedView: View {
    let regionId: String
    @ObservedObject var appState: AppState
    @StateObject private var weatherState = RegionWeatherState()
    @State private var allSpecies: [Species] = []
```

Add a new `@State` property, mirroring `ShortlistView`'s exact pattern:

```swift
struct PredpovedView: View {
    let regionId: String
    @ObservedObject var appState: AppState
    @StateObject private var weatherState = RegionWeatherState()
    @State private var allSpecies: [Species] = []
    @State private var photosBySpeciesID: [String: [SpeciesPhoto]] = [:]
```

- [ ] **Step 2: Load photos in a `.task`, mirroring `ShortlistView`**

Find the existing species-loading `.task` block (currently lines 142-148):

```swift
        .task {
            do {
                allSpecies = try SpeciesDatabase.loadAll()
            } catch {
                predpovedLogger.error("Failed to load species dataset: \(String(describing: error), privacy: .public)")
            }
        }
```

Add a second `.task` right after it, using the same grouping pattern `ShortlistView`
uses (not a throwing/logging pattern like the one above, since `ShortlistView`'s
existing version silently defaults to `[:]` on failure — match that exactly for
consistency):

```swift
        .task {
            do {
                allSpecies = try SpeciesDatabase.loadAll()
            } catch {
                predpovedLogger.error("Failed to load species dataset: \(String(describing: error), privacy: .public)")
            }
        }
        .task {
            photosBySpeciesID = (try? SpeciesPhotoDatabase.loadAll()).map { Dictionary(grouping: $0, by: \.speciesId) } ?? [:]
        }
```

- [ ] **Step 3: Update the `CompactSpeciesCardView` call site**

Find line 161:

```swift
                    CompactSpeciesCardView(species: signal.species, signal: signal, rank: index + 1, photo: nil)
```

Change `photo: nil` to the real lookup:

```swift
                    CompactSpeciesCardView(species: signal.species, signal: signal, rank: index + 1, photo: photosBySpeciesID[signal.species.id]?.first)
```

- [ ] **Step 4: Rewrite `CompactSpeciesCardView`'s body — full-bleed photo + scrim**

Replace the entire contents of `MushroomSignal/Views/CompactSpeciesCardView.swift`:

```swift
// MushroomSignal/Views/CompactSpeciesCardView.swift
import SwiftUI
import MushroomSignalCore

/// The forest redesign's compact "glass button" species card — small, roughly square,
/// fixed size regardless of window/grid resize. Distinct from `SpeciesCardView`
/// (Zoznam/Mapa's larger photo-backed grid cards, unaffected by this redesign).
///
/// Deliberate exception to the app-wide 20pt text floor (`DesignSystem.captionSize`, see
/// DesignSystem.swift ~line 16-21): this card's rank badge, name, latin name, and warning
/// text all render below 20pt. Its 120×120pt footprint is locked to the approved mockup and
/// can't fit floor-sized text for all four elements at once. Accepted tradeoff, explicitly
/// approved by Alexander 2026-08-11 — not an oversight.
struct CompactSpeciesCardView: View {
    let species: Species
    let signal: SpeciesSignal?
    let rank: Int?
    let photo: SpeciesPhoto?

    private var isWarning: Bool { species.edibility != .edible }
    private var accentColor: Color {
        isWarning ? DesignSystem.warningColor(for: species.edibility) : DesignSystem.Colors.mossAccent
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CachedAsyncImage(url: photo?.imageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    DesignSystem.Colors.bark
                    Image(systemName: "photo")
                        .font(.system(size: DesignSystem.compactCardSize * 0.28))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
                }
            }
            .frame(width: DesignSystem.compactCardSize, height: DesignSystem.compactCardSize)
            .clipped()

            LinearGradient(
                colors: [.clear, DesignSystem.Colors.forestDeep.opacity(0.95)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(width: DesignSystem.compactCardSize, height: DesignSystem.compactCardSize)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    if let rank {
                        Text("\(rank)")
                            .font(.system(size: DesignSystem.captionSize * 0.6, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                            .frame(width: DesignSystem.compactCardBadgeSize, height: DesignSystem.compactCardBadgeSize)
                            .background(Circle().fill(accentColor.opacity(0.28)))
                    }
                    Spacer()
                    if signal?.flushTriggered == true {
                        SunriseShape()
                            .stroke(DesignSystem.Colors.caution, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .frame(width: 11, height: 11)
                            .frame(width: DesignSystem.compactCardBadgeSize, height: DesignSystem.compactCardBadgeSize)
                            .background(Circle().fill(DesignSystem.Colors.caution.opacity(0.22)))
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(species.commonNameSk)
                        .font(.system(size: DesignSystem.captionSize * 0.55, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.cloud)
                        .lineLimit(2)
                    Text(species.latinName)
                        .font(.system(size: DesignSystem.captionSize * 0.45).italic())
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.55))
                        .lineLimit(1)
                    if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                        Text(warning)
                            .font(.system(size: DesignSystem.captionSize * 0.5, weight: .bold))
                            .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                            .lineLimit(1)
                    }
                    if let signal {
                        ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize * 0.4)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(8)
        }
        .frame(width: DesignSystem.compactCardSize, height: DesignSystem.compactCardSize)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.58))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.58)
                .stroke(isWarning ? DesignSystem.warningColor(for: species.edibility).opacity(0.4) : DesignSystem.Colors.cloud.opacity(0.16), lineWidth: 1)
        )
    }
}
```

What changed and why, against the spec's Robustness requirements:
- `ZStack(alignment: .topLeading)` replaces the old `VStack` — photo/placeholder is now
  the base layer, badges and text float on top, matching `SpeciesCardView`'s pattern.
- The `.grainTexture()` background modifier is removed — the approved mockup
  (Option A, full-bleed photo + scrim) never had a grain layer over a photo; grain was
  only ever used as texture for a flat color fill, which no longer exists here. This
  matches `SpeciesCardView`'s own placeholder, which also has no grain layer.
- Photo containment: `.frame(width:height:).clipped()` on the `CachedAsyncImage` itself
  pins it to exactly `compactCardSize`, and `.aspectRatio(contentMode: .fill)` inside
  that pinned frame cannot grow unbounded — this is the exact fix already proven for
  `SpeciesCardView`'s own past photo-overflow bug (unconstrained `.fill` needs an
  explicit frame to stop growing).
- Placeholder glyph: `.font(.system(size: DesignSystem.compactCardSize * 0.28))` —
  starting ratio, confirm visually in Step 6 below and adjust the multiplier if it
  looks oversized or undersized against the smaller card (this is a real design call,
  not a formula — look at it before locking in the exact number).
- Scrim: same gradient recipe `SpeciesCardView` already uses in production
  (`.clear` → `forestDeep.opacity(0.9)`, center-to-bottom), bumped to `0.95` opacity
  since this card's text is smaller and has less margin for low contrast. Verified
  against real photos in Step 6, not just the mockup's 3 sample images.
- Badges keep their existing translucent circle backgrounds unchanged — already
  sufficient contrast insurance against any photo per the spec.

- [ ] **Step 5: Build**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
```

Fix any compile errors before proceeding — do not skip ahead with a broken build.

- [ ] **Step 6: Visually verify against real data, including the missing-photo case**

```bash
pkill -f "MushroomSignal.app" 2>/dev/null
open DerivedData/Build/Products/Debug/MushroomSignal.app
```

Navigate to Predpoveď, look at "Odporúčané dnes". Confirm, by actually looking at a
screenshot:
1. Cards with a real photo (e.g. Hríb dubový / Boletus reticulatus, if it's in today's
   top picks) show that photo full-bleed, not stretched/cropped oddly, not bleeding
   past the card's rounded corners.
2. A card for one of the 7 no-photo species (if one appears in today's top picks —
   `tylopilus-felleus`, `amanita-muscaria`, `amanita-phalloides`,
   `laetiporus-sulphureus`, `tricholoma-terreum`, `armillaria-mellea`,
   `gyromitra-esculenta`) shows the bark-colored placeholder with the photo glyph, not
   a crash, not a broken image icon. If none of the 7 appear today, temporarily force
   one in during this check (e.g. hardcode a test species id in the call site,
   confirm, then revert) rather than skipping this check — this exact combination
   (caution/poisonous species + no photo) is the one already seen live in production.
3. Name, latin name, warning label (if present), and score dots are all fully legible
   against the scrim — no text disappearing into a bright part of the photo. Check this
   against at least the brightest photo in `species-photos.json`
   (`Bedľa vysoká`/Macrolepiota procera or similar light-colored species) as well as a
   dark one — not just whatever species happens to rank today.
4. Rank badge (top-left) and flush/sunrise badge (top-right, only on flush-triggered
   species) are both legible against the photo.
5. If the placeholder glyph in step 2 above looks oversized or undersized, adjust the
   `DesignSystem.compactCardSize * 0.28` multiplier in `CompactSpeciesCardView.swift`
   and rebuild until it looks visually balanced against the card.

- [ ] **Step 7: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: both green, same pass counts as before this task (no testable logic changed
— `photosBySpeciesID` is a trivial dictionary lookup mirroring an already-shipped,
already-untested-at-this-level pattern from `ShortlistView`, consistent with this
codebase's existing test coverage boundary).

- [ ] **Step 8: Commit**

```bash
git add MushroomSignal/Views/CompactSpeciesCardView.swift MushroomSignal/Views/PredpovedView.swift
git commit -m "feat: show species photos on the Predpoveď top-picks cards"
```
