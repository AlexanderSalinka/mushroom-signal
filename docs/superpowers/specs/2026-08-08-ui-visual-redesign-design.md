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
purpose. (Flagged during brainstorming as not fully confirmed; if Alexander wants a manual
override kept alongside the adaptive default, that's a small addition, not a redesign.)

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

## 5. Map — Per-Kraj Shaped Overlay (replaces the grid-of-circles)

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

### Open question — not resolved, needs a decision before implementation

`GridPoint`, `SlovakiaGrid`, and `WeatherClient.fetchSnapshots(for: [GridPoint])` (the
batched multi-point fetch) become unused once this lands — nothing else in the app
currently needs point-based sampling. Two options: remove them now as dead code (matches
this project's general lean-code preference), or leave them in place unused, since the
mentioned-but-undesigned future Mapa route-planner idea might conceivably want point-based
geographic sampling again. Leaning toward removing now and re-adding if/when that future
feature actually gets designed (YAGNI), but this is Alexander's call, not decided here.

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

**Open question — does this include the widget?** Not decided here. The companion app
(Zoznam/Mapa) has a spacious resizable window — a 20pt floor is straightforward there. The
WidgetKit extension is a completely different, much tighter surface: the small family is
only ~155×155pt total, and its existing layout already leans on `.minimumScaleFactor(0.8)`
to fit three rows of forecast text at its *current*, smaller sizes. Forcing every widget
text element to 20pt+ could mean real layout casualties (truncation, dropped content, or a
from-scratch redesign of the small/medium families), not just a font-size bump — and the
widget has been explicitly parked since 2026-08-07 ("focus on the app" — see this project's
memory of that decision). Two honest options: scope the 20pt floor to the companion app
only for now (consistent with the widget staying parked), or treat this as the moment the
widget's typography gets revisited too, accepting that as new, separate scope. Needs
Alexander's call before implementation.

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

## Open Questions for the Implementation Plan

- Exact hand-approximated polygon coordinates per kraj — this is genuinely research/drawing
  work to do at implementation time, not something to freeze in this spec.
- Whether the library grid keeps a manual column-count override alongside the adaptive
  default (leaning no, not confirmed).
- `GridPoint`/`SlovakiaGrid`/batched-fetch removal vs. keep-unused (see §5's open question).
- Exact photo-cache storage location and cache-key scheme (species id vs. URL hash) —
  implementation-time detail.
- Order of implementation: the four pieces (cards+grid, photos+cache, map redesign,
  typography floor) are loosely coupled but not strictly sequential — photos need to exist
  before cards look "beautiful," but the adaptive grid mechanic, the map redesign, and the
  typography floor don't depend on each other or on the rest. Worth sequencing explicitly
  in the implementation plan, not decided here.
- Whether the 20pt typography floor includes the widget (see §6) — the single biggest open
  question in this spec, since it changes whether this pass touches widget code at all
  after "focus on the app" parked it.
