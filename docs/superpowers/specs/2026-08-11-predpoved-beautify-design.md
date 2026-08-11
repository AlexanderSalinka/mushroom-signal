# Mushroom Signal — Predpoveď Beautify: Chart, Containers, Window Scaling

## Relationship to prior specs

Builds directly on `2026-08-11-forest-glass-visual-redesign` (shipped same day, branch
`worktree-forest-glass-redesign`), which established the current `PredpovedView` section
order, the frosted glass background mechanism (`GlassBackground.swift`), and the compact
species card. That spec explicitly deferred chart richness ("readable simple form" — two
unscaled stacked bar rows, no forecast, no axis labels) and left window sizing untouched.
This spec is the next pass: Alexander tried the shipped result and asked for three specific
follow-ups — a real chart (axes, forecast, range toggle), visible section containers, and a
window that doesn't stretch on large displays.

## Why

Alexander's own framing after seeing the shipped forest-glass redesign running: "the
application doesn't crash randomly... for a baseline it looks good... it is everything we
wanted there" — but the daily chart has no Celsius scale, no way to tell exactly how much it
rained or when last, sections float without visual grouping, and the window stretches
edge-to-edge on a full-size display instead of staying contained like a native macOS app
(his reference point: Apple's own Weather app).

Two rounds of visual-companion brainstorming (browser mockups, approved 2026-08-11) plus one
correction caught during design review (a dual-axis chart Alexander initially picked was
flagged against `dataviz` skill guidance and replaced with an honest two-single-axis-panel
alternative before he saw and approved the corrected version) produced the design below.

## Goals

1. **Real weather/rain chart, replacing `dailyStripSection`.** Temperature line (°C, its own
   axis) directly above a rain bar chart (mm, its own axis) — reads as one combined card, not
   a dual-axis chart. Bars grow from a shared baseline, proportional to actual mm (no rain =
   no bar). One shared date axis on the bottom panel, every single day labeled (no skipping).
   A "today" marker line runs through both panels. A "last rain" text line underneath states
   exactly when it last rained and how much, without requiring hover.
2. **7/14/30-day range toggle.** A segmented control switches the visible historical window.
   Backed by a single fetch (30 days back + 5-day forecast); the toggle re-slices already-
   loaded data client-side — instant, no spinner, no extra network call.
3. **Section containers.** All four `PredpovedView` sections (chart, Odporúčané dnes, Blíži sa
   dážď, Sezóna tento mesiac) get a frosted-glass panel treatment — blurred translucent fill,
   hairline border, drop shadow — matching macOS System Settings' pane grouping. Replaces the
   current bare-`VStack`-plus-`ForestDivider` separation.
4. **App-wide window size cap.** The window itself stays freely resizable/full-screenable (no
   change to that), but the tab content inside caps at 1024×768 and centers once the window
   grows past that, with the forest-glass background filling any remaining space — same
   pattern as Apple's Weather app. Applies to all three tabs (Zoznam, Mapa, Predpoveď), not
   just Predpoveď, since the frame constraint lives in the shared `ContentView`.
5. **Season calendar chips rebuilt as full-width ranked rows.** Replaces
   `seasonCalendarSection`'s adaptive-grid of small pill chips (currently truncating names —
   "Bedľa vys...", "Čírovník s...") with a vertically-stacked list of full-width rows, wide
   enough that every species' full common name is always visible, no truncation. Ranked by
   score (the same `SpeciesSignal.score` already computed for every species, currently only
   surfaced via `topPicksSection`'s top 4), highest first, replacing today's alphabetical
   order. Caution/poisonous rows keep their warning text ("⚠️ Opatrne"/"⚠️ Jedovatá") but move
   it inline on the same row (right-aligned) instead of stacking it as a second line below the
   name — equalizes row height across all edibility states without dropping the warning.
6. **"Blíži sa dážď" empty state expanded.** Today's one-line fallback ("Žiadny výraznejší
   dážď v predpovedi") stays for a genuinely flat forecast, but when the forecast has a *near
   miss* — rain without enough heat, or heat without enough rain, relative to
   `FlushTriggerDetector`'s existing 5mm/26°C thresholds — the message says so instead of just
   "nothing," using forecast data already loaded (no new fetch).

## Out of Scope

- **iPhone/iOS port.** Alexander raised this as future context only ("way, way later in the
  beta... we are still in alpha 0.11") — nothing in this spec builds toward it. No size-class
  abstraction, no iOS-specific layout branching.
- **Hard window-size cap.** Considered and explicitly rejected in favor of the soft
  content-cap approach — the OS window itself must stay fully resizable and full-screenable.
- **Humidity in the new chart.** The prior spec's chart already dropped humidity in favor of
  temp+rain only (§6 of the prior spec); this pass doesn't reopen that. Only temperature and
  precipitation are charted.
- **Changing `rainIncomingSection`'s ("Blíži sa dážď") own trigger logic.** It already reuses
  `FlushTriggerDetector`'s thresholds (prior spec §7) and that's unchanged — it just gets a
  container wrapper here, not new logic.
- **`ForestDivider` removed from `PredpovedView` only.** Its use elsewhere in the app (if any)
  is untouched; this spec only removes it between Predpoveď's now-boxed sections, where it
  would be redundant.
- **Per-user-adjustable window cap or chart range default.** Both are fixed constants (1024×768;
  default range 7 days) — not settings, not persisted preferences, in this pass.

## Design

### 1. `WeatherRainChartView` — new component, replaces `dailyStripSection`'s body

New `MushroomSignal/Views/WeatherRainChartView.swift`. Takes the already-loaded
`weatherState.dailyWeather` (see §2 for the fetch-range change) and a `@State` range selection
owned by this view.

```swift
struct WeatherRainChartView: View {
    let dailyWeather: [DailyWeather]
    let today: Date
    @State private var selectedRange: Int = 7   // 7 / 14 / 30, days of history shown
}
```

Layout, top to bottom:

- Segmented control: `7 | 14 | 30` (SwiftUI `Picker` with `.pickerStyle(.segmented)`, or a
  custom pill toggle matching the mockup — implementation detail, either satisfies this spec).
  Changing it only changes how many of the already-fetched past days are sliced into the
  charts below — **no new `WeatherClient` call**.
- Temperature panel: `Chart` with one `LineMark` per day (`maxTempC`, `caution`-colored,
  2pt line per `dataviz` mark spec), **one y-axis only**, Celsius, `.chartXAxis(.hidden)` (the
  rain panel's axis below carries the shared date axis for both).
- Rain panel: `Chart` with one `BarMark` per day (`precipitationMm`, `water`-colored, ≤24px
  thick, 4px rounded top corner only, grows from a `0` baseline — 0mm renders as no visible
  bar), **its own y-axis**, mm. This panel's `.chartXAxis` stays visible: one tick per day,
  label = day-of-month only (no month name, keeps 30-day density legible), small font sized as
  chart chrome (not subject to the 20pt body-text floor — same precedent as
  `mapMarkerDotSize`'s documented exception in `DesignSystem.swift`). Today's tick reads
  "dnes" instead of a date number.
- No gap between the two panels (`VStack(spacing: 0)`), so they read as one card with two
  honest single-axis regions rather than one dishonest dual-axis region. **This is a deliberate
  correction from the design that was first shown and approved in the browser mockup** — the
  first version overlaid both series on one shared scale, which was flagged during review
  against `dataviz` skill guidance (dual-axis charts "invent a correlation that isn't in the
  data") and replaced with this two-single-axis-panel version before Alexander saw and
  approved it.
- "Today" marker: a single vertical rule spanning both panels at the boundary between past and
  forecast days. Swift Charts doesn't natively support a rule spanning two separate `Chart`
  views — implementation approach (GeometryReader-positioned `Rectangle` overlay at the
  correct x-fraction, computed once from the shared date domain both charts render) is left to
  the implementation plan.
- "Last rain" callout: plain text below the charts, e.g. "Naposledy pršalo pred 3 dňami (18
  mm)." Computed from the **full 30-day fetch, independent of the selected toggle range** — so
  switching to the 7-day view never hides a true "last rain was 12 days ago." Fallback text
  when no rain occurred in the full 30-day window (e.g. "Bez zaznamenaných zrážok za posledných
  30 dní").

New pure function in `MushroomSignalCore`, alongside `FlushTriggerDetector`/
`UpcomingRainDetector`: `MostRecentRainfall.find(in dailyWeather: [DailyWeather], asOf: Date) ->
(date: Date, precipitationMm: Double)?` — searches backward from today for the most recent day
with `precipitationMm > 0`, restricted to non-forecast (past) days. Testable in isolation, same
pattern as the existing rain/flush detectors.

### 2. Data layer — single superset fetch, client-side range slicing

`RegionWeatherState.load(regionId:)` currently hardcodes `pastDays: 10, forecastDays: 5`.
Change to `pastDays: 30, forecastDays: 5` — one fetch per region load, superset of every range
the toggle can show. `WeatherClient.fetchDailyBreakdown(for:pastDays:forecastDays:)`'s
signature is unchanged (it already takes `pastDays` as a parameter); Open-Meteo's `past_days`
query param accepts values well past 30, so this is within the API's supported range.

`dailyStripSection`'s current `pastTenDays` computed property (a `.suffix(10)` filter) is
replaced by a range-parameterized equivalent living in `WeatherRainChartView` (or passed in),
`.suffix(selectedRange)` over the same already-loaded `dailyWeather` array — a simple slice,
not a new fetch path.

### 3. Section containers

New reusable container — a `ViewModifier` or wrapping `View`, e.g. `ForestPanel` — applied to
all four `PredpovedView` sections: the new chart, `topPicksSection`, `rainIncomingSection`,
`seasonCalendarSection`. Visual spec (from the approved mockup, style 3): translucent dark
fill (`rgba` close to `forestDeep` at ~55% opacity or `.ultraThinMaterial`/`.regularMaterial` —
implementation detail), background blur, 1px hairline border at low opacity, soft drop shadow
for separation from the page background. New `DesignSystem` tokens for panel corner radius/
padding if not already covered by existing `cardCornerRadius`/`spacingLarge`.

`ForestDivider()` calls between these four sections in `PredpovedView.body` are removed — the
panels' own edges now provide the separation `ForestDivider` was doing. `ForestDivider`
remains available/unchanged for any other use elsewhere in the app.

### 4. App-wide window size cap + background restructure

`ContentView.swift`'s `.frame(minWidth: 420, minHeight: 480)` becomes
`.frame(minWidth: 420, minHeight: 480, maxWidth: 1024, maxHeight: 768)`, applied to the
`TabView` specifically (the actual tab content), not the outer `NavigationStack`.

This requires moving `mushroomGlassBackground()` from being called individually inside each of
`ShortlistView`, `MapScreenView`, `PredpovedView`, and `SpeciesDetailView`, up to a single call
on `ContentView`'s outer `NavigationStack`, **outside** the new size cap — so the translucent
background (and its `CanopyLightView` light-blob animation) fills the entire window regardless
of how large it's dragged, while the capped `TabView` content centers on top of it. The four
existing per-screen `.mushroomGlassBackground()` calls are removed as part of this change
(otherwise double-applied/wasted — each was running its own independent light-blob animation
instance). Bonus side effect: the animated background now runs once per window instead of once
per screen.

`SpeciesDetailView` is reached via in-stack navigation (pushed within the same
`NavigationStack`, not a separate window) — the implementation plan should verify empirically
that pushed detail views still render within the capped-and-backgrounded shell rather than
escaping it, since this wasn't traced line-by-line here.

### 5. Season calendar chips — full-width ranked rows

`seasonCalendarSection`'s `LazyVGrid(columns: [GridItem(.adaptive(minimum: 120)...)])` of small
pill chips is replaced by a single-column `VStack` (or `LazyVStack`) of full-width rows —
mobile-phone-width at minimum (~375-390pt), so the row's own width is never the reason a name
truncates. `seasonChip(for:)` is rebuilt accordingly: leaf glyph, full `commonNameSk` (no
`.lineLimit(1)` truncation), and for `.caution`/`.poisonous` species, the existing
`DesignSystem.warningLabelSk(for:)` text right-aligned on the *same* row instead of stacked
below the name — every row is the same height regardless of edibility. Border/stroke weight is
already `lineWidth: 1` for every chip in the current code (confirmed, not actually different
per-edibility) — the previous "too thick" impression was the extra stacked warning line adding
visual height/density to caution/poisonous chips, not a literal border-width difference; moving
the warning inline resolves it without touching the border code.

Ordering: `inSeasonSpecies` (currently sorted alphabetically) is re-sorted by each species'
current `SpeciesSignal.score` from `appState.signals` (already computed for every species, not
just the top 4 — `topPicksSection` only takes `.prefix(4)` of the same array), highest score
first. A small rank number renders at the row's left edge (subtle, per the approved mockup —
not a prominent badge).

### 6. "Blíži sa dážď" — near-miss forecast messaging

New pure function in `MushroomSignalCore`, e.g. `NearMissRainInsight.describe(in dailyWeather:
[DailyWeather], asOf: Date) -> String?`, alongside `UpcomingRainDetector`. Scans the forecast
portion only (same data `UpcomingRainDetector` already reads) for the earliest day matching one
of two near-miss conditions, evaluated only when `UpcomingRainDetector.nextTriggerEvent`
already returned `nil` (a real trigger day always takes priority over a near miss):

1. `precipitationMm >= FlushTriggerDetector.minTriggerPrecipitationMm` but `maxTempC <
   FlushTriggerDetector.minTriggerMaxTempC` — rain without enough heat.
2. `maxTempC >= FlushTriggerDetector.minTriggerMaxTempC` but `precipitationMm <
   FlushTriggerDetector.minTriggerPrecipitationMm` — heat without enough rain.

Returns a descriptive string for whichever case matches first (or `nil` if the forecast is
genuinely flat on both fronts, in which case `rainIncomingSection` keeps today's plain "Žiadny
výraznejší dážď v predpovedi" fallback). Reuses `FlushTriggerDetector`'s exact threshold
constants, same one-source-of-truth pattern as `UpcomingRainDetector`. Exact Slovak copy for
each case is an implementation-time decision (same convention as the prior spec's rain-incoming
copy) — the logical cases and priority order are what's locked here.

## Testing

- **`MostRecentRainfall.find`** (§1): unit tests — a day with rain within the window returns
  it; the single most recent qualifying day wins when multiple days had rain; a day with
  `precipitationMm == 0` doesn't count; an all-dry 30-day window returns `nil`; forecast
  (future) days are excluded even if they show precipitation.
- **Range slicing**: verify `.suffix(7/14/30)` against a fetched 30-day array returns exactly
  the expected day count and the expected (most recent) days, not an arbitrary slice.
- **`NearMissRainInsight.describe`** (§6): unit tests — a forecast day with rain but not enough
  heat returns the rain-without-heat case; a day with heat but not enough rain returns the
  heat-without-rain case; a genuinely flat forecast (neither condition, any day) returns `nil`;
  when a real `UpcomingRainDetector` trigger day also exists, this function is not consulted at
  all (trigger takes priority — verify at the `rainIncomingSection` call-site level, not just
  the pure function).
- **Season chip ranking**: verify chips render in descending-score order matching
  `appState.signals`, not the prior alphabetical order, for a fixture with mixed scores.
- Build + manual visual check against the approved mockups, saved (not left in the gitignored
  `.superpowers/brainstorm/` session directory — see the prior spec's final-review finding M8,
  where mockups referenced only from that ephemeral location couldn't be found afterward) at
  `docs/superpowers/specs/mockups/2026-08-11-predpoved-beautify/chart-final.html` (7-day and
  30-day chart states), `container-style.html` (style-3 panel, the approved option among three
  shown), and `season-chips.html` (full-width ranked rows, inline warning badge).
- Verify the window cap directly: resize past 1024×768 on a real display and confirm content
  stays capped/centered while the background fills the remaining space, on all three tabs, not
  just Predpoveď.
- Verify `SpeciesDetailView` (pushed navigation) still renders inside the capped/backgrounded
  shell after the `ContentView` restructure (§4) — a real risk introduced by moving the
  background call, not present before this change.

## Open Questions for the Implementation Plan

- **"Today" marker rendering across two stacked `Chart` views** — exact SwiftUI mechanism
  (GeometryReader overlay vs. some other approach) is an implementation detail, not decided
  here; either satisfies §1 as long as one continuous marker visually spans both panels at the
  correct date.
- **Segmented-control exact component** — native `Picker(.segmented)` vs. a custom pill toggle
  matching the mockup's exact look is an implementation call; either satisfies §1.
- **Panel background exact material** — `.ultraThinMaterial`/`.regularMaterial` vs. a custom
  `rgba` fill matching the mockup's CSS approximation is an implementation detail; visual
  comparison against `container-style.html`'s style-3 mockup is the acceptance check, not a
  specific API choice.
- **New `DesignSystem` token names** (panel corner radius/padding, chart panel heights, etc.)
  are left to the implementation plan to name consistently with existing tokens, not frozen
  here.
