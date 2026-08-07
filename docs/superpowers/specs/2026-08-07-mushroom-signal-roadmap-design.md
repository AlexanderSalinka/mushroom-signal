# Mushroom Signal — Scoring Intelligence & Roadmap

## Relationship to v1/v2/v3/v4

v1 (merged) shipped the widget, companion app, region picker, shortlist, and the original 3-factor signal-scoring algorithm. v2 (merged) added the interactive map, species library, and widget resizing. v3 and v4 (specs written, never built) proposed a personal find log, GPS pinning, proactive notifications, a trend sparkline, and photo-based species ID.

**This spec supersedes v3 and v4.** Their content isn't discarded — the find log, notifications, trend sparkline, and photo ID are still real, still wanted, and are carried forward below as a prioritized backlog. But the priority order has changed: rather than building new user-facing features next, the priority is making the app's core intelligence — the scoring algorithm and the species dataset it runs on — deeper and more scientifically grounded first. Everything else builds on top of that.

The map and species library (v2) are explicitly **not** touched by this spec. They already work well and already pull from real computed data — see §4.

## Priorities (highest to lowest)

1. **This spec: scoring algorithm redesign + species data enrichment** — the core intelligence.
2. **Find log** (GPS-first pinning, manual fallback, SwiftData storage) — from v4 §1-2, unchanged in shape, just lower priority than originally proposed.
3. **Proactive notifications** and **trend sparkline** — from v3 §2-3, same priority tier as each other, both come after the find log.
4. **Photo-based species ID** — from v4 §3, last: it's its own longer effort, gated on Alexander's own photo-data-collection time, not just engineering time.

§6 below carries forward enough detail on 2-4 to plan from later, without repeating v3/v4 verbatim — see those files for full original mechanism detail where §6 points to them.

## Goals

1. Redesign `computeSignal` from three asymmetric factors (calendar-as-gate, temperature, rainfall) into four equal-weight factors (calendar, temperature, humidity, rainfall) — each worth exactly 25% of the score.
2. Add a real, data-driven "flush trigger": a warm day (≥26°C) with rain 2-7 days ago measurably raises a species' rainfall score, scaled by that species' rainfall sensitivity — matching a real foraging pattern, not an arbitrary bonus.
3. Add humidity as a genuine scoring input, backed by real Open-Meteo humidity data — the app already fetches temperature and precipitation live; humidity is fetched the same way.
4. Re-research and enrich the existing 27-species dataset (temperature ranges, new humidity ranges, fruiting months, rainfall sensitivity) from synthesized multi-source mycological knowledge, for Alexander to verify against his own 20 years of foraging experience.
5. Widen the displayed score from 0-3 to 0-4, matching the four underlying dimensions directly — one point per dimension, no more lossy rescaling.

## Out of Scope

- **No scraping.** nahuby.sk (or any other single site) is not fetched, scraped, or copied from — see §5 for why and what's done instead. Already a hard constraint in this project's `CLAUDE.md`; restated here because it came up directly in brainstorming this spec.
- **No changes to the map, species library, or region picker.** §4 confirms why: they already consume real computed data, so improving `computeSignal` improves them automatically, with no UI work needed.
- **No find log, GPS, notifications, trend sparkline, or photo ID in this phase.** All four are real and prioritized in §6, but out of scope for the implementation plan this spec leads to. Each gets its own future spec/plan cycle.
- **No change to `Region`, the 8-kraj model, or how a region is selected.**

## 1. Scoring Algorithm — Four Equal-Weight Dimensions

Each dimension scores `0.0`, `0.5`, or `1.0`. The total (`0.0`-`4.0`) is rounded to the nearest integer for display (`0`-`4`).

**Calendar fit** — unchanged from today: `1.0` if the current month is in `fruitingMonths`, `0.5` if it's an adjacent (shoulder) month, `0.0` otherwise.

**Temperature fit** — unchanged from today: `1.0` if the 10-day average temperature falls within `idealTempMinC...idealTempMaxC`, `0.5` if within 3°C of that range, `0.0` otherwise.

**Humidity fit** *(new)* — same shape as temperature fit: `1.0` if the 10-day average humidity falls within a new `idealHumidityMinPercent...idealHumidityMaxPercent` range on `Species`, `0.5` if within a tolerance band of that range, `0.0` otherwise. Exact tolerance width (proposed: 10 percentage points, mirroring temperature's 3°C) is an implementation-time tuning detail, not frozen here.

**Rainfall fit** *(redesigned)* — starts from today's existing precipitation-threshold logic as a baseline (unchanged: high sensitivity needs ≥20mm/10 days for full credit, medium needs ≥10mm, low always scores `1.0`), then adds the flush trigger:

- **Trigger condition:** was there a day, 2 to 7 days before today inclusive, whose **maximum** temperature reached ≥26°C *and* had measurable rain that same day? (Maximum, not average — a daytime peak reading matches "26°C during the day" better than a 24-hour mean.)
- **If triggered**, the rainfall dimension is bumped up, scaled by the species' `rainfallSensitivity`: high sensitivity → bump to `1.0` regardless of the baseline; medium → bump by `0.5` (capped at `1.0`); low → no bump (low-sensitivity species already always score `1.0`, so a rain trigger isn't informative for them).
- This directly encodes the real foraging pattern: a hot day followed by rain reliably precedes a flush within about a week, and species that depend heavily on rainfall benefit far more from that pattern than species that don't.

**Combining the four:** `total = calendar + temperature + humidity + rainfall` (range `0.0`-`4.0`).

**Safety-motivated exception to pure equal-weighting:** if calendar fit is `0.0` (species is completely outside its fruiting season — not even a shoulder month), the score is hard-zeroed regardless of how well the other three dimensions score. Without this, a species with perfect weather/humidity fit outside its actual season could still show a moderate score, which risks implying "go pick this now" for something that isn't growing at all. This is the one deliberate deviation from "all four dimensions purely equal" — flagged during brainstorming, not silently added.

**Displayed score:** `Int(total.rounded())`, clamped `0...4` (the clamp is a safety net; the formula naturally stays in range). This replaces the current 0-3 scale — see §3 for what that touches.

**Reason text:** `reasonText` gains two new cases — humidity out of range, and "recent warm rain, a flush may be coming" when the trigger contributed to the score. Exact Slovak wording is an implementation-time detail, matching how this project has always handled UI copy.

## 2. Data Model & Weather Client Changes

**`WeatherSnapshot`** gains one field:

```swift
public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public let regionId: String
    public let averageTempLast10DaysC: Double
    public let averageHumidityLast10DaysPercent: Double  // new
    public let totalPrecipitationLast10DaysMm: Double
    public let fetchedAt: Date
}
```

**Cost worth naming plainly:** this is a new required field on an existing `Codable` struct, so every place in the test suite that constructs a `WeatherSnapshot` directly (roughly 15-20 call sites across `MushroomSignalCoreTests`, `MushroomSignalTests`) needs a one-line update to supply it. Mechanical, not risky, but real — the implementation plan should account for it as its own step, not a surprise mid-task.

**`OpenMeteoClient`** adds `relative_humidity_2m_mean` to its existing `daily` query parameter list (alongside `temperature_2m_mean,precipitation_sum`) and averages it the same way temperature is already averaged. No new HTTP request — same call, one more field parsed from the same response.

**New `WeatherClient` method**, needed only for the flush-trigger check, which has to inspect specific days, not an average:

```swift
public struct DailyWeather: Codable, Sendable {
    public let date: Date
    public let meanTempC: Double
    public let maxTempC: Double
    public let precipitationMm: Double
}

public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]
    func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather]  // new
}
```

`OpenMeteoClient.fetchDailyBreakdown` requests `temperature_2m_max,temperature_2m_mean,precipitation_sum` with `past_days` (proposed default 10, to comfortably cover the 2-7 day trigger window) and `forecast_days=0` — the trigger only looks backward, so no forecast data is needed here.

**New pure function** for trigger detection, unit-testable in isolation against a synthetic `[DailyWeather]` array:

```swift
public enum FlushTriggerDetector {
    public static func triggered(in dailyWeather: [DailyWeather], asOf today: Date) -> Bool
}
```

**`Species`** gains two fields, mirroring the existing temperature-range shape:

```swift
public struct Species: ... {
    // existing fields unchanged
    public let idealHumidityMinPercent: Double  // new
    public let idealHumidityMaxPercent: Double  // new
}
```

## 3. Display — 0-4 Scale

The shortlist's `●●●/●●○/●○○` dot display becomes four dots instead of three, matching the four scoring dimensions one-to-one. This touches:

- `ShortlistView.signalRow` — currently clamps to `0...3`; becomes `0...4`.
- The widget's score rendering (`ShortlistWidgetView`) — same clamp, same change.
- Every existing test asserting a score is in `0...3` — needs updating to `0...4`.

No other UI changes. The map (§4) doesn't render dots at all, so it's unaffected by this specific change.

## 4. Why the Map Needs No Changes

Verified directly during brainstorming, not assumed: `InteractiveMapView` already calls `MapScreenState.loadGrid()` on appear, which fetches real live weather from `OpenMeteoClient.fetchSnapshots(for:)` for every grid point. Each point's color comes from `DominantSpeciesResolver`, which runs the same `computeSignal` this spec redesigns. Improving the algorithm improves the map's real-time coloring automatically, with zero changes to map code.

One likely source of the map "feeling like it doesn't follow any logic": a grid point only renders a species' color if that species is toggled on in the library grid below the map. With nothing toggled on, every point shows flat neutral brown — which looks like it isn't computing anything, even though it is. Not a bug, but worth knowing before assuming the map itself needs work.

## 5. Species Data Enrichment

**Sourcing constraint (restated from `CLAUDE.md`'s existing hard constraint, confirmed again during brainstorming this spec):** no scraping nahuby.sk or any other single site — no API, blocks non-browser fetches, and its content has no reuse permission. Beyond copyright, nahuby.sk is a Slovak/EU site, and the EU's *sui generis* database right can protect a compiled dataset like theirs even where individual facts aren't independently copyrightable — systematically extracting it carries real legal risk, not just a style preference.

**What happens instead:** for all 27 existing species, Claude researches and writes fresh, numeric values for:
- `idealTempMinC`/`idealTempMaxC` — refined from the original v1 pass
- `idealHumidityMinPercent`/`idealHumidityMaxPercent` — new
- `fruitingMonths` — reviewed, corrected if needed
- `rainfallSensitivity` — reviewed, corrected if needed

synthesized from multiple general mycological sources (field guides, academic mycology resources, Wikipedia among others) — cross-referenced, written fresh, not copied verbatim from any single source. Same division of labor as the original `species.json` compile and the in-progress Slovak-name review: Claude drafts comprehensively, Alexander verifies and corrects using his own 20 years of foraging experience before anything ships.

No new species are added in this pass — this is depth, not breadth, on the existing 27.

## 6. Backlog (carried forward from v3/v4, not built in this phase)

Kept here as a prioritized reference so the roadmap lives in one place, per the original request for "one spec with priorities." Full mechanism detail stays in the superseded v3/v4 files, referenced below rather than repeated.

**2. Find log** — GPS-first location pinning with manual map-tap fallback, SwiftData storage, a toggleable "My Finds" map layer. See `2026-08-05-mushroom-signal-v3-design.md` §1 for the base design and `2026-08-05-mushroom-signal-v4-design.md` §1-2 for the GPS-first amendment (manual tap becomes the fallback, not the only option).

**3a. Proactive notifications** — alert when a watched species crosses a score threshold, computed on the widget's periodic refresh so it works without the app open. See v3 §2. Worth noting: this becomes meaningfully more useful once the flush trigger (§1) exists — a notification could fire specifically on "trigger just activated for a species you're watching," which is a much stronger signal than a generic threshold-crossing.

**3b. Trend sparkline** — a compact per-species score chart across recent days + forecast. See v3 §3. Worth noting: `fetchDailyBreakdown` (§2, added in this spec for the flush trigger) is exactly the data this feature needs — it doesn't require its own new weather-client work when the time comes, only the day-by-day `computeSignal` loop and the chart UI.

**4. Photo-based species ID** — Create ML/Vision-based candidate suggestions (never a verdict), with the same poisonous-species warning treatment already used elsewhere. See v4 §3 for the full three-phase design (data, training, integration) and its safety framing — that framing doesn't change and should be re-read in full before this phase starts, not just skimmed.

## Testing

- **Humidity fit:** unit tests mirroring the existing `temperatureFit` test shape (in range, within tolerance, out of range).
- **Rainfall fit + trigger:** unit tests covering the trigger fired/not-fired, crossed with each `rainfallSensitivity` level (6 combinations) — verifying the bump amount and the `min(1.0, ...)` cap.
- **`FlushTriggerDetector`:** pure function, unit-testable with synthetic `[DailyWeather]` arrays — a qualifying day at each boundary of the 2-7 day window, a day just outside the window (day 1 or day 8), a day at exactly 26.0°C, a hot day with no rain, rain with no heat.
- **`fetchDailyBreakdown`:** unit test with a mocked multi-day JSON response (extends the existing `MockURLProtocol` pattern), verifying correct per-day parsing including the new max-temperature field.
- **`computeSignal` overall:** existing `SignalAlgorithmTests` updated for the new 0-4 scale and four-dimension combination; new tests for the out-of-season hard-zero gate and shoulder-season behavior under the new formula.
- **UI (dot count, widget rendering):** build + Xcode previews, same convention as all prior UI work in this project — no meaningful unit-test surface for pure layout.

## Open Questions for the Implementation Plan

- Exact humidity tolerance band width for the `0.5` tier (proposed 10 percentage points) — a tuning detail, not a blocking decision.
- Exact minimum precipitation to count as "rain" for the trigger (proposed >0mm, or a small floor like ≥1mm to avoid trace-measurement noise) — decide during implementation.
- Exact Slovak wording for the two new `reasonText` cases (humidity mismatch, flush-trigger-active).
- Backlog ordering (§6, items 2-4) is a strong default, not frozen — worth re-confirming once this phase's data enrichment is verified and it's time to plan the next one.
