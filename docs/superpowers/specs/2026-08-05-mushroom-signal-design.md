# Mushroom Signal — Design Spec

## Overview

A native macOS widget + companion app that tells you what mushroom species are
likely fruiting near you right now, in Slovakia — inspired by nahuby.sk's
content (mushroom species, seasonal occurrence patterns) and Apple Weather's
"glanceable widget + fuller app on tap" interaction model. Named after the
household's Signal Engine project, applying the same "raw conditions →
scored signal" pattern to mushroom foraging instead of sales prospects.

**Platform:** native macOS, Swift/SwiftUI + WidgetKit. Single Xcode project,
two targets (widget extension + companion app) sharing one local Swift
package for data/logic. No backend, no server — everything runs on-device.

**Build approach:** Claude implements directly (no step-by-step teaching for
this project — the user is intentionally not learning Swift right now).

## Goals (v1 / MVP)

1. Small WidgetKit widget shows a ranked shortlist of the 3 mushroom species
   most likely to be fruiting in the user's selected Slovak region, right now.
2. Tapping the widget opens a companion app with: the full species shortlist
   for the region, a region picker, and a regional heat map of Slovakia.
3. Feels hand-crafted and nature-inspired — not a generic list view.

**Out of scope for v1:** GPS/device location (manual region picker instead),
species detail pages with photos, medium/large widget families, push
notifications, iOS/iPadOS.

## Data Sourcing (decided, do not revisit)

nahuby.sk has no public API, returns 403 to non-browser fetches, and its
species descriptions / occurrence narrative / photos are original copyrighted
content with no stated reuse permission. **No scraping.** Instead:

- **Species knowledge base**: compiled by Claude from general mycological
  knowledge, written fresh — not copied from any single source.
- **Live conditions**: real weather data from **Open-Meteo**
  (open-meteo.com) — free, no API key/signup, EU coverage, historical +
  forecast temperature and precipitation by lat/lon. No secret to manage.

## Data Model

### Species (static, bundled JSON/Swift resource, ~25-30 entries)

```
Species {
  id: String                      // stable slug, e.g. "boletus-edulis"
  commonNameSk: String             // "Hríb smrekový"
  latinName: String                // "Boletus edulis"
  edibility: .edible | .caution | .poisonous
  lookAlikes: [String]             // species ids of dangerous look-alikes, may be empty
  fruitingMonths: Set<Int>         // 1...12
  idealTempRangeC: ClosedRange<Double>
  rainfallSensitivity: .low | .medium | .high   // how strongly recent rain gates fruiting
  habitat: String                  // free text, e.g. "smrekové a borovicové lesy"
  regionalAffinity: Set<Region>    // which regions this species is realistically found in
}
```

### Region

Slovak kraj-level regions (8), each mapped to one representative lat/lon for
weather lookups. Okres-level granularity is a possible post-v1 refinement,
not v1.

### Signal (computed, not stored)

```
SpeciesSignal {
  species: Species
  score: Int            // 0-3, drives the ●●●/●●○/●○○ display
  reason: String?        // optional short human-readable driver, e.g. "after recent rain"
}
```

## Signal Algorithm

Pure function, unit-testable in isolation:

```
computeSignal(species: Species, region: Region, weather: WeatherSnapshot) -> SpeciesSignal
```

Scoring inputs:
1. **Calendar fit** — is today's month in `fruitingMonths`? Adjacent months
   get partial credit (shoulder season).
2. **Temperature fit** — recent avg temp vs `idealTempRangeC`.
3. **Rainfall fit** — precipitation over the trailing ~10 days vs
   `rainfallSensitivity` (high-sensitivity species need recent rain to score
   well; low-sensitivity species are less penalized by dry spells).

Combine into a 0-3 integer score. Regional shortlist = top 3 species by
score for the selected region (ties broken by edibility relevance — edible
species rank above inedible/poisonous ones shown for awareness).

## Weather Integration

`WeatherClient` wraps Open-Meteo's historical + forecast endpoints for a
region's representative coordinate. Fetched once per refresh cycle (see
below), cached locally so the widget timeline doesn't need network access at
render time — WidgetKit timeline entries are precomputed from the last
successful fetch.

## Widget (small family only, v1)

Ranked shortlist card (confirmed via mockup):
- Region name (small, top)
- Top 3 species: common name + intensity dots (●●●/●●○/●○○)
- Last-updated timestamp (small, bottom)

**Refresh cadence:** 2x/day (morning + evening) via WidgetKit `TimelineProvider`.
Mushroom growth response to weather plays out over days, so this is not a
meaningful freshness limitation.

## Companion App (v1)

Opens on widget tap. Three pieces of UI:
1. **Full shortlist** — all scored species for the selected region (not just
   top 3), each row showing name, score, and the short `reason`.
2. **Region picker** — switch between the 8 Slovak kraje.
3. **Regional map** — color-coded heat map of Slovakia (green = favorable
   conditions, drier/muted = unfavorable), per the mockup's "option C"
   concept, promoted from widget-card idea to a full-app screen.

## Visual Design Language

Nature-inspired, forest-floor palette — evokes standing in a Slovak forest,
not a generic data-list app:
- **Palette**: deep forest greens, bark/wood browns, water-blue accents,
  soft cloud-grey/white for chrome and text-on-dark. Dark, moody base
  (matches the widget mockup already approved) rather than a bright/white
  UI.
- **Materials**: soft depth (subtle shadows/blur) reminiscent of Apple's own
  widget materials — avoid flat/generic card styling.
- **Proportions**: layout spacing and key element sizing follow the golden
  ratio (≈1.618) where it applies naturally — card padding-to-content,
  section height ratios, map-to-list split in the companion app.
- Claude will invoke the `frontend-design` skill during implementation to
  work out exact values (specific hex palette, spacing scale, typography)
  rather than freezing them in this spec.

## Testing

- Unit tests on `computeSignal` — the core value proposition, most worth
  protecting. Cover: peak season + wet, off season, dry spell for a
  high-sensitivity species, edge months (shoulder season partial credit).
- Widget and app UI verified manually via Xcode previews/simulator (no
  Swift UI testing framework overhead for a personal v1 project).

## Open Questions for Implementation Plan

- Exact list of the ~25-30 v1 species (Claude will propose the list as part
  of the implementation plan for a quick sanity check before writing 25+
  data entries).
- Exact golden-ratio application points (resolved via frontend-design skill
  during implementation, not frozen here).
