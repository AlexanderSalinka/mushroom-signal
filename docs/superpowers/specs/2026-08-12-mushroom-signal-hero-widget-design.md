# Mushroom Signal — Hero + Widget (First Version)

**Status: first version, not implementation-ready.** Split from the combined
`2026-08-12-mushroom-signal-hero-design.md` spec at Alexander's request. Unlike its
sibling (`2026-08-12-chart-fix-and-card-photos-design.md`, pre-approved), this half is
explicitly meant to be iterated on further before it goes to `writing-plans` — it's
larger, has real open risks (below), and the widget placement was designed reactively
in this session rather than from a proper mockup pass.

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
with a distinct graphic per state (one animated). The same icon set (static) extends to
the widget.

## Out of Scope

- Chart Y-axis fix, compact card photos — see the sibling spec, already approved
  separately.
- Any change to `seasonCalendarSection` or the glass/vibrancy background mechanism.
- Fixing the pre-existing widget-gallery visibility bug (documented in `CLAUDE.md`) —
  unrelated, out of scope here.
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
scoring concept. **Stated assumption, not yet re-confirmed by Alexander:** "rain
incoming" keeps using `UpcomingRainDetector` as originally speced (rain+heat combo,
already implemented and tested) rather than a simpler rain-only check — introducing a
new detector without an explicit ask felt riskier than reusing what's already
validated. Flag this on read-back if a rain-only check is actually what's wanted.

Flush-happening takes priority when both it and rain-incoming are true the same day
(they're not mutually exclusive — one looks 2-7 days backward, one looks forward).
Under the revised, stricter flush definition this collision should be rarer than under
the original binary-threshold version, but the tie-break still needs to exist. Not
re-litigated with Alexander this round — carried forward as originally decided.

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
sparkline-style mini chart — a condensed preview of the same 7-day temp/rain data.
**Hard requirement:** this must consume the same `RegionWeatherState` instance the full
chart section already loads, not an independent fetch — a second fetch risks a
different date window than the full chart a few inches below it on the same screen,
producing a visible desync between the two. A pure view over shared state, not
duplicated state.

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

### Animation — flush-happening state only, main app view only, never the widget

Staggered entrance — each mushroom cap grows from `scaleY(0.15)` with a spring-style
overshoot (~0.75s, staggered ~150-200ms per cap), settling into a slow idle loop
(~3-4s ease-in-out breathing scale pulse, faint pulsing growth rays) for as long as the
state is active.

**Two hard requirements, both found during spec review, not in the original combined
spec:**
1. Must check `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and skip the
   loop entirely when true — same pattern already established in
   `CanopyLightView.swift`, landing on the settled end-state with no motion.
2. **The idle loop must be torn down cleanly on `.onDisappear`**, not just gated at
   entry. SwiftUI's `repeatForever` does not automatically stop when its view leaves a
   scrollable container — if the hero scrolls off-screen (the section is inside a
   `ScrollView` per `PredpovedView`'s existing structure) without an explicit teardown,
   the animation can keep running or misbehave on reappear. Needs a concrete
   implementation pattern (e.g., an `@State` boolean gating the animation, flipped off
   in `.onDisappear`), not left implicit.

### Widget — static icons, inline with the region header

All 4 icons get a static rendering (no animation — WidgetKit renders a snapshot per
timeline refresh, it cannot run a continuous loop), same color/style language as the
app's hero.

**Placement, resolved during spec review by reading the actual widget code
(`ShortlistWidgetView.swift`):** `.systemSmall` already has no spare vertical room —
region header, up to 3 species rows, spacer, footer (poisonous warning or timestamp)
fully occupy it. A separate 40px badge block would force cutting a species row or the
footer. **Resolution:** the state icon renders inline with `regionHeader` (same row, a
small ~14-16pt glyph before the region text) instead of as its own block — costs no
extra vertical space, works identically across `.systemSmall`/`.systemMedium`/
`.systemLarge`. This replaces the "replace vs. alongside a whole row" framing from the
original combined spec with a cheaper, lower-risk placement.

## Testing

- Hero state selection: unit tests for the 4-way priority logic (flush > incoming >
  near-miss > none) using the revised flush definition, reusing the existing
  `FlushTriggerDetector`/`UpcomingRainDetector`/`NearMissRainInsight` test fixtures.
- Season-word mapping: unit test for all 12 months resolving to one of the 4 expected
  Slovak words.
- Animation lifecycle, widget rendering: visual, not unit-testable — verified live in
  the running app and, to the extent the widget-gallery bug allows, in the widget.

## Open Questions for the Next Iteration

This spec is explicitly a first version — the following are flagged for a follow-up
design pass, not resolved here:

- Confirm the flush-happening redefinition (`triggered` + `score == 4`) actually fires
  at a reasonable frequency against real weather data — an overly strict definition
  could mean the loudest, most-worked-on state almost never appears.
- Whether the flush-vs-incoming tie-break (flush wins) is still the right call under
  the stricter definition — not re-discussed this round.
- Mini sparkline's exact minimal view implementation (likely a stripped-down reuse of
  `WeatherRainChartView`'s `LineMark`, not a new charting component) — not designed in
  detail yet.
- New `DesignSystem` tokens needed: hero panel sizing, mini-chart height, widget inline
  icon size.
- A proper mockup pass for the widget's inline-badge placement — the resolution above
  is a code-reading-driven risk mitigation, not a visual design pass like the hero's.
