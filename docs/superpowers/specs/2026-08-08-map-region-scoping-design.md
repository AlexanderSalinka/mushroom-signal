# Mushroom Signal — Region-Scoped Map & Tab Restructuring

## Relationship to prior specs

This supersedes **§5 ("Map — Per-Kraj Shaped Overlay")** of
`2026-08-08-ui-visual-redesign-design.md`. That section's core idea — hand-approximated
kraj polygon shapes, already implemented in `RegionBoundaries.swift` (Task 10, committed) —
is unchanged and fully reused. What changes: instead of computing a dominant species
independently for all 8 regions and filling all 8 with color, this design computes it only
for the currently-selected region and fills only that one; the other 7 stay border-only,
always.

This also extends that spec's scope in a way it didn't anticipate: a 3rd tab
("Knižnica druhov"), splitting what was previously the combined "Mapa" screen (map +
species library stacked in one scroll view) into two separate tabs.

Everything else in the original spec — §1 shared card, §2 adaptive grid, §3 photo sourcing,
§4 photo cache, §6 typography floor — is unchanged by this doc.

## Why

After building a throwaway visual preview of Task 10's polygon shapes directly in the
running app (all 8 filled with flat colors, no real weather logic), Alexander determined
the "all 8 filled" concept wasn't right: the species highlight answers "where should I go
hunt this species," which is inherently a single-region question, not a whole-country
comparison. He also wants species toggling relocated to its own tab now that species cards
are getting bigger and more visual (per the original spec's Tasks 7-9), rather than stacked
awkwardly below the map in a scroll view.

## Goals

1. Split the current combined "Mapa" screen into two tabs: **Mapa** (map only) and
   **Knižnica druhov** (species picker only), sharing one `MapScreenState`.
2. Make the app's existing single region selection (toolbar `RegionPickerView`, already
   driving Zoznam) also drive the map — one selection, three tabs.
3. Redesign the map's visual model: all 8 kraj borders always visible as context, only the
   selected kraj fills with the dominant active-species color.
4. Simplify `MapScreenState`'s weather-fetching to a single-region fetch, removing the need
   for batched multi-point fetching entirely.

## Out of Scope

- Any change to `SpeciesLibraryView`'s own internal behavior — still all 27 species,
  tap-to-toggle-active, the "i" info button opening `SpeciesDetailView` — only its tab
  location changes.
- Any change to `RegionBoundaries`'s polygon data itself (Task 10, already committed) —
  reused as-is for the always-visible borders.
- Tapping a kraj shape on the map to change the selected region — the toolbar picker
  remains the single source of truth; the map is read-only display. (A real future idea,
  captured in `FUTURE_IDEAS.md`, not this pass.)
- Auto-zooming the camera to the selected kraj — the camera stays fixed on all of Slovakia
  regardless of selection.
- Everything already covered by the original 2026-08-08 UI visual redesign spec (§1-4, §6),
  which this doc doesn't touch.

## Design

### 1. Tab restructuring

- `ContentView`'s `TabView` gains a 3rd tab: Zoznam / Mapa / Knižnica druhov.
- `MapScreenState` moves from `MapScreenView`'s own `@StateObject` up to `ContentView`'s
  `@StateObject` (the same pattern already used for `AppState`), passed down to both the
  now-map-only `MapScreenView` and a promoted `SpeciesLibraryView` tab destination.
- `MapScreenView` shrinks to just `InteractiveMapView` — no more embedded
  `SpeciesLibraryView`/`ScrollView` stacking.

### 2. Shared region selection

- `MapScreenState` gains awareness of the app's currently-selected `Region` — the same
  source `AppState` already reads from. Exact plumbing (constructor injection vs.
  `@EnvironmentObject` vs. something else) is an implementation-time decision, not frozen
  here.
- When the selected region changes, `MapScreenState` **clears any existing fill state
  immediately** — no stale-region color shown even briefly — and refetches that region's
  weather. This was a deliberate call: leaving the old fill visible during the refetch would
  show the wrong region's color, which is actively misleading, not just slow.

### 3. Map visual model

- All 8 `RegionBoundaries` polygons render as outline-only borders, always, regardless of
  selection or active species — permanent context, not conditional.
- The single selected kraj's polygon additionally fills with the dominant active-species
  color when: (a) at least one species is toggled active, and (b) `DominantSpeciesResolver`
  resolves a non-nil dominant species for that region's current weather. Otherwise: border
  only, same as the other 7.
- Camera position is fixed, showing all of Slovakia at all times — selection changes which
  kraj is filled, never what's in view. (Explicitly decided against auto-zoom, to keep the
  map feeling like one consistent, low-key national view rather than jumping around.)

### 4. Weather-fetching simplification

- Replaces the original spec §5's design (`fetchSnapshots(for: [GridPoint])` fed 8
  region-derived points) with a single `weatherClient.fetchSnapshot(for: Region)` call — the
  exact same method `AppState` already uses for Zoznam. No batched multi-point fetch is
  needed for the map at all anymore.
- This makes `GridPoint` and `WeatherClient.fetchSnapshots(for: [GridPoint])` (the batched
  method) fully unused — not just `SlovakiaGrid`, as the original spec concluded. All three
  become removable dead code once this lands, since nothing samples multiple points anymore.

## Testing

- `MapScreenState`'s region-driven refetch and immediate-clear-on-switch behavior:
  unit-testable with the existing mocked-`WeatherClient` pattern already used in
  `MapScreenStateTests.swift` — assert that changing the selected region clears the
  previous fill state before the new fetch resolves, and that the new fetch calls the
  single-region method with the new region's coordinates.
- Map polygon rendering (borders always, fill only on selection + active species + non-nil
  dominant species): build + manual visual check, same convention as all prior map UI work
  in this project — no meaningful unit-test surface for the SwiftUI rendering itself.
- Tab restructuring: build + manual check that both new tabs render correctly and share
  live state (toggling a species in Knižnica druhov visibly changes Mapa's fill).

## Open Questions for the Implementation Plan

- Exact plumbing for "`MapScreenState` knows the selected region" — constructor parameter
  updated by `ContentView`, `@EnvironmentObject`, or something else — implementation-time
  decision.
- Whether `MapScreenStateTests.swift`'s existing tests (`testLoadGridPopulatesSnapshotsOnSuccess`,
  etc.) get renamed/rewritten or need entirely new tests reflecting the single-region model
  — likely a substantial rewrite given `loadGrid()`/`gridPoints` disappear entirely under
  this design.
- Naming/icon (SF Symbol) for the new "Knižnica druhov" tab — small implementation-time
  detail.
