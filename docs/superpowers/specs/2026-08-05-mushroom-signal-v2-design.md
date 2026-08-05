# Mushroom Signal v2 — Interactive Map & Species Library

## Relationship to v1

v1 (MVP, already merged to `main`) shipped a small-family widget, a companion app with a region picker, a full species shortlist, and a schematic 8-kraj heat-map grid. This spec is additive on top of that — it replaces the schematic map with a real interactive one, adds a species library, expands the widget to more sizes, and fixes one confirmed bug. Nothing here changes the shortlist tab, the region-picker mechanism, the signal-scoring algorithm, or the species dataset schema.

## Goals

1. Replace the schematic 8-kraj grid with a real, pannable/zoomable MapKit map of Slovakia, showing a fine-grained heat overlay (~30-50 weather sample points, one batched Open-Meteo request).
2. Add a species library (all 27 species) combined into the map screen — browsable in a customizable grid, each species toggleable on/off the map's heat layer, with best-effort photos and attribution.
3. Expand the widget to support small/medium/large families (native macOS drag-resize) with legible, size-appropriate fonts, fixing the current small widget's cramped 8-11pt text.
4. Fix the confirmed bug where the widget doesn't refresh when the selected region changes in the companion app.

## Out of Scope

- Historical/time-based mushroom activity views (Alexander's idea, explicitly deferred to a future round).
- A survey-grade Slovakia border polygon — a bounding-box + rough-shape filter is acceptable for a visualization tool that doesn't make legal/geographic claims.
- Any change to how region selection drives the shortlist/widget — stays exclusively via the existing dropdown picker (`RegionPickerView`).
- Any change to the shortlist tab, the signal-scoring algorithm, or `species.json`'s existing schema.
- A full identification "atlas" (long-form descriptions, multiple photo angles per growth stage, etc.) — the library stays to name + up to 3 photos + the data already in `Species`, per the "not Wikipedia" framing from brainstorming.

## 1. Weather Grid & Batched Fetching

Generate roughly 30-50 lat/lon sample points across Slovakia, derived from its bounding box (approx. lat 47.7–49.6, lon 16.8–22.6) filtered to a rough approximation of the country's shape — precision isn't critical since these points only drive a visualization, not an authoritative boundary claim. Exact filter shape is an implementation-time detail (see Open Questions).

**New data model:**

```swift
public struct GridPoint: Identifiable, Hashable, Sendable {
    public let id: String       // e.g. "grid-07"
    public let latitude: Double
    public let longitude: Double
}
```

**New `WeatherClient` capability — batched fetch**, since firing 30-50 separate HTTP requests per map refresh would be wasteful. Confirmed during brainstorming: Open-Meteo supports comma-separated multi-location queries (`&latitude=48.1,49.2&longitude=17.1,18.7`), returning a JSON **array** of per-location results in the same order as the input — a different top-level shape than the existing single-location object response, so this needs its own response-decoding path, not a reuse of the existing one.

```swift
public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]  // keyed by GridPoint.id
}
```

`OpenMeteoClient` implements the new method with one HTTP request for the whole grid.

## 2. Heat Rendering — Dominant-Species Mosaic

For each grid point, given the set of "active" (toggled-on-in-the-library) species, compute each active species' score at that point by reusing the existing `SignalAlgorithm.computeSignal` — same scoring logic as the shortlist and v1's map, no new algorithm. The point's rendered color is whichever active species scores highest there (ties broken the same way `ShortlistRanker` already breaks them — edibility then name). If every active species scores 0 at a point, render it dimmed/neutral rather than a strong color, so the map never implies a false positive.

Rendered via native MapKit (`Map` + `MapCircle` or a lightweight custom `Annotation` per grid point) — this was chosen over a web-embedded map (Windy-style) specifically because it's native, needs no API key, and fits the app's "modern lightweight" framing better than a `WKWebView` wrapping a website.

**Color assignment:** active species get a color assigned in toggle-on order from a small, curated, visually distinct palette (extends `DesignSystem` — see §4). A compact legend on-screen shows which color currently maps to which species. This is the "dominant mosaic" approach chosen during brainstorming specifically because it stays legible regardless of how many species are active — the alternative (alpha-blended overlapping glows) was rejected because it turns muddy past 2-3 simultaneous species.

## 3. Species Library

Reuses the existing `Species` data as-is (name, Latin name, edibility, habitat, fruiting months, lookalikes) — no schema changes to `species.json`. Adds a photo layer as a **separate** bundled resource, since photo curation (Alexander manually reviewing/correcting all 27 entries, adding photos over time) is an ongoing, independent task from the core scoring dataset:

```swift
public struct SpeciesPhoto: Codable, Identifiable, Sendable {
    public let id: String
    public let speciesId: String
    public let imageURL: URL     // Wikimedia Commons direct image URL
    public let photographer: String
    public let license: String   // e.g. "CC BY-SA 4.0" or "CC0"
    public let sourceURL: URL    // Commons file page, for attribution link
}
```

Stored in a new `species-photos.json`, 0-3 entries per species id. Photos are **not bundled as local assets** — they're fetched live via `AsyncImage` from the stored Commons URL, keeping the app bundle small and the dataset easy to extend. A missing/failed-to-load photo shows a neutral placeholder; this is explicitly best-effort, not a completeness requirement, since the app isn't being distributed.

**UI — combined into the map screen** (per brainstorming decision, not a separate tab): a `LazyVGrid` of species cards, column count adjustable via a simple stepper/segmented control (2-4 columns, defaulting to 3×3) since that's cheap to make adjustable rather than hardcoded. Each card: common name + first photo (or placeholder) + a visual toggle state showing whether it's currently active on the map. Tapping a card toggles its map layer on/off. A secondary affordance (small "i" button or long-press) opens a detail view with the full picture — all photos, edibility, habitat, lookalikes — since a grid cell can't show everything.

**Attribution:** a small "Photo Credits" view listing photographer, license, and source link for every photo currently in use, satisfying Wikimedia Commons' "reasonable to the medium" attribution requirement without requiring the app itself to become CC-BY-SA (displaying an unmodified photo is not a derivative work under that license).

## 4. Design System — Typography Tokens

`DesignSystem` currently has no font-size tokens (flagged as a deferred minor during v1's final review) — widget/app views use raw literal sizes. Since three widget families each need a coherent, distinct font scale, this is the natural point to add them: a small typography scale (e.g. `.captionSize`, `.bodySize`, `.titleSize`, `.heroSize`) following the same golden-ratio relationship already used for spacing, rather than each view inventing its own numbers.

Also extends `DesignSystem.Colors` with a small curated accent palette for species-map coloring (distinct hues, chosen to read clearly against the existing forest-green map background) — exact values are an implementation-time detail.

## 5. Widget Family Expansion

`MushroomSignalWidget.supportedFamilies` grows from `[.systemSmall]` to `[.systemSmall, .systemMedium, .systemLarge]` — this is what actually delivers "resizable, like the classical ones": native WidgetKit widgets are drag-resizable between supported families in macOS's Edit Widgets mode.

`ShortlistWidgetView` branches on `@Environment(\.widgetFamily)`:
- **Small** (current size): ranked shortlist, fonts bumped to the largest size that honestly fits without truncation/overlap (roughly `.bodySize` for names) — this directly addresses "currently it's unreadable," within the real constraints of a ~155×155pt card.
- **Medium**: same ranked list with more horizontal room — Latin name as a subtitle per row becomes legible, names at `.titleSize`.
- **Large**: full shortlist with generous spacing, names at `.heroSize`, and the #1-ranked species gets prominent "hero" treatment (similar in spirit to Apple Weather's large current-temperature display).

The existing poisonous-species labeling and score-clamping (already fixed in v1's final review) carry through unchanged to all three sizes — same underlying row logic, just re-laid-out per family.

## 6. Widget Region-Sync Fix

`AppState.selectRegion(_:)` currently persists the new region to `RegionStore` and refreshes the app's own `AppState`, but never tells the widget extension its data is stale — it waits for the next scheduled 12-hour timeline refresh. Fix: call `WidgetCenter.shared.reloadAllTimelines()` immediately after persisting the region change, forcing WidgetKit to recompute now.

## Testing

- `GridPoint` generation (bounding-box + filter): unit test that point count lands in the ~30-50 range and every point falls within the bounding box.
- `OpenMeteoClient.fetchSnapshots(for:)`: unit test with a mocked multi-location JSON array response (same `MockURLProtocol` pattern as v1), verifying correct order-preserving mapping back to grid-point ids.
- Dominant-species-per-point selection: pure function, unit-testable — given a set of per-species scores at a point, returns the correct highest scorer, correctly falls back to "neutral" when everything is 0, and correctly applies the existing edibility/name tie-break.
- `SpeciesPhoto` decoding: unit test with a small fixture JSON, including the zero-photos case.
- Widget family layouts and the map/library screen: SwiftUI views, verified via build + Xcode previews per family (same approach as v1 — no meaningful unit-test surface for pure layout).

## Open Questions for the Implementation Plan

- Exact bounding-box filter shape for Slovakia — a simple polygon approximation is fine to start; refine only if grid points visibly land in neighboring countries during manual testing.
- Exact accent color values for the species palette and the new typography scale's point sizes — decided during implementation to stay visually consistent with the existing forest palette, not frozen here.
- Whether the library needs a "favorites" quick-toggle for frequently-checked species — not requested during brainstorming; flag only if it comes up, don't build speculatively.
