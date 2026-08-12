# Widget Temperature + Rain Bands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the MushroomSignal widget temperature and rain info in every family, a denser
species list, and a centered region header with date+time — replacing the aggregate poisonous
footer banner (per-row `⚠️` markers already carry that safety info).

**Architecture:** `ShortlistEntry` gains a `dailyWeather: [DailyWeather]` field (already fetched
by `ShortlistProvider.fetchEntry`, just not threaded through yet). `ShortlistWidgetView` computes
temperature/rain facts from it via `WeatherSnapshot.derive`/`UpcomingRainDetector`/
`MostRecentRainfall` (all existing, from `MushroomSignalCore`) and renders them as new tile
views, reusing the exact circle-badge-plus-text visual language `MushroomSignalHeroView`
already established. `DropletShape`/`SunriseShape` move from the app-only `ForestIcons.swift`
into a new `MushroomSignalCore/.../DesignSystem/SharedIcons.swift` (public) so the widget
extension target — which cannot see app-target source files — can draw them too.

**Tech Stack:** Swift, SwiftUI, WidgetKit — no new dependencies.

## Global Constraints

- Per `docs/superpowers/specs/2026-08-12-widget-weather-bands-design.md`: any change to the
  app's own hero panel is out of scope — untouched. No animation — WidgetKit renders a static
  snapshot per timeline refresh. The aggregate `"⚠️ obsahuje jedovaté"` footer banner is
  **removed** (per-row `⚠️` markers on individual poisonous/caution species are unchanged and
  carry the safety info now).
- **Item 1 (weather-fetch-consolidation) is a satisfied prerequisite** — `WeatherSnapshot.derive`
  already exists in `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift`
  (confirmed on `main` before this plan was written).
- **Item 8 (widget-fetch-unification) is NOT a prerequisite for this plan**, despite the design
  spec's "post Item 8" phrasing. Confirmed by reading the current code:
  `ShortlistProvider.fetchEntry` (`MushroomSignalWidget/MushroomSignalWidget.swift`) already
  fetches a `[DailyWeather]` array via its existing two-call shape
  (`fetchDailyBreakdown(for:pastDays:10)`) — Item 10 only threads that already-fetched value
  through one more field. Whether the widget's fetch is later consolidated to one call (Item 8)
  is unrelated to whether `ShortlistEntry` carries the array. Do not implement Item 8 as part of
  this plan.
- `ShortlistEntry.dailyWeather` has **no default value** (matches the design spec's struct
  definition exactly) — every construction site must supply it explicitly. This plan touches
  every such site across `MushroomSignalWidget.swift` and `ShortlistWidgetView.swift`'s 3
  `#Preview` blocks.
- On `ShortlistProvider.fetchEntry`'s own failure paths (the outer `catch`, where `fetchSnapshot`
  or `SpeciesDatabase.loadAll()` threw before any daily-breakdown fetch happened), pass
  `dailyWeather: []`. There is no cache to fall back to for the daily array on this path yet —
  wiring `DailyWeatherCache` into the widget's own fallback is Item 8's scope, not this plan's.
  The weather tiles already degrade gracefully on an empty array (`"—"` temperature, `"Bez
  výraznejšieho dažďa"` rain) — this is the design's intended behavior for missing data, not a
  gap this plan needs to patch further.
- `getTimeline`'s species `limit` (`MushroomSignalWidget.swift`) must change from
  `context.family == .systemLarge ? 4 : 3` to `context.family == .systemLarge ? 9 : 4` — required
  for the redesigned species list (small/medium: 4 rows, large: 9 total) to actually receive
  enough signals to show. The design spec does not state this as an explicit diff since it only
  describes `ShortlistWidgetView`'s rendering, not `ShortlistProvider`'s fetch limit — identified
  by reading the current code, not assumed.
- No SwiftUI View-level unit test infrastructure exists in this codebase (confirmed:
  `MushroomSignalTests/` only covers `@ObservableObject`/pure-logic types, never a `View` struct
  directly, and `MushroomSignalCore`'s existing `ForestIcons.swift`-equivalent shapes have no
  test precedent either). Every task in this plan is verified by build success plus a visual
  check (Xcode's `#Preview` canvas), not XCTest.
- **Known, disclosed limitation, not introduced by this plan:** this project's widget has a
  pre-existing widget-gallery visibility bug (unnotarized personal-team signing — see this
  repo's `CLAUDE.md`). A live desktop-widget screenshot may not be obtainable regardless of what
  this plan does. Visual verification here means Xcode's `#Preview` canvas (which renders the
  real `ShortlistWidgetView` struct directly, without needing the widget to register with the
  OS), not the live gallery.
- `MushroomSignal/Info.plist` and `MushroomSignalWidget/Info.plist` are mutated by every
  `xcodebuild build`/`xcodebuild test` as a side effect — check `git status --short` on both
  before every commit in this plan and `git checkout --` them if modified.
- Never hand-edit `MushroomSignal.xcodeproj` directly — only `project.yml` + `xcodegen generate`.
  Not expected to be needed anywhere in this plan (no `.swift` files are added or removed outside
  `MushroomSignalCore`, which auto-discovers; the one new file, `SharedIcons.swift`, lives inside
  the Core Swift Package).
- `SharedIcons.swift`'s shapes must be `public` (matching `DesignSystem.swift`'s own precedent of
  `import SwiftUI` inside `MushroomSignalCore`) — the widget extension target cannot see
  `internal` declarations from a different module.
- All new UI styling routes through `DesignSystem` tokens — no ad hoc hardcoded colors/spacing
  except where a token doesn't exist yet and the design spec gives an explicit literal value
  (e.g. tile icon frame sizes) — matches the design spec's own code exactly in those cases.

---

## Task 1: Shared icons move to `MushroomSignalCore`

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/SharedIcons.swift`
- Modify: `MushroomSignal/Views/ForestIcons.swift`

**Interfaces:**
- Produces: `public struct DropletShape: Shape`, `public struct SunriseShape: Shape`,
  `public struct MushroomShape: Shape` (all with `public init() {}`) — consumed by Task 3
  (widget weather tiles + species podium) and by 5 existing app-target call sites (unchanged,
  see Step 3).

**Background (confirmed in code):** `ForestIcons.swift` currently defines `DropletShape` and
`SunriseShape` as plain (non-public) structs with no explicit `init()`. Five app-target files
call them with no module prefix: `CompactSpeciesCardView.swift:65`, `SpeciesCardView.swift:50`,
`PredpovedView.swift:112`, `MushroomSignalHeroView.swift:205,228,232`. All five already
`import MushroomSignalCore`, so moving the shapes there and making them `public` requires zero
call-site changes — confirmed by reading each file's imports.

- [ ] **Step 1: Create `SharedIcons.swift`**

Create `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/SharedIcons.swift`:

```swift
import SwiftUI

/// Shapes shared between the app and widget extension targets — ForestIcons.swift
/// (MushroomSignal/Views/) holds app-only shapes; anything the widget also needs to draw
/// lives here instead, since the widget extension can't see app-target source files.

public struct DropletShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.5, y: y))
        path.addCurve(
            to: CGPoint(x: x + w * 0.92, y: y + h * 0.65),
            control1: CGPoint(x: x + w * 0.5, y: y),
            control2: CGPoint(x: x + w * 0.92, y: y + h * 0.4)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y + h),
            control1: CGPoint(x: x + w * 0.92, y: y + h * 0.9),
            control2: CGPoint(x: x + w * 0.73, y: y + h)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.08, y: y + h * 0.65),
            control1: CGPoint(x: x + w * 0.27, y: y + h),
            control2: CGPoint(x: x + w * 0.08, y: y + h * 0.9)
        )
        path.addCurve(
            to: CGPoint(x: x + w * 0.5, y: y),
            control1: CGPoint(x: x + w * 0.08, y: y + h * 0.4),
            control2: CGPoint(x: x + w * 0.5, y: y)
        )
        path.closeSubpath()
        return path
    }
}

public struct SunriseShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x, y: y + h * 0.75))
        path.addLine(to: CGPoint(x: x + w, y: y + h * 0.75))

        path.move(to: CGPoint(x: x + w * 0.29, y: y + h * 0.75))
        path.addArc(
            center: CGPoint(x: x + w * 0.5, y: y + h * 0.75),
            radius: w * 0.21,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: true
        )

        path.move(to: CGPoint(x: x + w * 0.5, y: y + h * 0.33))
        path.addLine(to: CGPoint(x: x + w * 0.5, y: y + h * 0.13))

        path.move(to: CGPoint(x: x + w * 0.27, y: y + h * 0.46))
        path.addLine(to: CGPoint(x: x + w * 0.12, y: y + h * 0.29))

        path.move(to: CGPoint(x: x + w * 0.73, y: y + h * 0.46))
        path.addLine(to: CGPoint(x: x + w * 0.88, y: y + h * 0.29))

        return path
    }
}

/// A generic single mushroom (cap + stem, gill lines beneath the cap) — the widget's
/// top-3 podium squares. Deliberately distinct from the hero's `MushroomCapShape` (a
/// three-cap-burst animation motif, app-only, not a static per-species icon).
public struct MushroomShape: Shape {
    public init() {}
    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height, x = rect.minX, y = rect.minY
        var path = Path()
        path.move(to: CGPoint(x: x + w * 0.2, y: y + h * 0.5))
        path.addCurve(
            to: CGPoint(x: x + w * 0.8, y: y + h * 0.5),
            control1: CGPoint(x: x + w * 0.2, y: y + h * 0.05),
            control2: CGPoint(x: x + w * 0.8, y: y + h * 0.05)
        )
        path.move(to: CGPoint(x: x + w * 0.4, y: y + h * 0.55))
        path.addCurve(
            to: CGPoint(x: x + w * 0.4, y: y + h * 0.85),
            control1: CGPoint(x: x + w * 0.4, y: y + h * 0.55),
            control2: CGPoint(x: x + w * 0.4, y: y + h * 0.85)
        )
        path.addLine(to: CGPoint(x: x + w * 0.6, y: y + h * 0.85))
        path.addLine(to: CGPoint(x: x + w * 0.6, y: y + h * 0.55))
        path.move(to: CGPoint(x: x + w * 0.325, y: y + h * 0.45))
        path.addCurve(
            to: CGPoint(x: x + w * 0.675, y: y + h * 0.45),
            control1: CGPoint(x: x + w * 0.45, y: y + h * 0.325),
            control2: CGPoint(x: x + w * 0.55, y: y + h * 0.325)
        )
        return path
    }
}
```

- [ ] **Step 2: Remove `DropletShape`/`SunriseShape` from `ForestIcons.swift`**

In `MushroomSignal/Views/ForestIcons.swift`, delete the entire `DropletShape` struct (currently
lines 31-59, the "A classic teardrop/raindrop silhouette" comment plus its `struct DropletShape:
Shape { ... }` block) and the entire `SunriseShape` struct (currently lines 62-89, the "A horizon
line..." comment plus its block). Leave every other shape in the file (`LeafShape`, `SporeShape`,
`MushroomCapShape`, `GrowthRaysShape`, `CloudOutlineShape`) untouched.

- [ ] **Step 3: Build the app target to confirm the 5 existing call sites still resolve**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
```

Expected: builds clean. This confirms `CompactSpeciesCardView.swift:65`,
`SpeciesCardView.swift:50`, `PredpovedView.swift:112`, and
`MushroomSignalHeroView.swift:205,228,232` all resolve `DropletShape()`/`SunriseShape()` against
the new `MushroomSignalCore` definitions with no call-site edits needed. If any of these fail to
resolve, do NOT add a module-qualified prefix at the call site as a workaround — investigate why
(likely a missing `import MushroomSignalCore` that this plan's Global Constraints section
assumed incorrectly) and report back before proceeding.

- [ ] **Step 4: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
```

Expected: all green (169, unchanged — this task adds no tests, per the design spec's
no-test-precedent for pure-geometry shapes).

- [ ] **Step 5: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/SharedIcons.swift MushroomSignal/Views/ForestIcons.swift
git commit -m "feat: move DropletShape/SunriseShape to MushroomSignalCore, add MushroomShape"
```

---

## Task 2: `ShortlistEntry` gains the daily weather array

**Files:**
- Modify: `MushroomSignalWidget/MushroomSignalWidget.swift`
- Modify: `MushroomSignalWidget/ShortlistWidgetView.swift` (3 `#Preview` blocks only — mechanical
  compile fix, not the view body; Task 3 replaces these placeholder values with realistic sample
  data)

**Interfaces:**
- Consumes: none new (the local `dailyWeather` variable `fetchEntry` already computes).
- Produces: `ShortlistEntry.dailyWeather: [DailyWeather]` (new stored property, no default) —
  consumed by Task 3 (`ShortlistWidgetView`'s new computed properties).

- [ ] **Step 1: Add the field to `ShortlistEntry`**

In `MushroomSignalWidget/MushroomSignalWidget.swift`, change:

```swift
struct ShortlistEntry: TimelineEntry {
    let date: Date
    let region: Region
    let signals: [SpeciesSignal]
}
```

to:

```swift
struct ShortlistEntry: TimelineEntry {
    let date: Date
    let region: Region
    let signals: [SpeciesSignal]
    let dailyWeather: [DailyWeather]
}
```

- [ ] **Step 2: Update `placeholder(in:)` and `getSnapshot(in:completion:)`**

Change:

```swift
    func placeholder(in context: Context) -> ShortlistEntry {
        ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ShortlistEntry) -> Void) {
        completion(ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: []))
    }
```

to:

```swift
    func placeholder(in context: Context) -> ShortlistEntry {
        ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: [], dailyWeather: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ShortlistEntry) -> Void) {
        completion(ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: [], dailyWeather: []))
    }
```

- [ ] **Step 3: Thread `dailyWeather` through `fetchEntry`'s three return sites**

In `fetchEntry(region:limit:)`, change the success return:

```swift
            return ShortlistEntry(date: Date(), region: region, signals: shortlist)
```

to:

```swift
            return ShortlistEntry(date: Date(), region: region, signals: shortlist, dailyWeather: dailyWeather)
```

This reuses the `dailyWeather` local variable already computed a few lines above (line 49-55 of
the current file) — it may legitimately be `[]` if the inner `fetchDailyBreakdown` call already
failed there (existing behavior, unchanged), which is fine and consistent with this plan's
Global Constraints on graceful degradation.

In the outer `catch` block, change the cached-fallback return:

```swift
                return ShortlistEntry(date: cached.fetchedAt, region: region, signals: shortlist)
```

to:

```swift
                return ShortlistEntry(date: cached.fetchedAt, region: region, signals: shortlist, dailyWeather: [])
```

And the hard-failure return:

```swift
            return ShortlistEntry(date: Date(), region: region, signals: [], dailyWeather: [])
```

(This one goes from `ShortlistEntry(date: Date(), region: region, signals: [])` — add
`dailyWeather: []`.)

- [ ] **Step 4: Fix the 3 `#Preview` blocks in `ShortlistWidgetView.swift` so the file still compiles**

**Note:** these previews are rewritten again in Task 3 Step 5 with realistic sample data —
this step only needs them to compile.

In `MushroomSignalWidget/ShortlistWidgetView.swift`, each of the 3 `#Preview` blocks constructs
`ShortlistEntry(date:region:signals:)` with no `dailyWeather:` argument. Add `dailyWeather: []`
to all three (this is a mechanical compile fix only — Task 3 replaces these placeholder `[]`
values with realistic sample data once the weather tiles exist to preview):

```swift
#Preview("Small", as: .systemSmall) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: [])
}

#Preview("Medium", as: .systemMedium) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: [])
}

#Preview("Large", as: .systemLarge) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 4),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Plávka zelenkastá", latin: "Russula virescens", edibility: .caution, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: [])
}
```

- [ ] **Step 5: Update `getTimeline`'s species limit**

In `getTimeline(in:completion:)`, change:

```swift
        let limit = context.family == .systemLarge ? 4 : 3
```

to:

```swift
        let limit = context.family == .systemLarge ? 9 : 4
```

This is required for Task 3's redesigned species list (small/medium: 4 rows, large: 9 total —
3 podium + 6 ranked) to receive enough signals from `SignalPipeline.rankedSignals(...,
limit:)` to actually show. Not part of the design spec's own code blocks (which only describe
`ShortlistWidgetView`'s rendering) — identified by reading `SignalPipeline.rankedSignals`'s
`limit` parameter usage in this same file.

- [ ] **Step 6: Build and verify**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: build succeeds, Core suite green (169, unchanged), app suite green (20, unchanged —
this task adds no tests, pure data-plumbing plus a `View`-level preview fix).

- [ ] **Step 7: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignalWidget/MushroomSignalWidget.swift MushroomSignalWidget/ShortlistWidgetView.swift
git commit -m "feat: thread dailyWeather through ShortlistEntry, raise species fetch limit"
```

---

## Task 3: `ShortlistWidgetView` redesign — header, weather tiles, species list

**Files:**
- Modify: `MushroomSignalWidget/ShortlistWidgetView.swift`

**Interfaces:**
- Consumes: `entry.dailyWeather: [DailyWeather]` (Task 2), `WeatherSnapshot.derive(regionId:
  from:windowDays:asOf:calendar:)` (Item 1, already on `main`), `UpcomingRainDetector
  .nextTriggerEvent(in:asOf:calendar:)` and `RainEvent` (existing), `MostRecentRainfall
  .find(in:asOf:calendar:)` (existing), `DropletShape`/`SunriseShape`/`MushroomShape` (Task 1).
- Produces: no new interface — this is the plan's final task, all changes are internal to
  `ShortlistWidgetView`'s own rendering.

**Note on `infoBand` (small family's weather tiles):** the design spec describes this as
"the same circle-badge-plus-text pattern the original `rainIncomingSection` established
(`infoBand(icon:color:headline:subline:)` helper, unchanged from the first draft of this spec)"
but does not include `infoBand`'s code in its final document — a documentation gap in the spec
(the pattern was approved across 8 mockup rounds; the exact helper code from an earlier draft
wasn't carried into the final write-up). The code below is this plan's own synthesis, built
directly from `MushroomSignalHeroView.swift`'s existing `HStack(badge, VStack(headline,
subline))` pattern (lines 97-107 of that file) — the same "circle-badge-plus-text" language the
spec names — scaled down to widget/`captionSize` proportions and given `squareTile`'s existing
rounded-rect-with-tint-background-and-stroke-border container (lines 296-305 of the design spec)
so the small family's bands and the medium/large family's tiles read as one visual family, not
two unrelated patterns. **Flag this specific helper for a quick visual sanity check** — it is
the one piece of this task not traceable to spec-verbatim code.

- [ ] **Step 1: Add the region header, removing the footer**

Replace:

```swift
    private var regionHeader: some View {
        Text(entry.region.nameSk)
            .font(.caption2)
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
    }
```

with:

```swift
    private static let headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "sk_SK")
        formatter.dateFormat = "d. MMMM · HH:mm"
        return formatter
    }()

    private var regionHeader: some View {
        VStack(spacing: 1) {
            Text(entry.region.nameSk)
                .font(.system(size: DesignSystem.captionSize * 0.65, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.85))
            Text(Self.headerDateFormatter.string(from: entry.date))
                .font(.system(size: DesignSystem.captionSize * 0.55))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
```

Locale is forced to `sk_SK` — same rationale as `MushroomSignalHeroView.monthFormatter`: every
string in this app is Slovak, and an unforced formatter would silently render English month
names on a non-Slovak-locale device.

Delete the `footer` computed property entirely:

```swift
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
```

This does not remove safety information — `row(for:...)`/`heroRow(for:)` already prefix an
individual poisonous/caution species' name with `"⚠️ "` and color it via
`DesignSystem.warningColor(for:)`, per-row, and that stays unchanged in this task. Only the
redundant widget-level aggregate banner is cut — the time it used to show now lives in the
header instead.

- [ ] **Step 2: Add the weather-tile computed properties and view helpers**

Add these new computed properties and methods to `ShortlistWidgetView` (anywhere inside the
struct, e.g. directly below `regionHeader`):

```swift
    private var sevenDayAverage: WeatherSnapshot? {
        WeatherSnapshot.derive(regionId: entry.region.id, from: entry.dailyWeather, windowDays: 7, asOf: entry.date)
    }

    private var todayWeather: DailyWeather? {
        entry.dailyWeather.first { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
    }

    private var temperatureHeadline: String {
        guard let todayWeather else { return "—" }
        return "\(Int(todayWeather.minTempC.rounded()))° / \(Int(todayWeather.maxTempC.rounded()))°"
    }

    private var temperatureSubline: String? {
        guard let sevenDayAverage else { return nil }
        return "Týždenný priemer: \(Int(sevenDayAverage.averageTempLast10DaysC.rounded()))°C"
    }

    private var upcomingRainEvent: RainEvent? {
        UpcomingRainDetector.nextTriggerEvent(in: entry.dailyWeather, asOf: entry.date)
    }

    private var lastRainfall: (date: Date, precipitationMm: Double)? {
        MostRecentRainfall.find(in: entry.dailyWeather, asOf: entry.date)
    }

    private func daysBetween(_ from: Date, _ to: Date) -> Int {
        max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from), to: Calendar.current.startOfDay(for: to)).day ?? 1)
    }

    private var rainHeadline: String {
        if let event = upcomingRainEvent {
            return "O \(daysBetween(entry.date, event.date)) dní · \(String(format: "%.0f", event.precipitationMm)) mm"
        }
        if let last = lastRainfall {
            return "Naposledy pred \(daysBetween(last.date, entry.date)) dňami"
        }
        return "Bez výraznejšieho dažďa"
    }

    private var rainSubline: String? {
        guard let last = lastRainfall else { return nil }
        if upcomingRainEvent != nil {
            return "Naposledy pred \(daysBetween(last.date, entry.date)) dňami · \(String(format: "%.0f", last.precipitationMm)) mm"
        }
        return "\(String(format: "%.0f", last.precipitationMm)) mm"
    }

    /// `.systemSmall`'s weather band — circle-badge-plus-text, full-width. See this task's
    /// note above: this is this plan's own synthesis, not spec-verbatim code.
    private func infoBand(icon: some Shape, color: Color, headline: String, subline: String?) -> some View {
        HStack(spacing: DesignSystem.spacingSmall) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.22))
                    .frame(width: 26, height: 26)
                icon
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 14, height: 14)
            }
            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                Text(headline)
                    .font(.system(size: DesignSystem.captionSize * 0.8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                if let subline {
                    Text(subline)
                        .font(.system(size: DesignSystem.captionSize * 0.6))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35)
                .stroke(color.opacity(0.4), lineWidth: 1)
        )
    }

    private func squareTile(icon: some Shape, color: Color, headline: String, subline: String?) -> some View {
        VStack(spacing: 1) {
            icon
                .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .frame(width: 12, height: 12)
                .frame(width: 22, height: 22)
                .background(Circle().fill(color.opacity(0.25)))
            Text(headline)
                .font(.system(size: DesignSystem.captionSize * 0.65, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.cloud)
            if let subline {
                Text(subline)
                    .font(.system(size: DesignSystem.captionSize * 0.5))
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(6)
        .background(color.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35)
                .stroke(color.opacity(0.45), lineWidth: 1)
        )
    }

    private var weatherTileRow: some View {
        HStack(spacing: 6) {
            squareTile(icon: SunriseShape(), color: DesignSystem.Colors.caution, headline: temperatureHeadline, subline: temperatureSubline)
            squareTile(icon: DropletShape(), color: DesignSystem.Colors.water, headline: rainHeadline, subline: rainSubline)
        }
    }
```

- [ ] **Step 3: Add the podium/ranked-row helpers for `.systemLarge`**

Add these two new methods (e.g. directly below the existing `heroRow(for:)` method, which you'll
remove in Step 4):

```swift
    private func podiumSquare(rank: Int, signal: SpeciesSignal, isFirst: Bool) -> some View {
        let hasWarning = signal.species.edibility != .edible
        let color = hasWarning ? DesignSystem.warningColor(for: signal.species.edibility) : DesignSystem.Colors.mossAccent
        return VStack(spacing: 2) {
            MushroomShape()
                .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                .frame(width: isFirst ? 30 : 22, height: isFirst ? 30 : 22)
            Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                .font(.system(size: isFirst ? DesignSystem.captionSize * 0.7 : DesignSystem.captionSize * 0.6, weight: .bold))
                .foregroundStyle(hasWarning ? color : DesignSystem.Colors.cloud)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(String(repeating: "●", count: max(0, min(4, signal.score))) + String(repeating: "○", count: 4 - max(0, min(4, signal.score))))
                .font(.system(size: DesignSystem.captionSize * 0.5))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background((hasWarning ? color : DesignSystem.Colors.mossAccent).opacity(isFirst ? 0.26 : 0.16))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius * 0.35)
                .stroke((hasWarning ? color : DesignSystem.Colors.mossAccent).opacity(isFirst ? 0.6 : 0.4), lineWidth: 1)
        )
    }

    private func rankedRow(rank: Int, signal: SpeciesSignal) -> some View {
        let hasWarning = signal.species.edibility != .edible
        let color = hasWarning ? DesignSystem.warningColor(for: signal.species.edibility) : DesignSystem.Colors.cloud
        return HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: DesignSystem.captionSize * 0.55))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.4))
                .frame(width: 14, alignment: .trailing)
            Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                .font(.system(size: DesignSystem.captionSize * 0.7, weight: .semibold))
                .foregroundStyle(color)
            Spacer()
            Text(String(repeating: "●", count: max(0, min(4, signal.score))) + String(repeating: "○", count: 4 - max(0, min(4, signal.score))))
                .font(.system(size: DesignSystem.captionSize * 0.55))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
    }
```

- [ ] **Step 4: Rewrite `smallBody`, `mediumBody`, `largeBody`, and delete `heroRow`**

Replace:

```swift
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
            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals, id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.bodySize, weight: .semibold), showLatin: false, inlineLatin: true)
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
```

with:

```swift
    private var smallBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            regionHeader
            infoBand(icon: SunriseShape(), color: DesignSystem.Colors.caution, headline: temperatureHeadline, subline: temperatureSubline)
            infoBand(icon: DropletShape(), color: DesignSystem.Colors.water, headline: rainHeadline, subline: rainSubline)
            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals.prefix(4), id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.bodySize, weight: .semibold), showLatin: false)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
        }
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            regionHeader
            weatherTileRow
            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals.prefix(4), id: \.species.id) { signal in
                    row(for: signal, nameFont: .system(size: DesignSystem.bodySize, weight: .semibold), showLatin: false, inlineLatin: true)
                }
                emptyStateIfNeeded
            }
            Spacer(minLength: 0)
        }
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
            regionHeader
            weatherTileRow
            if entry.signals.isEmpty {
                emptyStateIfNeeded
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(entry.signals.prefix(3).enumerated()), id: \.element.species.id) { index, signal in
                        podiumSquare(rank: index + 1, signal: signal, isFirst: index == 0)
                    }
                }
                VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                    ForEach(Array(entry.signals.dropFirst(3).prefix(6).enumerated()), id: \.element.species.id) { index, signal in
                        rankedRow(rank: index + 4, signal: signal)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
```

Then delete the now-unused `heroRow(for:)` method entirely:

```swift
    private func heroRow(for signal: SpeciesSignal) -> some View {
        let clampedScore = max(0, min(4, signal.score))
        let hasWarning = signal.species.edibility != .edible
        let warningColor = DesignSystem.warningColor(for: signal.species.edibility)
        return VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            Text((hasWarning ? "⚠️ " : "") + signal.species.commonNameSk)
                .font(.system(size: DesignSystem.heroSize, weight: .bold))
                .foregroundStyle(hasWarning ? warningColor : DesignSystem.Colors.cloud)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(signal.species.latinName)
                .font(.system(size: DesignSystem.bodySize).italic())
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 4 - clampedScore))
                .font(.system(size: DesignSystem.titleSize))
                .foregroundStyle(DesignSystem.Colors.mossAccent)
        }
    }
```

`row(for:nameFont:showLatin:inlineLatin:)` and `emptyStateIfNeeded` are unchanged and still used
— do not modify or remove them.

- [ ] **Step 5: Replace the 3 `#Preview` blocks' `dailyWeather: []` with realistic sample data**

Add this new private helper near `previewSignal` (bottom of the file, outside the `struct`):

```swift
private func previewDailyWeather() -> [DailyWeather] {
    let now = Date()
    var days: [DailyWeather] = (-9...0).map { offset in
        DailyWeather(
            date: now.addingTimeInterval(Double(offset) * 86400),
            meanTempC: 18,
            maxTempC: offset == -3 ? 22 : 20,
            minTempC: 12,
            precipitationMm: offset == -3 ? 6 : 0,
            humidityPercent: 68
        )
    }
    // A forecast day 2 days out that qualifies FlushTriggerDetector's threshold
    // (maxTempC >= 26, precipitationMm >= 5) — exercises the upcoming-rain headline/subline.
    days.append(DailyWeather(date: now.addingTimeInterval(2 * 86400), meanTempC: 24, maxTempC: 27, minTempC: 19, precipitationMm: 8, humidityPercent: 75))
    return days
}
```

Then replace each `#Preview`'s `dailyWeather: []` with `dailyWeather: previewDailyWeather()`:

```swift
#Preview("Small", as: .systemSmall) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: previewDailyWeather())
}

#Preview("Medium", as: .systemMedium) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 3),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: previewDailyWeather())
}

#Preview("Large", as: .systemLarge) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [
        previewSignal(name: "Hríb dubový", latin: "Boletus reticulatus", edibility: .edible, score: 4),
        previewSignal(name: "Kuriatko jedlé", latin: "Cantharellus cibarius", edibility: .edible, score: 2),
        previewSignal(name: "Plávka zelenkastá", latin: "Russula virescens", edibility: .caution, score: 2),
        previewSignal(name: "Muchotrávka tigrovaná", latin: "Amanita pantherina", edibility: .poisonous, score: 1)
    ], dailyWeather: previewDailyWeather())
}
```

- [ ] **Step 6: Build**

```bash
xcodegen generate
xcodebuild build -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData
```

Expected: builds clean — this is the strongest available automated signal on this task (see
Global Constraints on the lack of View-level test infrastructure).

- [ ] **Step 7: Visual verification**

Open `MushroomSignalWidget/ShortlistWidgetView.swift` in Xcode and use the `#Preview` canvas
(⌥⌘P or the Editor > Canvas menu) to render all 3 `#Preview` blocks ("Small", "Medium",
"Large"). Confirm, by actually looking at each:
1. The header shows the region name and a `"d. MMMM · HH:mm"`-formatted date/time, centered,
   with no footer/banner below the species list.
2. Small shows two full-width weather bands (temperature above rain) with a badge, headline,
   and (temperature only, since the preview data has no last-rain-only state) subline.
3. Medium and Large show the two weather tiles side-by-side as squares, not stretched.
4. Large shows a 3-square podium row (rank 1 visibly larger than ranks 2-3) followed by
   numbered rows 4-6 below it (the preview's 4-signal sample list means only 1 ranked row
   actually renders — confirm it renders correctly at that count, not that there are exactly 6).
5. No `DropletShape`/`SunriseShape`/`MushroomShape` renders as a blank/missing shape (would
   indicate a broken `Task 1` migration).

This project has a pre-existing widget-gallery visibility bug (see Global Constraints) — do not
attempt to add the widget to the live desktop gallery as a verification step; the Xcode canvas
renders the real `ShortlistWidgetView` struct directly and does not depend on widget
registration.

- [ ] **Step 8: Run the full test suite (regression check)**

```bash
swift test --package-path MushroomSignalCore
xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData
```

Expected: Core suite green (169, unchanged), app suite green (20, unchanged).

- [ ] **Step 9: Commit**

```bash
git status --short MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
# if either shows modified, run: git checkout -- MushroomSignal/Info.plist MushroomSignalWidget/Info.plist
git add MushroomSignalWidget/ShortlistWidgetView.swift
git commit -m "feat: widget region header, weather tiles, and species list redesign"
```
