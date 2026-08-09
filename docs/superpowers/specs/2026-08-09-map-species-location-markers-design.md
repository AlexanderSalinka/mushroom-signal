# Mushroom Signal — Map Species-Location Markers

## Relationship to prior specs

This supersedes the map-visualization portions of `2026-08-08-map-region-scoping-design.md`
(§3 "Map visual model" and its "single selected kraj fills with color" design) — that design
was never actually implemented; the map today only renders always-visible kraj border
outlines (`RegionBoundaries`, Task 10 of `2026-08-08-ui-visual-redesign.md`, committed) with
no fill and no per-point rendering. This spec replaces "fill the map with color" entirely
with a different visual model: small per-point markers, not region fill.

The 3-tab split and "`MapScreenState` learns the toolbar-selected region" portions of that
same spec are **not** addressed here — out of scope, unrelated to this feature. `MapScreenView`
still combines the map, the resize handle (added 2026-08-09), and the species library grid in
one screen; this spec doesn't change that structure.

## Why

`MapScreenState` already has `gridPoints` (from `SlovakiaGrid`, currently 39 points),
`activeSpeciesOrder`, `speciesColors`, and `dominantSpecies(at:)` — all live and fetching real
weather data via `loadGrid()`. None of it is drawn on the map today; it only feeds a text
legend in the corner ("Hríb dubový — [orange dot]") with no visual counterpart on the map
itself. Alexander wants this machinery finished: an actual on-map indicator of where each
species toggled active in "Knižnica druhov" is likely to be found, reusing the app's existing
`●●○○` prognosis-dot visual language (already on every species card) instead of inventing a
new visual language or a solid region fill (rejected — the kraj polygon edges are jagged
enough that filling them would look worse, not better; see Out of Scope).

## Goals

1. Render a marker at a subset of `SlovakiaGrid` points, showing a small `●●○○`-style dot
   cluster colored by whichever active species dominates at that point.
2. Coarsen `SlovakiaGrid`'s spacing so the grid stays visually restrained — a prior attempt at
   this kind of overlay used a "very very crazy" radius/density and looked bad; this pass must
   not repeat that.
3. Extract the existing dot-cluster rendering (currently inlined in `SpeciesCardView`) into a
   small shared view, so the card and the new map marker draw the identical glyph via one
   implementation, just parameterized by size and color.
4. Leave the existing species-color legend as-is — it already explains what each color means
   and stays useful once markers use the same colors.

## Out of Scope

- **Redrawing the kraj boundary polygons for smoother edges.** Real, agreed issue (jagged,
  "broken glass") — explicitly deferred as a follow-up, not this pass. Borders render exactly
  as they do today.
- **Filling kraj regions with solid color.** Considered and rejected in favor of point
  markers, specifically because the jagged edges would be more visible filled than as an
  outline.
- **Tap interaction on markers** (e.g. a popover with species detail). The map stays read-only
  display, consistent with the existing convention (species interaction happens via the
  card grid below, not the map itself).
- **The 3-tab split / toolbar-region-awareness** from the superseded spec. Unrelated to this
  feature; `MapScreenView`'s current single-screen structure is unchanged.
- **Changing `SignalPipeline`, `SignalAlgorithm`, or ranking/scoring logic.** The marker reuses
  the exact same scoring already used for the legend and the shortlist — no new algorithm.
- **Widget changes.** Unrelated (see cancelled Task 3 of the UI visual redesign plan).

## Design

### 1. Coarsen `SlovakiaGrid`

Current constants (`MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift`):
`latitudeStep = 0.4`, `longitudeStep = 0.6` → **39 points** after the diamond-silhouette trim
(confirmed by running the generation logic against the current constants).

New constants: `latitudeStep = 0.8`, `longitudeStep = 1.2` → **11 points** (confirmed the same
way). Roughly a 3.5x reduction — restrained, evenly spread across the country, not a swarm.
Everything else about `SlovakiaGrid` (bounding box, diamond-trim threshold, `GridPoint` output)
is unchanged.

### 2. Extract `ScoreDotsView`

New shared view (`MushroomSignal/Views/ScoreDotsView.swift`):

```swift
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

`SpeciesCardView` replaces its inlined score-dots `Text` with
`ScoreDotsView(score: signal.score, color: DesignSystem.Colors.mossAccent, dotSize: DesignSystem.captionSize)`
— identical rendered output, same clamping behavior, no visual change to existing cards.

### 3. `MapScreenState` exposes score, not just the winning species

`dominantSpecies(at:) -> Species?` is replaced with:

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

(`DominantSpeciesResolver` becomes unused once this lands — its one production call site
(`MapScreenState.dominantSpecies`) moves inline here, since the enum wrapper added no value
beyond calling `SignalPipeline` directly. Confirmed its only references elsewhere are two
doc-comment mentions, in `SignalPipeline.swift` and `SignalPipelineTests.swift` — plus its own
dedicated `MushroomSignalCoreTests/DominantSpeciesResolverTests.swift` (43 lines), which must
be deleted alongside `DominantSpeciesResolver.swift` itself, not just left to fail. Reword the
two doc-comment mentions rather than leave them pointing at a deleted type.) This exposes
`SpeciesSignal.score` (0-4, already
clamped by `ScoreDotsView`) alongside the species — nothing else about the scoring changes.
`nil` behavior is identical to today: no snapshot, no active species, or a resolved score of 0
all produce no marker, matching the existing "nothing rendered" convention used for kraj fills
in the superseded spec.

`MapScreenStateTests.swift`'s `testDominantSpeciesReturnsNilWithNoActiveSpecies` and
`testDominantSpeciesReturnsNilWhenSnapshotMissing` get rewritten against `dominantSignal`,
same assertions (nil in, nil out), same two triggering conditions.

### 4. Render markers on the map

In `InteractiveMapView`, alongside the existing kraj-border `ForEach`, a new `ForEach` over
`mapState.gridPoints`:

```swift
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
```

`Annotation` renders at a fixed screen size regardless of map zoom — unlike `MapCircle`, whose
geographic radius is what made the prior attempt look oversized at some zoom levels. This
isn't just "pick smaller numbers," it's a different rendering primitive that can't develop the
same problem. New `DesignSystem` token, added next to `legendDotSize` in
`DesignSystem.swift`, same `Double` type as every other token in that file:

```swift
/// Score-dot glyph size inside a map marker — a decorative map-icon scale, matching the
/// precedent set by `legendDotSize`. Not subject to the 20pt body-text floor, which governs
/// readable text, not small status glyphs.
public static let mapMarkerDotSize: Double = 6
```

The capsule background reuses the exact same treatment as the existing legend chip
(`forestDeep.opacity(0.85)`), so markers and legend read as one visual family.

### 5. Legend stays as-is

No change to `InteractiveMapView`'s `legend` computed property — it already shows exactly the
species→color mapping the markers now use, so it continues to explain the map at a glance.

## Testing

- `MapScreenStateTests.swift`: rewrite the two `dominantSpecies`-named tests against
  `dominantSignal`, asserting `nil` under the same two conditions (no snapshot, no active
  species) plus one new case — an active species whose resolved score is 0 also yields `nil`
  (mirrors `DominantSpeciesResolver`'s existing `top.score > 0` guard, now inlined).
- `SlovakiaGridTests.swift` already has `testGeneratePointCountLandsInExpectedRange`, currently
  asserting `30...50` — this must be updated to match the coarsened output (e.g. `8...16`),
  not left as-is, or it fails immediately after the constant change. The other two existing
  tests (`testEveryPointFallsWithinBoundingBox`, `testPointIDsAreUnique`) need no changes —
  neither depends on point count.
- `ScoreDotsView`: no dedicated unit test — it's a pure rendering view with the same
  `max(0, min(4, score))` clamp already implicitly covered by `SpeciesCardView`'s existing
  usage; a build + manual visual check (both the card and the new map markers) is this
  project's established convention for SwiftUI rendering correctness (see
  `2026-08-08-map-region-scoping-design.md`'s own Testing section for the same reasoning).
- Manual visual check (build + launch, same as every other map UI change in this project):
  confirm markers appear only at points with a resolved non-nil signal, colors match the
  legend, marker size stays small/fixed across zoom levels, and toggling species on/off in
  Knižnica druhov visibly updates the markers.

## Follow-up (not this pass)

- Redraw `RegionBoundaries`' hand-approximated kraj polygon coordinates so the border outlines
  stop looking jagged ("broken glass"). Alexander confirmed this will happen in a future pass.
