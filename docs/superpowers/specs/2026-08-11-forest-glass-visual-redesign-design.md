# Mushroom Signal — Forest Glass Visual Redesign

## Relationship to prior specs

Builds directly on `2026-08-08-ui-visual-redesign` (which established `DesignSystem`'s
forest-coded palette — `forestDeep`/`forestMid`/`bark`/`water`/`mossAccent` — and the
`SpeciesCardView`/adaptive-grid pattern) and `GlassBackground.swift`'s real behind-window
vibrancy (`NSVisualEffectView`, `.behindWindow` blending), shipped earlier. It also closes a
gap flagged in `KNOWN_ISSUES.md`'s Open Issues: `PredpovedView`'s `topPicksSection` never
got the chip/pill treatment that `seasonCalendarSection` received on 2026-08-10, so the tab
currently reads as two visual families stacked on top of each other.

No prior spec covers glass texture, iconography, or typography choices — this is the first
pass to treat those as design decisions rather than incidental defaults.

## Why

Alexander's own framing: the current design (golden-ratio spacing, real glass vibrancy,
Apple-HIG-familiar layout) already works and he likes it — "almost like a better App Store
style context." The ask is not to replace it, but to push it further toward *feeling like
standing in a forest* while keeping the glass. Two brainstorming rounds (with mockups,
approved 2026-08-11) landed on a signature move plus four supporting moves, all validated
against real `DesignSystem.swift` tokens rather than invented ones.

A third round, same day, went further than visual polish: Alexander specified a concrete
top-to-bottom order for the whole `PredpovedView` tab and asked for the daily weather chart
to show humidity alongside temperature, plus a new forward-looking rain alert. That full-tab
mockup (`predpoved-full-tab.html`) was explicitly approved as final — "I want the finished
code to look exactly like the mockup right now" — so this spec now locks both the visual
system *and* the tab's concrete layout/content, not just tokens and components.

## Goals

1. **Canopy-light glass** (signature move) — replace the flat `forestDeep.opacity(0.25)` tint
   in `mushroomGlassBackground()` with 2-3 soft, irregular, warm-toned light blobs blended
   under the same vibrancy, at a fixed 66% intensity. Approved via interactive mockup
   (intensity slider), locked at 66%.
2. **New compact "glass button" species card** — a small, roughly-square, translucent card,
   replacing `topPicksSection`'s numbered-badge/`VStack` rows. Distinct from
   `SpeciesCardView` (Zoznam/Mapa's photo-backed grid cards) — those stay exactly as they
   are; this is a smaller, secondary component for compact contexts.
3. **Forest glyph set** — four hand-drawn line icons (leaf, droplet, sunrise, spore) at
   SF-Symbols-comparable weight, each with a concrete first-use site (not just decoration).
4. **Grain texture** — a very subtle (5% opacity, overlay blend) noise texture on
   `forestMid`/`forestDeep` card fills, replacing perfectly flat gradients.
5. **Extended `bark`/`water` usage** — `bark` draws a section divider; `water` (paired with
   the new droplet glyph) colors the existing moisture/rainfall readout. Both were previously
   near-unused tokens.
6. **`PredpovedView`'s full section order, locked** — hero → combined daily chart → top 4
   picks → rain-incoming alert → season calendar, matching the approved
   `predpoved-full-tab.html` mockup exactly. `topPicksSection` moves from showing 3 signals to
   4 (`visibleTopSignals`'s `.prefix(3)` → `.prefix(4)`).
7. **Rain + heat chart, last 10 days only** — `dailyStripSection` is simplified rather than
   made more complex: two simple stacked bar rows (max temp, precipitation), past days only,
   no forecast, no humidity. Deliberately the same two variables the rain-incoming alert (Goal
   8) is computed from, so the chart explains the alert instead of showing a third metric.
   Revised mid-brainstorm — an earlier round of this spec called for a combined
   temperature+humidity chart with dual axes; superseded by this simpler version once the
   alert's real trigger condition (rain **and** heat) was settled.
8. **New "Blíži sa dážď" (rain incoming) alert** — a forward-looking heads-up: scans the
   forecast portion of `dailyWeather` for a day at/above `FlushTriggerDetector`'s existing 5mm
   rain threshold, and if found, tells the user when and how much, plus the window a flush
   could follow. Reuses the scoring engine's real threshold; introduces no new number.

## Out of Scope

- **Display typeface change.** A Fraunces-based display face for headers/hero text was
  mocked up and explicitly rejected by Alexander ("looks bougie") in favor of the current SF
  Pro treatment. SF Pro (`.system(size:...)`) stays everywhere, unchanged. Do not revisit
  without a new explicit ask.
- **New forest "sensor" indicators** (fog levels, wildlife/animal sightings, etc.).
  Alexander liked the idea but explicitly deferred it: "that's a whole another systems data
  feed we don't have." Nothing in this spec introduces a new data source — `bark`/`water`
  extension only styles data the app already fetches (existing `humidityPercent`/
  `precipitationMm` from `RegionWeatherState`).
- **Species photos inside the new compact card.** Not used in this pass — the card ships
  photo-less. See the explicit forward-compatibility requirement under Goal 2 below.
- **Touching `SpeciesCardView` or the Zoznam/Mapa grids.** Explicitly called out by Alexander
  as "too big" for this context, not as something to redesign — they are unaffected by this
  spec.
- **Changing `seasonCalendarSection`'s existing pill/chip component.** It already matches its
  own approved mockup (2026-08-10). Only its swatch dot gets a small enhancement (Goal 3,
  leaf glyph) — the chip shape/layout itself is untouched.
- **Reduce-motion handling for the canopy-light drift.** Worth doing (macOS exposes
  `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`), but not decided here — left
  as an open question for the implementation plan rather than silently skipped.
- **Tuning the glass's opacity/tint strength.** Alexander's own words: "we then can use or
  adjust the glossy look or the see-through of the background... that's just tweaking." The
  glass mechanism itself (canopy light at 66%, `forestDeep` at 0.25 opacity) ships as
  currently spec'd; further transparency tuning is explicitly a later pass, not this one.

## Design

### 1. Canopy-light glass

`GlassBackground.swift`'s `mushroomGlassBackground()` currently layers
`VisualEffectBackground()` (the real `NSVisualEffectView`) with a flat
`DesignSystem.Colors.forestDeep.opacity(0.25)` fill. Replace the flat fill with a new
`CanopyLightView`: 2-3 soft-edged, irregularly-shaped light blobs (organic, not circular —
matches the approved mockup's `border-radius: 62% 38% 55% 45% / ...` treatment, translated to
SwiftUI via an irregular `Path`/`Ellipse` combination with heavy `.blur()`), filled with a
radial gradient from `cloud` toward `caution` at low opacity, `.blendMode(.softLight)`,
positioned asymmetrically, each with an independent slow drift animation (~22-32s,
ease-in-out, alternating).

New `DesignSystem` token: `canopyLightIntensity: Double = 0.66` — the locked, approved
opacity multiplier on the blob layer as a whole (not user-facing/adjustable in the shipped
app; the mockup's slider was a calibration tool, not a feature).

```swift
extension View {
    func mushroomGlassBackground() -> some View {
        background(
            ZStack {
                VisualEffectBackground()
                DesignSystem.Colors.forestDeep.opacity(0.25)
                CanopyLightView()
                    .opacity(DesignSystem.canopyLightIntensity)
            }
        )
    }
}
```

Applies everywhere `mushroomGlassBackground()` is already used (`ContentView`,
`PredpovedView`, `SpeciesDetailView`, `MapScreenView`, `ShortlistView`) — no per-view changes
needed beyond the shared modifier.

### 2. Compact species card

New `MushroomSignal/Views/CompactSpeciesCardView.swift`. Square-ish (not the 4:3 photo
proportions of `SpeciesCardView`), translucent glass fill (`.background(.ultraThinMaterial)`
is sufficient here — the card sits on top of an already-glass `PredpovedView` background, so
it doesn't need its own `NSVisualEffectView`), rounded corners, subtle top-edge highlight and
border to read as a tappable "glass button" rather than a flat swatch.

```swift
struct CompactSpeciesCardView: View {
    let species: Species
    let signal: SpeciesSignal?   // rank + score dots when shown in a ranked context
    let rank: Int?                // nil in a non-ranked (future library) context
    let photo: SpeciesPhoto?      // nil today — see forward-compatibility note below
}
```

**Fixed size, independent of window/grid resize.** `DesignSystem` gains
`compactCardSize: Double` (matching the mockup's ~110-130pt scale). `topPicksSection`'s grid
uses `GridItem(.fixed(DesignSystem.compactCardSize))` columns, not `.adaptive` — the *number*
of visible columns/rows can reflow as the window resizes (more columns fit in a wider
window), but each individual card never scales up or down. This is a direct requirement from
Alexander: "these new compact cards should stay the same size... as large as here on the
mockup," distinct from the adaptive-but-elastic behavior of `SpeciesCardView`'s grid.

**Replaces** `topPicksSection`'s current numbered-badge/`VStack` rows in `PredpovedView.swift`
(lines 69-100) — same data source, new presentation, count raised from 3 to 4
(`visibleTopSignals`'s `.prefix(3)` → `.prefix(4)`, per Goal 6).

**Sunrise-badge placement, resolved.** An earlier draft of this spec left open where the
flush-trigger sunrise glyph goes, since the card has no room for reason text at this size.
Resolved via the `predpoved-full-tab.html` mockup and approved as-is: a small corner badge,
top-right, opposite the rank number (visible on the mockup's #2 pick) — not inline with any
text.

**Forward-compatible photo slot, not built now.** No photo ships in this pass, but the view
already takes an optional `SpeciesPhoto?` so a photo can be added later without restructuring
the component. Explicit requirement for whenever that happens (per Alexander, to be verified
manually, not just asserted): the photo must be centered within the card, clipped to the
card's own rounded shape, and must never overlap the rank badge, species name, latin name, or
score dots at any card size — check this against a real build with a real photo before
shipping, not just in isolation.

Edibility color policy matches every other species-bearing component: `.caution`/`.poisonous`
species recolor the rank badge and border via the existing `DesignSystem.warningColor(for:)`,
same as `SpeciesCardView` and the season-calendar chips already do.

### 3. Forest glyph set

Four hand-drawn line icons, SwiftUI `Shape`s (not image assets — keeps them fully
code-reviewable and tintable via `.foregroundStyle` exactly like the app's existing SF
Symbols, no asset-catalog entry needed). New `MushroomSignal/Views/ForestIcons.swift`
(or `MushroomSignalCore` if `SpeciesDetailView`/widget ever need them — start app-side,
promote later only if a real second call site needs it). Stroke width ~1.6pt to sit
comfortably next to the app's existing SF Symbols (`info.circle.fill`, `photo`, `trash`).

Each glyph has a concrete first-use site — none are added purely decoratively:

| Glyph     | First use |
|-----------|-----------|
| Droplet   | `PredpovedView`'s hero moisture/rainfall line, replacing plain text-only presentation, tinted `water` |
| Leaf      | `seasonCalendarSection`'s chip swatch — small leaf silhouette instead of the plain `Circle` dot, same `warningColor` tint policy |
| Sunrise   | Next to a signal's reason text wherever `flushTriggered` is true (`topPicksSection`'s new compact card, `SpeciesCardView`'s reason line) — the flush-trigger mechanic's first real visual presence beyond text |
| Spore     | Empty-state illustrations — `seasonCalendarSection`'s "Žiadne druhy nie sú aktuálne v sezóne" message and any other empty species list |

More glyphs can be added the same way as real needs come up — this set is not meant to be
exhaustive on day one.

### 4. Grain texture

SwiftUI has no native fractal-noise filter (the mockup's web version used an inline SVG
`feTurbulence` data URI, which has no direct native equivalent). Native approach: a small
(~128×128pt), pre-rendered, tileable noise texture, generated once and bundled as a static
asset — same precedent as the programmatically-generated `AppIcon` placeholder
(`KNOWN_ISSUES.md`, 2026-08-06). New `DesignSystem`/view-extension modifier `.grainTexture()`:
tiles the noise image via `.background(Image("Grain").resizable(.tile))`, `.opacity(0.05)`,
`.blendMode(.overlay)`.

Applied to `forestMid`/`forestDeep`-filled surfaces only: `SpeciesCardView`'s background,
the new `CompactSpeciesCardView`'s background, and `PredpovedView`'s glass content panel.
**Never applied directly behind running body text** — matches the approved mockup's
constraint, keeps legibility unaffected.

### 5. Extended `bark`/`water` usage

New `ForestDivider: View` (or a `.forestDivider()` modifier) — a 1pt line using
`LinearGradient(colors: [bark, .clear], startPoint: .leading, endPoint: .trailing)` at ~70%
opacity, replacing ad hoc separators. First use: between `PredpovedView`'s hero section and
`topPicksSection`.

`water` + the new droplet glyph together color `PredpovedView`'s existing moisture/rainfall
readout (`heroSection`'s `"Vlhkosť \(...)% · Zrážky \(...) mm"` line) — styling data the app
already has (`DailyWeather.humidityPercent`/`precipitationMm`), not a new feed. No other
current view surfaces raw humidity/rainfall data, so this is `water`'s only real usage in
this pass; noted here rather than overclaiming broader "everywhere" application.

### 6. Full-tab layout order + simplified rain/heat chart

`PredpovedView.body`'s section order becomes: `heroSection` → `dailyStripSection` (rain+heat,
last 10 days) → `topPicksSection` (4 compact cards) → new `rainIncomingSection` →
`seasonCalendarSection` → `disclaimer`. `ForestDivider` (§5) separates each section, matching
the mockup. The season calendar's position — last, unchanged in content/shape — was an open
assumption in the prior mockup round, now confirmed by Alexander's blanket approval of
`predpoved-full-tab.html` ("exactly as is").

`dailyStripSection` is rebuilt as two simple stacked bar rows over the same 10 past days,
sharing one x-axis (day labels, rightmost = today): a heat row (`BarMark` per day, `caution`
fill, value = `maxTempC`) and a rain row (`BarMark` per day, `water` fill, value =
`precipitationMm`). No forecast days, no dual-axis overlay, no humidity — reads from
`weatherState.dailyWeather.filter { !isForecastDay($0) }`, still the same already-loaded
array, no new `WeatherClient` call. This replaces the earlier (now superseded) combined
temperature+humidity single-plot design — two small unscaled-relative-to-each-other bar rows
are simpler to build and read than one dual-axis chart, and Alexander asked for exactly that:
"readable simple form." Chart width is bound to available layout width
(`.frame(maxWidth: .infinity)`), centered.

Grain texture (§4) is applied to the panel background this section sits on, but **not** to the
chart's own drawing area — noise under bars would hurt data legibility. This deviates from
§4's literal "card fills" wording; flagged as a deliberate, approved exception, not a silent
gap.

### 7. "Blíži sa dážď" — forward-looking rain alert

New pure function, e.g. `UpcomingRainDetector.nextTriggerEvent(in dailyWeather: [DailyWeather], asOf: Date) -> RainEvent?`,
alongside `FlushTriggerDetector` in `MushroomSignalCore`. Scans only the forecast portion of
the already-loaded `dailyWeather` (no new fetch — the same array `dailyStripSection` reads,
just its forecast days rather than the past-10 days §6 displays) for the earliest day meeting
`FlushTriggerDetector`'s **exact** existing condition — `precipitationMm >= 5` **and**
`maxTempC >= 26`, both required, same thresholds, one source of truth reused rather than
duplicated. Returns the day, amount, and temp, plus a display window computed the same way
`FlushTriggerDetector` computes its backward lookback (2-7 days after the trigger day) — a
heads-up, not a guaranteed score change.

```swift
public struct RainEvent: Equatable, Sendable {
    public let date: Date
    public let precipitationMm: Double
    public let maxTempC: Double
    public let flushWindowStart: Date  // date + 2 days
    public let flushWindowEnd: Date    // date + 7 days
}
```

New `rainIncomingSection` in `PredpovedView`: renders one `RainEvent` as a droplet-icon card
(§3's droplet glyph, `water`-tinted background) when present; a quiet empty state ("Žiadny
výraznejší dážď v predpovedi" or similar, final Slovak copy decided during implementation) when
`nil` — consistent with the app's existing empty-state pattern (§3's spore-glyph illustration
for `seasonCalendarSection`).

**Resolved:** qualifying rain requires the *same* condition `FlushTriggerDetector` already
uses for a real score bump — ≥5mm rain **and** ≥26°C max temp on that day, not rain alone.
Alexander's own reasoning: rain without warmth doesn't drive the same flush, matching real
foraging experience, not just the scoring engine's existing math. `UpcomingRainDetector`
reuses `FlushTriggerDetector`'s exact threshold constants rather than duplicating them —
one source of truth for what counts as a "trigger day," read in both directions (backward for
scoring, forward for this alert).

## Testing

This is a visual/`DesignSystem` pass — following the project's established convention for
SwiftUI view work (see the 2026-08-10 spec's Testing section): build + manual visual check,
no UI testing framework in this repo. Concretely:

- Compare the built app, section-by-section, against the three approved mockups (canopy-light
  intensity mockup, the round-2 assembled/compact-card/icon-set/grain mockup, and
  `predpoved-full-tab.html`'s full-page layout — the last of these is the final word on
  section order and content) before calling any piece done.
- Any pure logic introduced (e.g., if the sunrise-glyph visibility condition becomes its own
  helper rather than an inline `if flushTriggered`) gets a normal unit test — but this pass
  is expected to be almost entirely view code, not new pure logic.
- Verify `CompactSpeciesCardView`'s fixed-size behavior directly: resize the window and
  confirm column count changes while individual card size does not.
- **`UpcomingRainDetector`** (§7) is pure logic, gets normal unit tests: a forecast day at
  exactly 5mm **and** 26°C qualifies; 5mm alone without the heat does not; 26°C alone without
  the rain does not; multiple qualifying days returns the earliest one; an all-dry or all-cool
  forecast returns `nil`; the returned window is exactly +2/+7 days from the trigger day.

## Open Questions for the Implementation Plan

- **Canopy-light blob geometry** — exact path/ellipse construction and hand-tuned position
  constants are an implementation judgment call, not frozen here (the mockup used CSS
  `border-radius` tricks with no direct SwiftUI equivalent).
- **Reduce-motion for the canopy-light drift** — flagged in Out of Scope as worth doing but
  undecided; the plan should make an explicit call rather than silently skipping it.
- **Grain texture asset generation** — static pre-rendered image vs. a `Canvas`-drawn
  procedural noise is an implementation detail; either satisfies the 5%-opacity/overlay-blend
  requirement.
- **Leaf/sunrise/spore path fidelity** — translating the mockup's hand-drawn SVG path data
  into SwiftUI `Path` exactly vs. redrawing for SwiftUI's coordinate/curve conventions is an
  implementation detail, not a design decision.
- **Two-row chart layout** — whether the heat/rain rows are two separate `Chart` views stacked
  in a `VStack`, or one `Chart` faceted by metric, is an implementation detail; either
  satisfies §6 as long as the two rows read independently (no shared/normalized scale between
  them).
- **Rain-incoming Slovak copy** — the mockup's "O 2 dni · 9 mm dažďa" /
  "Podmienky na nárast rastu — sleduj skóre približne o 4–9 dní" is placeholder-quality
  phrasing for mockup purposes, not reviewed for tone against the app's existing Slovak copy
  (see `NotificationPreferences`'s established phrasing pattern) — final wording is an
  implementation-time decision.
