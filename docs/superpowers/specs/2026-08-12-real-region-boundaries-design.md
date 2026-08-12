# Real Region Boundary Data — Design

**Status: approved, implemented and verified 2026-08-12.** Written after the fact,
documenting the decisions made during an interactive session — Alexander redirected
mid-brainstorm from "smooth the existing hand-drawn shapes" to "get real data instead,"
which turned out to be the right call.

## Why

`KNOWN_ISSUES.md`: `RegionBoundaries`' hand-approximated kraj polygons (35-135 points
per region, hand-drawn 2026-08-08) render jagged ("broken glass") borders on the map.
The first proposal — Chaikin corner-cutting smoothing applied to the existing fake
data — was demoed and worked, but Alexander redirected: smoothing a guess is still a
guess. He asked to find and use real Slovak kraj boundary data instead.

## Data source and provenance

Slovak kraje are official EU NUTS3 statistical regions, so precise open government data
exists. Found via `github.com/drakh/slovakia-gps-data` (`GeoJSON/epsg_4326/
regions_epsg_4326.geojson`) — a third-party repackaging, with no license badge of its
own, of Slovakia's official ZBGIS database (Office of Geodesy, Cartography and Cadastre
of the Slovak Republic, source: geoportal.sk). ZBGIS explicitly states its data is free
for all use including commercial. The primary source's own WFS/download service would
give a cleaner first-party copy — not pursued here per Alexander's explicit choice ("use
it now, document the source," 2026-08-12), matching the same personal/alpha-use pattern
already established for `species-photos.json`'s photographer/license gap. **Revisit
before any public release**, same as that precedent.

Raw data: all 8 kraje present, 607-1905 points per region (vs. the old 35-135), sourced
from real survey/cadastral data.

## Topology-preserving simplification

Raw point counts are far more than needed for a small map overlay. Naive independent
Douglas-Peucker simplification per region would have broken the one property the old
hand-drawn data specifically guaranteed and tested for: adjacent regions share exact
border points, so `MapPolygon` never renders a visible gap or overlap at a kraj
boundary. Confirmed empirically before simplifying: the raw government data already has
this property (e.g. Bratislavský/Trnavský share 405 exact points) — a proper topology,
not independently-drawn polygons that happen to look close.

Fix: for every point shared between two adjacent regions' raw rings, the shared
contiguous run is identified once, simplified once (Douglas-Peucker, tolerance 0.004°,
~400-450m at Slovakia's latitude), and the identical simplified result is spliced into
both regions' final rings. Non-shared runs (each region's own outer/international-border
edges) are simplified independently at the same tolerance. Verified programmatically
after simplification: every previously-touching pair of regions still shares a non-empty
set of exact points (e.g. Bratislavský/Trnavský: 405 → 358 shared points after
simplification — reduced, never zeroed).

Result: 10,641 → 2,218 total points (168-384 per region) — roughly 2-4x today's old
density, but real surveyed shape instead of a hand-drawn guess.

## Storage format change

2,218 points as Swift tuple literals would make `RegionBoundaries.swift` very large and
is a known real compiler type-checking cost for big array literals. Switched to a
bundled JSON resource (`Data/region-boundaries.json`), matching the existing
`SpeciesDatabase`/`SpeciesPhotoDatabase` pattern (`Bundle.module.url(forResource:
withExtension:)` + `JSONDecoder`) rather than inventing a new one. `RegionBoundaries`'
public API is unchanged — `polygon(for regionId: String) -> [(latitude: Double,
longitude: Double)]?` — the JSON is decoded once into a `static let` (lazy,
thread-safe), falling back to an empty dictionary (matching the existing
optional-return failure semantics) if the bundled resource is somehow missing.

## Incidental fix: `SlovakiaGrid.latitudeRange`

The real data's true northernmost point (49.6137°, in Žilinský kraj) sits just past the
old hand-approximated data's assumed range (`SlovakiaGrid.latitudeRange` upper bound was
49.6). Widened to 49.65. Confirmed this doesn't change `SlovakiaGrid.generate()`'s actual
grid points — the 0.8° `latitudeStep` still lands its last row at 49.3 either way (49.3 +
0.8 = 50.1, past both the old and new bound) — only the declared range constant changes.

## Testing

Existing `RegionBoundariesTests.swift` needed no changes and all pass unmodified against
the real data: `testEveryRegionHasAPolygon` (≥35 points — real data has 168-384),
`testAdjacentRegionsShareBorderPoints`, `testEveryPolygonPointFallsWithinSlovakiaGridBounds`
(passes now that the range was widened), `testUnknownRegionIdReturnsNil`.

## Verification

Full Core suite: 159/159 passing. App built and launched; Mapa tab visually confirmed —
boundaries render smooth, accurately follow real terrain/borders, correctly scaled and
positioned against the underlying Apple Maps base layer, adjacent regions still touch
with no visible gaps.
