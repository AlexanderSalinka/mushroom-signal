# Known Issues (from v1 final whole-branch review)

The v1 final review (2026-08-05) found 2 Critical + 11 Important findings. The 2 Critical
plus one Important (widget score-clamp) were fixed same session. Everything below was
deliberately deferred and is still open — captured here because the SDD review ledger
that originally tracked it is gitignored and gets deleted at the end of each plan's cycle.

- **Widget doesn't refresh when region changes in-app** — up to 12h lag before the widget
  reflects a region switch made in the companion app. Fix: call
  `WidgetCenter.shared.reloadAllTimelines()` in `AppState.selectRegion(_:)`.
  (Now planned as part of the v3 spec's notification work, since both touch the same call site.)
- **`.caution`-level species render identically to edible** on both the widget and the
  companion app — only `.poisonous` gets a warning treatment. A `⚠️`/amber treatment for
  `.caution` would close this.
- **No working refresh affordance on failure** — `ShortlistView` uses `.refreshable`, which
  has no pull-to-refresh gesture on macOS. A toolbar refresh button wired to
  `appState.refresh()` is the fix.
- **Stale data shown under an error banner** — `AppState.refresh()` sets `errorMessage`
  without clearing `signals` on failure, so a failed region switch can show the *previous*
  region's species list under an error for the *new* region. Either clear `signals` on
  failure or tag the list with the region it was computed for.
- **No cancellation on rapid region switching** — `AppState.selectRegion(_:)` fires an
  unstructured `Task` with no handle; overlapping refreshes can let an older fetch overwrite
  a newer one's results (last-*finished*-wins, not last-*started*-wins).
- **Three duplicated copies of the scoring pipeline** — the widget's `TimelineProvider`,
  `AppState.refresh()`, and `RegionMapView`'s per-region loop each independently do
  filter-by-region → `computeSignal` → rank. They agree today (verified during the final
  review) but nothing keeps them in sync; a future change to the filter/ranking rule has to
  be made in three places. Extracting one shared function in `MushroomSignalCore` (e.g.
  `SignalPipeline.rankedSignals(...)`) would fix this and also give the `.caution`/`.poisonous`
  filtering policy one place to live.
- **Regional map renders network failure as "low chance"** — a failed per-region weather
  fetch falls back to score 0, which looks identical to genuinely bad conditions and is
  labeled "Nízka šanca" in the legend. Should render unknown cells distinctly instead
  (hatched/grey/"—"). Directly relevant to the v2 map redesign — worth designing correctly
  there rather than patching the old schematic map.
- **No weather caching** — the design spec required caching the last good `WeatherSnapshot`
  so the widget doesn't need live network access at render time; this got dropped between
  spec and plan and was never implemented. A transient network blip pins the widget to
  "Žiadne údaje" for a full 12h refresh cycle.
- **No logging on any failure path** — `"Žiadne údaje"` currently means network failure,
  JSON decode failure, App Group unavailable, *or* genuinely nothing in season — four causes,
  one indistinguishable string. Add `os.Logger` at each catch site.
- **Dataset common names need a native-speaker pass** — the final review flagged a few
  possibly-off Slovak common names (e.g. `coprinus-comatus` → "Hnojník obyčajný" vs. the
  more standard "hnojník ochlpený"; `calocybe-gambosa` → "Penízovka hľuznatá" uses what may
  be a Czech-influenced form). Alexander (20 years foraging experience) is doing this review
  personally rather than delegating it to research.
- **No AppIcon asset catalog** — needed before this is a "real" installable app; currently
  produces a build warning.
- **Design-system bypasses** — a few raw `.white`/literal spacing values in `RegionMapView`
  and `ShortlistWidgetView`, inherited verbatim from their original plan briefs. Cosmetic,
  low priority, but should route through `DesignSystem` when those files are next touched.
