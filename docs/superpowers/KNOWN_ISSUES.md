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

## Fixed (2026-08-06 widget-resize-and-region-sync pass)

- **Widget doesn't refresh when region changes in-app** — fixed via a `WidgetReloading`
  protocol (`WidgetReloading.swift`) injected into `AppState`; `selectRegion(_:)` now calls
  `WidgetCenter.shared.reloadAllTimelines()` immediately after persisting the region change,
  instead of waiting for the next scheduled 12h timeline refresh.
- **Widget stuck at a single fixed size, unreadably small** — fixed: `MushroomSignalWidget`
  now supports `.systemSmall`, `.systemMedium`, `.systemLarge`, with `ShortlistWidgetView`
  branching per family and sizing text via new `DesignSystem` typography tokens
  (`captionSize`/`bodySize`/`titleSize`/`heroSize`). Large shows a hero row for the #1 species
  plus 3 more (4 total); small/medium stay at 3.

## Fixed (2026-08-06 v2 interactive map & species library pass)

- **Regional map renders network failure as "low chance"** — resolved as a side effect of
  the v2 map redesign: `RegionMapView` (the old schematic 8-kraj grid, which had this bug)
  is deleted entirely. Its replacement, `InteractiveMapView` + `DominantSpeciesResolver`,
  treats a missing weather snapshot the same as "no active species" — both render neutral/
  dimmed, never a false "low chance" color.

## Open Issues
- **Region selection may not be persisting via the shared App Group** — investigated
  2026-08-06 while testing the widget still showing "Žilinský kraj" (the hardcoded default
  in `RegionStoreConstants.defaultRegionId`, `RegionStore.swift:14`). Confirmed: the real
  App Group container (`~/Library/Group Containers/UMPK75W8X6.group.com.alexandersalinka.MushroomSignal/Library/Preferences/`)
  was completely empty — no sandboxed process had ever successfully written a preference
  there. Not yet root-caused: unclear whether (a) the region was simply never changed via
  `RegionPickerView` in the app, or (b) `RegionStore.setSelectedRegion` / `AppState.selectRegion`
  silently fails to persist (note `store?.setSelectedRegion(region)` in `AppState.swift` is a
  silent no-op if `RegionStore.init` ever returns nil — no logging on that path). Next step:
  manually pick a different kraj in the app, quit, relaunch, and check whether the *app itself*
  (not just the widget) remembers the choice — that distinguishes an app-vs-widget sync bug
  from persistence never having been exercised at all. Also found and cleaned up (not the root
  cause, but real): a malformed `~/Library/Group Containers/--TeamIdentifierPrefix-group...`
  directory from some earlier build where `$(TeamIdentifierPrefix)` wasn't resolved — removed,
  contained no data, just a stray empty container shell.
- **Three duplicated copies of the scoring pipeline** — the widget's `TimelineProvider`,
  `AppState.refresh()`, and now `MapScreenState.dominantSpecies(at:)` each independently do
  filter-by-region/species → `computeSignal` → rank (or resolve-dominant). They agree today
  but nothing keeps them in sync; a future change to the filter/ranking rule has to be made
  in three places. Extracting one shared function in `MushroomSignalCore` (e.g.
  `SignalPipeline.rankedSignals(...)`) would fix this and also give the
  `.caution`/`.poisonous` filtering policy one place to live.
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
- **Design-system bypasses** — a few raw `.white`/literal spacing values in
  `ShortlistWidgetView`, plus a `.frame(width: 220, height: 160)` literal in the new
  `SpeciesDetailView` (inherited verbatim from its plan brief), and a hardcoded 8 in
  `InteractiveMapView`'s legend dot. Cosmetic, low priority, but should route through
  `DesignSystem` when those files are next touched.
