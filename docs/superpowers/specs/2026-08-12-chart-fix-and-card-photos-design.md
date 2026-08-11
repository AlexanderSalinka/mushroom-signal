# Mushroom Signal — Chart Y-Axis Fix + Compact Card Photos

**Status: approved, ready for implementation plan.** Split from the combined
`2026-08-12-mushroom-signal-hero-design.md` spec at Alexander's request — this half is
small, low-risk, and fully specified; the hero/widget half needs more design iteration
and is tracked separately in `2026-08-12-mushroom-signal-hero-widget-design.md`.

## Why

Two findings from live-reviewing the merged forest-glass/predpoved-beautify work:

1. **A real bug.** `WeatherRainChartView` stacks two `Chart` views (temp line, rain
   bars). Only the X-axis got unified between them; each renders its own default
   Y-axis, and they visually collide — the temp axis's "0" merges into the rain axis's
   "5" as "05", with the rain axis's remaining "10/5/0" floating below. Confirmed both
   visually (screenshot) and in code (`WeatherRainChartView.swift:124-153`, no
   `.chartYAxis(.hidden)` on either chart).
2. **Dead plumbing.** The "Odporúčané dnes" compact cards show species with no photo,
   even though `CompactSpeciesCardView` already declares a `photo: SpeciesPhoto?`
   parameter — the call site (`PredpovedView.swift:161`) passes `photo: nil`. The
   feature was scaffolded and never finished.

## Goals

1. Fix the chart's Y-axis collision — one legible axis, not two overlapping ones.
2. Wire real photos into the compact cards, reusing the existing photo infrastructure
   (`CachedAsyncImage`, `species-photos.json`), with a graceful fallback for the 7
   species that don't have one yet.

## Out of Scope

- Sourcing photos for the 7 species that don't have one (poisonous/caution species —
  Alexander will supply these himself in a future build; tracked in
  `KNOWN_ISSUES.md`).
- Legal/safety/liability review of poisonous-species content — explicitly deferred.
- Any change to `topPicksSection`'s selection logic — untouched.
- Full interactive chart changes (range toggle, axis tick logic) beyond the Y-axis fix.
- The Mushroom Signal hero, widget integration — see the separate hero/widget spec.

## Design

### 1. `WeatherRainChartView` — Y-axis fix

Add `.chartYAxis(.hidden)` to the rain `BarMark` chart (the second `Chart` in the
`VStack`, currently lines 135-153). The temp `LineMark` chart's default Y-axis
(0-40°C) stays visible — it's the one that reads correctly today. Rain bars remain
proportional to their own auto-ranged scale; their height plus the existing "Naposledy
pršalo..." caption text carries the information a rain-axis label would have. No other
change to this view.

### 2. `CompactSpeciesCardView` — photo integration

**Layout:** full-bleed background photo (replaces the current gradient+grain fill),
badges (rank top-left, flush-sunrise top-right) float on top unchanged, text sits on a
bottom gradient scrim — the same compositional pattern `SpeciesCardView` already uses,
at compact scale. Approved via visual-companion mockup against real screenshot data
(Boletus reticulatus, Fistulina hepatica, Macrolepiota procera, Laetiporus sulphureus).

**Missing photo (7 species — `tylopilus-felleus`, `amanita-muscaria`,
`amanita-phalloides`, `laetiporus-sulphureus`, `tricholoma-terreum`,
`armillaria-mellea`, `gyromitra-esculenta`):** same placeholder `SpeciesCardView`
already uses — bark-colored fill (`DesignSystem.Colors.bark`) with a centered `photo`
system-image glyph. **Sized proportionally to the compact card, not copied at
`SpeciesCardView`'s literal point size** — `SpeciesCardView`'s glyph uses the SF
Symbol's unscaled default size, which is tuned for that view's much larger photo area
(`speciesCardPhotoHeight`); reused verbatim at `compactCardSize` (120pt total card, ~104pt
usable after padding) it reads oversized. Use an explicit `.font(.system(size:
DesignSystem.compactCardSize * 0.28))`-scale modifier (exact ratio confirmed visually
during implementation, not hand-picked blind) so it balances against the smaller card.

**Wiring:** `PredpovedView.swift:161` needs the real photo lookup (matching however
`ShortlistView`/`SpeciesLibraryView` already resolve `SpeciesPhoto` for a given species
id) instead of the hardcoded `photo: nil`.

**Robustness (explicitly requested — think through the failure modes):**
- Photo containment: `.aspectRatio(contentMode: .fill)` inside a frame pinned to
  `DesignSystem.compactCardSize` with `.clipped()`, matching the exact fix already
  applied to `SpeciesCardView`'s own photo-overflow bug (unconstrained `.fill` grows
  past its container without an explicit height frame).
- Text legibility: scrim gradient (`forestDeep` → transparent, matching
  `SpeciesCardView`'s existing stops) sized generously enough to guarantee contrast
  against any photo brightness — verify against the real brightest and darkest photos
  in `species-photos.json` during implementation, not just the 3 sample photos used in
  the mockup.
- Async failures: `CachedAsyncImage`'s existing placeholder-during-load behavior covers
  network hiccups — same placeholder as the missing-photo case, no new failure state.
- Badge legibility: rank/sunrise badges keep their own translucent circle backgrounds
  (already implemented) so they stay readable over any photo.

## Testing

- `WeatherRainChartView`: visual/manual check that only one Y-axis renders — this is a
  rendering issue, not something a unit test can catch on its own.
- `CompactSpeciesCardView` photo wiring: unit test that the correct `SpeciesPhoto` is
  resolved per species id at the call site; unit test that missing-photo species fall
  back to the placeholder path (not a crash, not a broken `CachedAsyncImage` call with a
  nil URL).

## Open Questions for the Implementation Plan

- Exact call-site pattern for resolving a `SpeciesPhoto` by species id inside
  `PredpovedView` (mirror whatever `ShortlistView` does today — not yet located).
- Exact proportional-scale constant for the compact-card placeholder glyph — pick
  visually during implementation, verify against a real screenshot.
