# Mushroom Signal — Chart Fix, Card Photos, and the Signal Hero

**Superseded — split into two specs after a critique pass surfaced real gaps (missing
season-word mapping, an unworkable widget layout assumption, an under-specified
animation lifecycle) and Alexander asked to separate the small pre-approved half from
the larger one still needing iteration:**
- `2026-08-12-chart-fix-and-card-photos-design.md` — approved, implementation-ready.
- `2026-08-12-mushroom-signal-hero-widget-design.md` — first version, still iterating.

Kept here for history; do not implement directly from this version.

## Relationship to prior specs

Builds directly on `2026-08-11-predpoved-beautify-design.md` (shipped same session,
merged to `main` at `0dba1e9`). That spec shipped `WeatherRainChartView`, the compact
`CompactSpeciesCardView` grid, and the plain-text "Blíži sa dážď" section. This spec is
the first real usage pass after seeing it running: Alexander live-reviewed the shipped
tab, one visual bug was found and confirmed against the code, and two follow-on features
came out of a combined brainstorming + frontend-design session (three iterations in the
browser-based visual companion, all approved live).

## Why

Three separate findings from actually running the merged app, not just reading diffs:

1. **A real bug.** `WeatherRainChartView` stacks two `Chart` views (temp line, rain
   bars). Only the X-axis got unified between them; each renders its own default Y-axis,
   and they visually collide — the temp axis's "0" merges into the rain axis's "5" as
   "05", with the rain axis's remaining "10/5/0" floating below. Confirmed both visually
   (screenshot) and in code (`WeatherRainChartView.swift:124-153`, no
   `.chartYAxis(.hidden)` on either chart).
2. **Dead plumbing.** The "Odporúčané dnes" compact cards show species with no photo,
   even though `CompactSpeciesCardView` already declares a `photo: SpeciesPhoto?`
   parameter — the call site (`PredpovedView.swift:161`) passes `photo: nil`. The
   feature was scaffolded and never finished.
3. **An underused signal.** The "Blíži sa dážď" section is plain text. Alexander wants
   it to be a real focal point — the app's temperature+rain trigger logic
   (`FlushTriggerDetector`) already exists and already drives scoring, but today it's
   surfaced nowhere more prominent than a small icon on individual species cards.

## Goals

1. **Fix the chart's Y-axis collision** — one legible axis, not two overlapping ones.
2. **Wire real photos into the compact cards**, reusing the existing photo
   infrastructure (`CachedAsyncImage`, `species-photos.json`), with a graceful fallback
   for the 7 species that don't have one yet.
3. **Replace "Blíži sa dážď" with a "Mushroom Signal" hero** — one prominent panel
   combining the temperature+rain trigger state, a mini chart, and region/season
   context, with a distinct graphic per state, one of which is animated. The same icon
   set (static) extends to the widget.

## Out of Scope

- Sourcing photos for the 7 species that don't have one (poisonous/caution species —
  Alexander will supply these himself in a future build; tracked in `KNOWN_ISSUES.md`).
- Legal/safety/liability review of poisonous-species content — explicitly deferred, not
  a pre-ship concern ("we're not shipping this year").
- Any change to `topPicksSection`'s selection logic, `seasonCalendarSection`, or the
  glass/vibrancy background mechanism — Alexander is happy with these and explicitly
  asked that their code not change.
- Fixing the pre-existing widget-gallery visibility bug (unnotarized personal-team
  signing rejected by `chronod`, documented in `CLAUDE.md`) — unrelated, long-standing,
  out of scope here. This work can be built and unit-tested but may not be visually
  confirmable in the actual widget gallery.
- Full interactive chart changes (range toggle, axis tick logic) beyond the Y-axis fix —
  the 7/14/30-day chart itself stays as shipped.

## Design

### 1. `WeatherRainChartView` — Y-axis fix

Add `.chartYAxis(.hidden)` to the rain `BarMark` chart (the second `Chart` in the
`VStack`, currently lines 135-153). The temp `LineMark` chart's default Y-axis (0-40°C)
stays visible — it's the one that reads correctly today. Rain bars remain proportional
to their own auto-ranged scale; their height plus the existing "Naposledy pršalo..."
caption text carries the information a rain-axis label would have. No other change to
this view.

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
system-image glyph. Not a new pattern.

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
  against any photo brightness, not just the sample photos used in the mockup.
- Async failures: `CachedAsyncImage`'s existing placeholder-during-load behavior covers
  network hiccups — same placeholder as the missing-photo case, no new failure state.
- Badge legibility: rank/sunrise badges keep their own translucent circle backgrounds
  (already implemented) so they stay readable over any photo.

### 3. Mushroom Signal hero — replaces `rainIncomingSection`

**Placement:** same slot in `PredpovedView`'s section order (below the big temp
readout, above the 7-day chart section, which is unaffected and stays as its own
section below this).

**Trigger logic — 4 states, one shared panel shell:**

| State | Trigger | Visual weight |
|---|---|---|
| Flush happening | `FlushTriggerDetector.triggered(in:asOf:)` is `true` (a qualifying rain+heat day occurred 2-7 days ago — the existing scoring signal, reused as-is, not re-derived) | Loud — animated |
| Rain incoming | `UpcomingRainDetector.nextTriggerEvent` returns a `RainEvent` | Loud — static |
| Near-miss | `FlushTriggerDetector.triggered` false AND `UpcomingRainDetector.nextTriggerEvent` nil AND `NearMissRainInsight.describe` returns a case | Quiet |
| No rain forecast | All three above are negative/nil | Quiet |

`FlushTriggerDetector.triggered` takes priority over `UpcomingRainDetector` when both
are true (an active flush is more newsworthy than a future one) — this ordering isn't
in either function today and needs to be the hero's own priority logic, not a change to
the detectors themselves.

**Panel shell (all 4 states):** icon badge, headline, real-numbers subline, and a
`region · month · season` context row (region from `Region.nameSk`, month/season reusing
`seasonCalendarSection`'s existing `Calendar.current.component(.month, from:)` pattern —
read-only reuse, that section's own code doesn't change).

**Loud states only (flush-happening, rain-incoming):** additionally show a compact
sparkline-style mini chart — a condensed preview of the same 7-day temp/rain data the
full chart section already loads, no axis labels, not an independent data fetch. Quiet
states (near-miss, no-rain) skip the mini chart — nothing eventful to preview.

**Graphics (hand-drawn `Shape` structs, same language as `ForestIcons.swift`'s
`LeafShape`/`DropletShape`/`SunriseShape`/`SporeShape`):**
- *Flush happening:* three mushroom caps bursting from one point, faint radiating growth
  lines beneath (reuses the sunrise-rays motif language). Moss/green.
- *Rain incoming:* droplet silhouette with motion lines, unchanged from the shipped
  `DropletShape`-based icon already in `rainIncomingSection`, just sized up. Water/blue.
- *Near-miss:* sunrise arc (reused from the flush-trigger glyph) with a faint dashed
  droplet beneath. Caution/amber, smaller badge.
- *No rain:* plain flat outline cloud, muted cloud-color at low opacity, no droplet.

**Animation (flush-happening state only, main app view only — never the widget):**
staggered entrance — each mushroom cap grows from `scaleY(0.15)` with a spring-style
overshoot (`cubic-bezier(0.34, 1.56, 0.64, 1)`-equivalent SwiftUI spring, ~0.75s,
staggered ~150-200ms per cap), settling into a slow idle loop (~3-4s ease-in-out
breathing scale pulse, faint pulsing growth rays) for as long as the state is active.
Must check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and skip the loop
entirely when true — same pattern already established in `CanopyLightView.swift`,
landing on the settled end-state with no motion.

**Widget:** all 4 icons get a static 40px badge rendering (no animation — WidgetKit
renders a snapshot per timeline refresh, it cannot run a continuous loop), reused across
`.systemSmall`/`.systemMedium`/`.systemLarge` in `MushroomSignalWidget.swift`. Same
color/style language as the app's hero, not a different visual identity — the widget
should read as a frozen frame of the hero panel, not a separate icon set. Which
existing widget layout slot this occupies (replacing/alongside the current shortlist
rows) is an open question for the implementation plan, not decided here.

## Testing

- `WeatherRainChartView`: existing chart tests (if any) plus a visual/manual check that
  only one Y-axis renders — this is a rendering issue, not something a unit test can
  catch on its own.
- `CompactSpeciesCardView` photo wiring: unit test that the correct `SpeciesPhoto` is
  resolved per species id at the call site; unit test that missing-photo species fall
  back to the placeholder path (not a crash, not a broken `CachedAsyncImage` call with a
  nil URL).
- Hero state selection: unit tests for the 4-way priority logic (flush > incoming >
  near-miss > none), reusing the existing `FlushTriggerDetector`/`UpcomingRainDetector`/
  `NearMissRainInsight` test fixtures rather than re-deriving new ones.
- Animation and the widget-static-badge rendering are visual, not unit-testable —
  verified live in the running app (screenshot) and, to the extent the widget-gallery
  bug allows, in the widget.

## Open Questions for the Implementation Plan

- Exact call-site pattern for resolving a `SpeciesPhoto` by species id inside
  `PredpovedView` (mirror whatever `ShortlistView` does today — not yet located).
- Where exactly the mini sparkline's data comes from — does it share `RegionWeatherState`
  with the full chart section (avoiding a second fetch), and what's the minimal view
  needed (likely a stripped-down reuse of `WeatherRainChartView`'s `LineMark`, not a new
  charting component).
- Widget layout: does the static hero badge replace part of the existing shortlist rows,
  or sit alongside them — needs a look at current `ShortlistWidgetView` composition
  before deciding, especially for `.systemSmall`'s already-tight vertical budget.
- New `DesignSystem` tokens needed: hero panel sizing, mini-chart height, widget badge
  size (`40` used throughout mockups, matching `.systemSmall`'s icon conventions —
  should be confirmed against real widget rendering before locking in).
