# Mushroom Signal — Hero (First Version, Now Approved)

**Status: approved, implementation-ready.** Iterated from the first version of this spec
(same filename, prior revision) which was explicitly flagged as not implementation-ready.
That iteration resolved every open question below, and Alexander made one scope call:
**the widget integration is cut from this spec entirely**, deferred to a follow-up spec
written after this hero ships — "leave the widget as is right now... after we have a
header, we will put the header inside the widget" (2026-08-12). Everything in this
version is hero-only, main app view only.

## Why

The "Blíži sa dážď" section is plain text today, even though the app's
temperature+rain trigger logic (`FlushTriggerDetector`) already exists and already
drives scoring — it's currently surfaced nowhere more prominent than a small icon on
individual species cards. Alexander wants a real focal point combining that signal with
locality and season context, one state of which is the exciting "mushrooms are actually
growing right now" moment.

## Goals

Replace `rainIncomingSection` with a "Mushroom Signal" hero — one prominent panel
combining the temperature+rain trigger state, a mini chart, and region/season context,
with a distinct graphic per state (one animated).

## Out of Scope

- **Widget integration** — cut from this spec entirely per Alexander's 2026-08-12
  decision. The widget keeps its current shortlist-only layout unchanged until a
  follow-up spec designs the inline state badge against the hero's real, shipped icon
  set (rather than against a description of icons that don't exist yet).
- Chart Y-axis fix, compact card photos — see the sibling spec, already approved and
  shipped separately.
- Any change to `seasonCalendarSection` or the glass/vibrancy background mechanism.
- Full interactive chart changes beyond what's already shipped.

## Design

### Trigger logic — 4 states, one shared panel shell

| State | Trigger | Visual weight |
|---|---|---|
| Flush happening | `FlushTriggerDetector.triggered(in:asOf:)` is `true` **AND** at least one species in today's `signals` has `score == 4` | Loud — animated |
| Rain incoming | `UpcomingRainDetector.nextTriggerEvent` returns a `RainEvent` | Loud — static |
| Near-miss | Both above negative, `NearMissRainInsight.describe` returns a case | Quiet |
| No rain forecast | All three above negative/nil | Quiet |

**Flush-happening definition, revised from the original combined spec:** not just the
raw `FlushTriggerDetector.triggered` threshold (any single day 2-7 days ago that
crossed 26°C/5mm), but that trigger *plus* confirmation it's producing a real maxed-out
result — at least one species hitting `score == 4`, the same value already rendered as
"●●●●" everywhere else in the app. This is Alexander's own framing ("four out of four
balls, hundred percent convergence") made literal against existing data, not a new
scoring concept.

**Validated against real data (2026-08-12):** checked `triggered` + `score==4` together
against ~90 days of real Open-Meteo history across 4 spread regions (Bratislavský,
Trenčiansky, Žilinský, Košický), covering May–August — actual foraging season, not a
favorable cherry-pick. Result: the raw threshold fires on 24.2% of days; of those, 71.4%
also produce a `score==4` species. **The strict definition fires on ~17.3% of all
days — roughly 1 in 6, not the "almost never appears" risk the first version of this
spec flagged.** Confirmed safe to build as designed, no loosening needed.

`appState.signals` already carries a `flushTriggered: Bool` on every `SpeciesSignal`
(set once per `AppState.refresh()`, same value for every entry that refresh cycle) — the
hero can read `appState.signals.contains(where: \.flushTriggered)` for the trigger
boolean instead of calling `FlushTriggerDetector.triggered` a second time with a
separately-fetched `dailyWeather` array. One source of truth already threaded through
existing state, no new fetch.

Flush-happening takes priority when both it and rain-incoming are true the same day
(they're not mutually exclusive — one looks 2-7 days backward, one looks forward).
**Re-confirmed by Alexander (2026-08-12):** flush wins, unchanged from the original
combined spec.

### Panel shell (all 4 states)

Icon badge, headline, real-numbers subline, and a `region · month · season` context
row. Region from `Region.nameSk` (already shown in the toolbar picker — this is a
second appearance of the same value, accepted as intentional redundancy per
Alexander's ask for locality in the signal itself, not a bug).

**Season-word gap, found during spec review — no existing code produces it.**
`seasonCalendarSection` only uses the raw month number (`Calendar.current.component(
.month, from: Date())`) to filter species by `fruitingMonths`; there is no
month→Slovak-season-word (jar/leto/jeseň/zima) mapping anywhere in the codebase today.
This needs new, small logic — a 4-value lookup — not a reuse as the original combined
spec implied.

**Loud states only (flush-happening, rain-incoming):** additionally show a compact
mini chart — **temp line and rain bars, stacked** (the same two-panel structure as the
full chart, condensed, not a temp-only sparkline — Alexander's explicit call,
2026-08-12, over the leaner temp-only option). **Hard requirement:** this must consume
the same `RegionWeatherState` instance the full chart section already loads, not an
independent fetch — a second fetch risks a different date window than the full chart a
few inches below it on the same screen, producing a visible desync between the two. A
pure view over shared state, not duplicated state.

**Windowing note, found during spec review:** `WeatherRainChartView`'s day-range
filtering (`visibleDays`, the 7/14/30-day toggle) is a private computed property driven
by that view's own private `@State`, not callable from the hero. The mini chart needs
its **own small windowing helper** — always a fixed 7-day-back + forecast window (no
user-facing range toggle, unlike the full chart) — applied to the same shared
`RegionWeatherState.dailyWeather` array. Not a new charting component: same `LineMark`/
`BarMark` pattern as `WeatherRainChartView`, condensed, with its own filter logic.

**Near-miss/no-rain must not read as broken.** These are deliberately quieter than the
loud states, but "quiet" means smaller icon and muted color — not omitted content. The
dashed-droplet-on-amber (near-miss) and outline-cloud (no-rain) treatments must always
render in full, distinctive enough on their own that an empty-looking panel doesn't
read as an unfinished state.

### Graphics (hand-drawn `Shape` structs, matching `ForestIcons.swift`'s existing language)

- *Flush happening:* three mushroom caps bursting from one point, faint radiating
  growth lines beneath (reuses the sunrise-rays motif language). Moss/green.
- *Rain incoming:* droplet silhouette with motion lines, unchanged from the shipped
  `DropletShape`-based icon already in `rainIncomingSection`, just sized up. Water/blue.
- *Near-miss:* sunrise arc (reused from the flush-trigger glyph) with a faint dashed
  droplet beneath. Caution/amber, smaller badge.
- *No rain:* plain flat outline cloud, muted cloud-color at low opacity, no droplet.

None of these `Shape` structs exist yet — `ForestIcons.swift` today has `LeafShape`,
`DropletShape` (reused as-is for rain-incoming), `SunriseShape` (reused for near-miss),
and `SporeShape`. Flush-happening's mushroom-cap-burst shape is new.

### Animation — flush-happening state only, main app view only

Staggered entrance — each mushroom cap grows from `scaleY(0.15)` with a spring-style
overshoot (~0.75s, staggered ~150-200ms per cap), settling into a slow idle loop
(~3-4s ease-in-out breathing scale pulse, faint pulsing growth rays) for as long as the
state is active.

**Two hard requirements, both found during spec review:**
1. Must check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and skip the
   loop entirely when true — same pattern already established in
   `CanopyLightView.swift` (its `reduceMotion` computed property, checked before setting
   `animate = true` in `.onAppear`), landing on the settled end-state with no motion.
2. **The idle loop must be torn down cleanly on `.onDisappear`**, not just gated at
   entry. SwiftUI's `repeatForever` does not automatically stop when its view leaves a
   scrollable container — if the hero scrolls off-screen (the section is inside a
   `ScrollView` per `PredpovedView`'s existing structure) without an explicit teardown,
   the animation can keep running or misbehave on reappear. Concrete pattern: an
   `@State` boolean (e.g. `isAnimating`) gates the animation modifier's `value:`, set
   `true` in `.onAppear` (guarded by the reduce-motion check above) and explicitly set
   `false` in `.onDisappear` — the same boolean-gated shape `CanopyLightView` already
   uses for its `animate` state, plus the `.onDisappear` teardown it does *not* have
   (that view never scrolls off-screen, so it never needed one; the hero does).

### New `DesignSystem` tokens

Following existing conventions — paired badge/glyph ratios like `rainIncomingSection`'s
current ad hoc 30pt/15pt circle, and the full chart's `chartTempPanelHeight`/
`chartRainPanelHeight` split, scaled down for a condensed preview:

| Token | Value | Rationale |
|---|---|---|
| `heroIconBadgeSize` | 64 | Loud-state icon badge diameter — a real focal point, ~2× the existing inline droplet badge it replaces, well under `compactCardSize` (120) |
| `heroIconGlyphSize` | 34 | ~53% of badge, matching the existing 15/30 glyph-to-badge ratio |
| `heroIconBadgeSizeQuiet` | 40 | Near-miss/no-rain badge — visibly smaller than loud (per the "smaller badge" requirement above), still well above the 20pt text floor |
| `heroIconGlyphSizeQuiet` | 21 | Same ~53% ratio preserved |
| `heroSparklineTempHeight` | 36 | Mini temp line panel — ~40% of `chartTempPanelHeight` (90) |
| `heroSparklineRainHeight` | 28 | Mini rain bars panel — ~40% of `chartRainPanelHeight` (72) |

Headline/subline/context-row text reuse existing `titleSize`/`bodySize`/`captionSize` —
no new text tokens needed.

## Testing

- Hero state selection: unit tests for the 4-way priority logic (flush > incoming >
  near-miss > none) using the revised flush definition, reusing the existing
  `FlushTriggerDetector`/`UpcomingRainDetector`/`NearMissRainInsight` test fixtures.
- Season-word mapping: unit test for all 12 months resolving to one of the 4 expected
  Slovak words.
- Mini chart windowing helper: unit test for the fixed 7-day-back + forecast filter
  against a synthetic `[DailyWeather]` fixture (boundary cases: fewer than 7 past days
  available, no forecast days available).
- Animation lifecycle: visual, not unit-testable — verified live in the running app
  (entrance, idle loop, reduce-motion skip, `.onDisappear` teardown on scroll).

## Deferred — Widget Integration (future spec)

Cut from this spec per Alexander's 2026-08-12 decision. Once this hero ships, a
follow-up spec will design the widget's static icon treatment against the hero's real,
shipped `Shape` structs and color language — not against a description of icons that
don't exist yet. The widget's `ShortlistWidgetView` is untouched by this spec; its
`.systemSmall`/`.systemMedium`/`.systemLarge` layouts, `regionHeader`, and shortlist
rows all stay exactly as shipped.
