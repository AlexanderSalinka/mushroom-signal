# Known Issues (from v1 final whole-branch review)

The v1 final review (2026-08-05) found 2 Critical + 11 Important findings. The 2 Critical
plus one Important (widget score-clamp) were fixed same session. Five more items were fixed
in the 2026-08-06 standalone-bugfixes pass — see
`docs/superpowers/plans/2026-08-06-standalone-bugfixes.md` and its final whole-branch review
for details. Those five are listed under "Fixed" below, not "Open Issues." Everything under
"Open Issues" is still open — captured here because the SDD review ledger that originally
tracked it is gitignored and gets deleted at the end of each plan's cycle.

## Fixed (2026-08-06 standalone-bugfixes pass)

- **`.caution`-level species rendered identically to edible** — fixed via
  `DesignSystem.warningColor(for:)`/`warningLabelSk(for:)`, a single styling policy used by
  both the widget and the companion app.
- **No working refresh affordance on failure** — fixed via an explicit toolbar refresh
  button in the companion app (`ContentView.swift`); `.refreshable` still has no macOS
  gesture, so the button is the real affordance now.
- **Stale data shown under an error banner** — fixed: `AppState.refresh()` now clears
  `signals` when a refresh fails, instead of leaving the previous region's list showing
  under the error.
- **No cancellation on rapid region switching** — fixed with a generation-token pattern in
  `AppState.refresh()`: whichever refresh call started most recently always wins the final
  state, regardless of which call happens to finish first (last-started-wins, not
  last-finished-wins).
- **No logging on any failure path** — fixed. `AppState.refresh()`, the widget's
  `TimelineProvider` (`MushroomSignalWidget.swift`), and `RegionMapView.loadAllRegionScores()`
  all now log via `os.Logger` on their failure paths, distinguishing network/decode failures
  from an unavailable App Group.

## Open Issues

- **Widget doesn't refresh when region changes in-app** — up to 12h lag before the widget
  reflects a region switch made in the companion app. Fix: call
  `WidgetCenter.shared.reloadAllTimelines()` in `AppState.selectRegion(_:)`.
  (Still planned as part of the v3 spec's notification work, since both touch the same call site.)
- **Three duplicated copies of the scoring pipeline** — the widget's `TimelineProvider`,
  `AppState.refresh()`, and `RegionMapView`'s per-region loop each independently do
  filter-by-region → `computeSignal` → rank. They agree today but nothing keeps them in
  sync; a future change to the filter/ranking rule has to be made in three places.
  Extracting one shared function in `MushroomSignalCore` (e.g.
  `SignalPipeline.rankedSignals(...)`) would fix this and also give the
  `.caution`/`.poisonous` filtering policy one place to live.
- **Regional map renders network failure as "low chance"** — a failed per-region weather
  fetch falls back to score 0, which looks identical to genuinely bad conditions and is
  labeled "Nízka šanca" in the legend. The fetch failure is now logged (see "Fixed" above),
  but the *rendering* is unchanged — should show unknown cells distinctly instead
  (hatched/grey/"—"). Directly relevant to the v2 map redesign — worth designing correctly
  there rather than patching the old schematic map.
- **No weather caching** — the design spec required caching the last good `WeatherSnapshot`
  so the widget doesn't need live network access at render time; this got dropped between
  spec and plan and was never implemented. A transient network blip pins the widget to
  "Žiadne údaje" for a full 12h refresh cycle.
- **Dataset common names need a native-speaker pass** — the v1 final review flagged a few
  possibly-off Slovak common names (e.g. `coprinus-comatus` → "Hnojník obyčajný" vs. the
  more standard "hnojník ochlpený"; `calocybe-gambosa` → "Penízovka hľuznatá" uses what may
  be a Czech-influenced form). Alexander (20 years foraging experience) is doing this review
  personally rather than delegating it to research.
- **No AppIcon asset catalog** — needed before this is a "real" installable app; currently
  produces a build warning.
- **Design-system bypasses** — a few raw `.white`/literal spacing values in `RegionMapView`
  and `ShortlistWidgetView`, inherited verbatim from their original plan briefs. Cosmetic,
  low priority, but should route through `DesignSystem` when those files are next touched.
