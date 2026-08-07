# Future Ideas

A running list of ideas worth remembering for later versions — not full specs, not committed
to, just nuanced ideas captured so they don't get lost and don't need re-brainstorming from
scratch. Append to this file whenever a new idea comes up in conversation; each entry should
be a few sentences, not a full write-up (that's what a spec in `docs/superpowers/specs/` is
for, once an idea is actually being built).

## 2026-08-08

Brainstormed while deciding what to prioritize after the UI visual redesign plan (see
`docs/superpowers/plans/2026-08-08-ui-visual-redesign.md`). Ordered roughly cheapest/most
obvious to most speculative — not a priority ranking, just how the ideas were generated.

**Already-parked ideas worth resurrecting** (originally scoped in the shelved v3/v4 specs,
superseded by the 2026-08-07 scoring-intelligence roadmap consolidation, but still good ideas
for a future version):

1. **Photo-ID via Create ML/Vision.** Train on Alexander's own 20 years of foraging photos.
   Hard "candidates only, never a verdict" safety framing — fatal lookalikes exist in the
   dataset, this must never present as a confident identification.
2. **GPS find-pinning.** A private personal layer of past finds — never exported, never
   shared, never social. Foragers guard their spots; this is the one feature that should
   stay explicitly personal-only by design, not just by default.
3. **Historical trend sparkline per species/kraj.** The current UI only shows *today's*
   score. A 7-14 day trend line would show a flush building before it peaks — arguably more
   actionable than a single snapshot.
4. **Proactive local notifications.** "Hríby sa dnes darí v Žilinskom kraji" push when a
   region crosses a score threshold, opt-in per kraj.

**New ideas from tonight's brainstorm:**

5. **watchOS complication.** A glance-at-your-wrist forecast may be more useful in practice
   than the desktop widget — you're standing in a forest, not at your Mac, when this matters
   most. Smaller build than it sounds: mostly reuses `MushroomSignalCore` as-is.
6. **"Season calendar" browse mode.** Separate from the live weather-driven forecast — a
   reference view answering "what's typically in season in August regardless of this week's
   weather," useful for planning trips ahead rather than just checking today.
7. **Share-a-forecast image export.** Render a kraj's current forecast card as a shareable
   image for a foraging-buddies group chat. Pure local image generation, zero backend, fits
   the app's existing local-only architecture as-is.
8. **Paid Apple Developer Program enrollment.** Likely the actual highest-priority item on
   this list: fixes the widget-gallery visibility bug that's cost two full debugging
   sessions (root cause is almost certainly unnotarized personal-team signing — see
   `CLAUDE.md`'s widget-visibility notes), and is the prerequisite for every distribution
   path below it.
9. **TestFlight beta with a few real Slovak foragers.** Once #8 unblocks it, get 2-3 people
   foraging in different kraje using it for a season. Real-world validation of the scoring
   algorithm beats further tuning against Open-Meteo data alone.

**The genuinely speculative one — a real architectural fork, not a small feature:**

10. **Opt-in anonymized community flush reports.** Foragers tap "found some here" and it
    aggregates anonymously into the map, supplementing the weather-model prediction with
    real sightings. This is the one idea here that breaks the app's zero-backend
    architecture (needs a real server, a privacy design, abuse handling). Named because it's
    the single highest-leverage idea for prediction accuracy, but it's a different project
    scale — not a feature to bolt on to the current app.
