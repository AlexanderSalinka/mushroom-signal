# Mushroom Signal — UI Visual Redesign: Cards, Photos, Map Regions

## Relationship to prior specs

v1/v2 (merged) shipped the widget, companion app, shortlist, region picker, the interactive
map's grid-of-circles heat overlay, and the species library grid. The 2026-08-07 scoring
intelligence pass (merged) redesigned the algorithm underneath all of that — this spec
doesn't touch scoring at all, it's purely visual/structural: how species are displayed and
how the map represents regions.

This spec supersedes `2026-08-07-ui-redesign-working-notes.md` (marked below), which
captured the same ground mid-brainstorm before the map reference image and the color-mixing
diagnosis. Nothing here contradicts those notes — this is the completed version.

## Goals

1. Replace Zoznam's vertical list and the species library's small-thumbnail grid with one
   shared, photo-forward card component — big enough to feel like a real visual (not a data
   row), consistent everywhere it appears.
2. Make that grid genuinely responsive — column count follows the app window's actual width,
   not a manual stepper.
3. Unify navigation: tapping a species card anywhere always reaches the same detail view.
4. Give species real photos (currently zero — the v2 photo system was built but never
   populated) for edible species specifically, cached locally so the app works offline and
   loads instantly after first fetch.
5. Replace the map's ~39-point circle grid with one solid shape per kraj (8 regions),
   matching Slovakia's real administrative boundaries closely enough to read correctly —
   approximate for now, precise later. This is also the fix for tonight's diagnosed
   "colors look muddy/mixed" complaint (see §5's Context).
6. Raise the app's typography floor to a minimum 20pt everywhere (added 2026-08-08) — an
   app-wide legibility change, not scoped to just the new card/grid UI (see §6).

## Out of Scope

- Exact, survey-grade kraj boundary geometry — approximate hand-drawn polygons are
  explicitly sanctioned for this pass (Alexander, 2026-08-07 night session, recorded in
  `CLAUDE.md`'s Project Conventions). Real GIS data (Natural Earth or Slovakia's own
  geoportal.sk, both cleanly licensed) is the named upgrade path for later, not now.
- Photos for `.caution`/`.poisonous` species — edible only, per explicit instruction
  ("nobody is looking for the poisonous mushroom"). Those keep the existing placeholder
  treatment.
- Cloud/remote photo storage — local-disk cache only, matching this app's zero-backend
  architecture (decided in the original v1 spec, reaffirmed tonight).
- Mapa's future "route planner / route discoverer" idea — mentioned in passing, no design
  intent yet, a separate future spec whenever Alexander wants to build it.
- Any change to `SpeciesSignal`, `computeSignal`, or the shortlist's underlying data — this
  is a view-layer and map-data-shape redesign only.
- The widget's card/grid/photo treatment — §1-4 (shared card, adaptive grid, photos, photo
  cache) are companion-app only (Zoznam/Mapa). The widget is back in scope for §6's
  typography floor specifically (confirmed by Alexander — see §6), and only that; it does
  not get the card-grid redesign, photos, or any other piece of this spec.

## 1. Shared `SpeciesCardView`

One card component, used by both the redesigned Zoznam grid and the existing species
library grid on Mapa — same visual identity everywhere a species is shown as a card.

**Size — a qualitative target, not an enforced dimension (revised 2026-08-08):** ~400×250pt
is a rough reference point, not a fixed size to lock in. The actual goal is "eye-catching but
not too big" — big enough to read as a real thumbnail, not a data-dense row, but not so large
that fewer than a comfortable number of cards fit on screen at once. The adaptive grid (§2)
already means card size flexes with available width regardless; this just clarifies that
400×250 shouldn't be treated as a strict minimum/maximum in the implementation, only a
starting point to judge "does this feel right" against. "YouTube thumbnail" reference: the
photo dominates the card, with information overlaid via a gradient scrim rather than sitting
in separate rows below it.

**Content, top to bottom via the scrim:**
- Photo fills the card (via the new `PhotoCache`, §3) — a neutral placeholder (existing
  `bark`-colored + photo-icon treatment from `SpeciesLibraryView`) when no photo exists,
  which includes every `.caution`/`.poisonous` species by design (§3).
- Common name (prominent) + Latin name (subtitle), both over the scrim.
- **Zoznam context only:** score dots (0-4, per the 2026-08-07 scoring pass) and the
  `reason` string, since that's the forecast information the shortlist exists to show.
- **Both contexts:** the existing edibility warning treatment (`DesignSystem.warningLabelSk`/
  `warningColor`) when applicable — `.caution`/`.poisonous` species keep their warning
  visible on the card itself, not hidden behind a tap.

**Tap behavior — same card, different primary action per context:**
- **Zoznam:** tapping a card opens `SpeciesDetailView` directly (existing view, reused
  as-is — no new detail UI to build).
- **Mapa's species library:** keeps its current behavior — tapping toggles the species
  active on the map's heat layer; the existing small "i" info-button overlay still opens
  `SpeciesDetailView` for that card. This preserves an already-working interaction rather
  than changing library semantics as a side effect of the visual redesign.

## 2. Adaptive Grid Layout

Both Zoznam and the species library switch from their current layouts (Zoznam: a
`ScrollView` of vertical rows; library: `LazyVGrid` with a manual 2-4 column `Stepper`) to
one shared adaptive grid — `LazyVGrid` with `GridItem(.adaptive(minimum: 400, maximum: ...))`
or equivalent, reflowing column count automatically as the app window is resized. Confirmed
with Alexander: the resize trigger is the standard macOS window resize (dragging the window
edge), not a custom gesture or panel.

The library's manual column-count `Stepper` is removed — adaptive reflow replaces its
purpose. (Resolved during implementation planning: removed, not kept alongside the adaptive
default.)

## 3. Photo Sourcing (Edible Species Only)

`species-photos.json` currently has **zero entries** — confirmed by inspection. The v2 spec
built the `SpeciesPhoto` model (`imageURL`, `photographer`, `license`, `sourceURL`) and the
`AsyncImage` wiring, but the actual curation pass was never done.

**Scope:** source real photos only for species where `edibility == .edible`. `.caution` and
`.poisonous` species get no photo — same placeholder treatment the library already uses for
missing photos.

**Source:** Wikimedia Commons, matching the existing `SpeciesPhoto` model exactly (it was
already designed around Commons' CC-licensed, attribution-trackable structure). Not scraped
from arbitrary sites — Commons explicitly licenses this use, same legal footing already
established for this project. Cross-reference each species' Latin name to find a real,
appropriately-licensed photo; populate `photographer`/`license`/`sourceURL` honestly for each
one (needed for the existing Photo Credits view from v2 to keep working correctly).

**Process:** a real research pass, similar in shape to the 2026-08-07 species-data
enrichment — likely one dedicated implementation task, not something to hand-write inline
in this spec (the actual photo URLs are the deliverable of doing the research, not
knowable in advance).

## 4. Local `PhotoCache`

**Confirmed with Alexander: download-once, cache-locally.** Not live-fetch-every-time
(today's behavior), not bundled-at-build-time, not cloud storage — this app has zero
backend by original design (v1 spec, reaffirmed tonight), and a cloud database would be
solving a problem that doesn't exist for a single-user local macOS app.

**Shape:** given a `SpeciesPhoto.imageURL`, check a local disk cache first (keyed by
species id or the URL itself); if absent, download and persist to disk, then serve from
disk on every subsequent load. Photos are static content — a species' representative photo
doesn't change — so no expiry/invalidation logic is needed, just a persistent cache.
Replaces direct `AsyncImage(url:)` calls in the card component with a caching equivalent
(a small custom view wrapping this logic, or `AsyncImage`'s own `urlSession:` customization
point if that proves sufficient — an implementation-time decision, not frozen here).

**Storage location:** the app's own local storage (e.g. `Application Support` or `Caches`)
is sufficient — this doesn't need App Group sharing with the widget, since photo display is
Zoznam/Mapa-only (companion app), not a widget concern.

**Resolved during implementation planning (2026-08-08):** cache key is a short digest of the
full URL plus the URL's last path component, stored under `Caches/SpeciesPhotos/` — collision-
resistant across sources without needing an external hashing dependency.

## 5. Map — Per-Kraj Shaped Overlay (replaces the grid-of-circles)

> **Superseded 2026-08-08** by `2026-08-08-map-region-scoping-design.md`, written after
> testing a throwaway preview of this section's "all 8 kraje filled" concept directly in the
> running app. The polygon shape data below (`RegionBoundaries.swift`, Task 10) is unchanged
> and fully reused — what changes is the fill logic: only the currently-selected region
> fills with the dominant-species color; the other 7 stay border-only, always. The new doc
> also folds in a tab restructuring (a separate "Knižnica druhov" tab) this section didn't
> anticipate. Kept below for history.

### Context: this is also the color-mixing fix

Diagnosed tonight, not guessed: the current map computes a dominant species independently
at ~39 grid points (`SlovakiaGrid.generate()`, spaced ~44km apart, each a `MapCircle` of
18km radius at 0.75 opacity). Real weather varies meaningfully over 44km, so neighboring
points can easily disagree on which species "wins," producing a noisy, salt-and-pepper
patchwork rather than a clean picture — which reads as "muddy/mixed colors" even though the
color-assignment logic itself (`SpeciesColorAssigner`, 8 distinct palette colors) is
correct. Moving to one color per kraj, computed once per region rather than sampled at many
independent points, removes the patchwork at the source rather than patching the symptom.

### Design

- Replace the `GridPoint`/`SlovakiaGrid`-based sampling with one polygon shape per `Region`
  (the app's existing 8-kraj model — no data-model change needed, this maps directly onto
  what already exists).
- Each kraj's fill color = the dominant active species computed from **that region's own**
  weather — reusing the existing single-coordinate-per-region fetch pattern already used
  for the shortlist (`WeatherClient.fetchSnapshot(for: region)`), not the batched
  multi-point fetch the grid currently uses. One weather lookup per kraj (8 total) instead
  of ~39 independent samples.
- Rendering: SwiftUI's `MapPolygon` (available at this app's macOS 14+ deployment target)
  instead of `MapCircle` — a real filled-shape overlay per kraj, sharing borders with
  neighbors rather than floating as separate circles with gaps between them.
- Neutral/dimmed rendering when no active species scores above 0 in a region — same
  principle the current implementation already uses, just applied per-kraj instead of
  per-point.

### Shape data — approximate for now, explicitly sanctioned

Hand-approximated polygon coordinates per kraj, aiming to roughly match real proportions
and adjacency (recognizable as Slovakia, boundaries roughly in the right place) without
needing precise GIS data. This is original approximate work, not derived from any external
dataset — deliberately sidesteps the licensing question entirely for this pass (a
promising-looking free GeoJSON source was found during brainstorming but has no stated
license, same risk category already flagged for `nahuby.sk` — not worth adopting for an
alpha that explicitly doesn't need precision yet).

**Upgrade path, later, not now:** Natural Earth (public domain, no attribution required) or
Slovakia's own official `geoportal.sk` open data, once real precision matters.

### Resolved during implementation planning (2026-08-08)

`GridPoint` and `WeatherClient.fetchSnapshots(for: [GridPoint])` are **not** removed — they
get reused, fed 8 region-derived points (one per kraj) instead of `SlovakiaGrid`'s ~39-point
fine grid. No `WeatherClient` protocol change needed. `SlovakiaGrid` itself (the
grid-generation logic) becomes genuinely dead code once nothing calls it, and is removed
(YAGNI) rather than kept unused — re-addable later if the undesigned future route-planner
idea actually needs point-based sampling again.

## 6. Global Typography Floor — Minimum 20pt

Added 2026-08-08, app-wide, not scoped to this spec's new UI specifically: every text
element should render at a minimum 20pt.

**What this touches:** `DesignSystem`'s existing golden-ratio typography scale
(`captionSize`≈8, `bodySize`≈12.9, `titleSize`≈20.9, `heroSize`≈33.9, from v2) sits well
below 20pt at its smaller steps, and several views use raw system font styles (`.caption`,
`.caption2`, `.subheadline`) directly rather than routing through `DesignSystem` at all —
per this project's own Hard Constraint that all styling should route through
`DesignSystem`, those are already a documented-but-unfixed gap this touches in passing.
Meeting a real 20pt floor means both revising `DesignSystem`'s own scale (or introducing an
explicit minimum derived from it) and auditing every view using raw system styles directly.

**Resolved during implementation planning (2026-08-08):** mechanically reapplying the
existing golden-ratio multiplier (1.618) from a 20pt floor would compound to `20 → 32.36 →
52.36 → 84.72`, an 84pt hero size — absurd in a widget whose hero row already renders at
`heroSize` today. The complaint was "too small to read," not "make the largest text much
larger too." Final values: `captionSize: 20, bodySize: 24, titleSize: 28, heroSize: 36` — a
gentler graduated progression that clears the floor without that blowup. Approved by
Alexander.

**Confirmed with Alexander: the whole app, including the widget** — the current text is
too small to read, full stop, not a preference to weigh against other constraints. This
means the WidgetKit extension's typography is back in scope for this pass, reopening
something that had been parked since 2026-08-07 ("focus on the app"). Worth being explicit
about the real cost this carries, not softened: the small widget family is only ~155×155pt
total, and its current layout already leans on `.minimumScaleFactor(0.8)` to fit three rows
of forecast text at sizes well under 20pt. A hard 20pt floor there is not a font-size
tweak — it very likely means the small (and possibly medium) family's layout needs
rethinking: fewer rows shown, a different information density, or a genuinely different
layout shape, not the same content just rendered bigger. That redesign work belongs in the
implementation plan as its own real task, not treated as a trivial side effect of raising a
number in `DesignSystem`.

## Testing

- `SpeciesCardView`: SwiftUI view, verified via build + Xcode previews per this project's
  established convention for pure layout — no meaningful unit-test surface.
- Adaptive grid reflow: same — visual/preview verification, not unit-testable.
- `PhotoCache`: unit-testable — given a mocked `URLSession` (same `MockURLProtocol` pattern
  already used for weather fetching), verify a cache-miss triggers a download-and-persist,
  and a cache-hit serves from disk without a second network call.
- Photo sourcing data: `SpeciesDataTests`-style validation — every `.edible` species has a
  photo entry, every entry decodes correctly, no `.caution`/`.poisonous` species has one.
- Per-kraj map polygon color: pure-function-testable — given a region's weather and active
  species, the dominant-species selection logic (reusing `SignalPipeline`/
  `DominantSpeciesResolver` patterns already established) is the same kind of unit-testable
  code as the existing map logic, just keyed by region instead of grid point.
- Map polygon rendering itself: build + manual visual check, same convention as all prior
  map/widget UI work in this project.
- Typography floor: `DesignSystem`'s scale values themselves are pure constants, trivially
  unit-testable (assert every token ≥ 20). Whether every *view* actually uses a compliant
  token (vs. a raw system style that happens to be smaller) is a build + visual-audit check,
  not something a unit test can verify — this project has no snapshot-testing setup, and
  adding one is out of scope for this pass.

## Resolved by the Implementation Plan (`docs/superpowers/plans/2026-08-08-ui-visual-redesign.md`)

- Typography scale values (§6), `GridPoint`/`SlovakiaGrid` disposition (§5), the manual
  column-stepper removal (§2), and the photo-cache key scheme (§4) are all resolved above.
- Order of implementation: typography floor first (later tasks consume its final token
  values) → photo cache infrastructure → photo sourcing research → shared card + adaptive
  grid (both tabs) → map polygon redesign + dead-code cleanup. Twelve tasks total.
- Widget small/medium layout: reduced to a single-species hero treatment for small, 2 rows
  (down from 3) for medium — "fewer items, not smaller text." Exact coordinates are approved
  as a real starting layout, not a placeholder, but genuinely expected to need visual tuning
  once built (same as the map polygons below).

## Still Open — Expected to Need Tuning During/After Implementation

- Exact hand-approximated kraj polygon coordinates: a real first draft exists in the plan
  (Task 10), drawn from the reference map already reviewed, not left blank — but explicitly
  a starting point to visually check and adjust once rendered, not a frozen final answer.
- Whether the widget's redesigned small/medium layout actually fits ≥20pt text within their
  real on-screen frames is a build-and-look check (plan Task 3, Step 6), not guaranteed by
  the design on paper alone.
