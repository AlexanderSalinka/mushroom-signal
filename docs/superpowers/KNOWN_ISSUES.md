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

## Fixed (2026-08-07 app-focus pass)

- **Region selection wasn't persisting via the shared App Group** — root-caused and fixed.
  `RegionStoreConstants.resolvedAppGroupId` composed the App Group ID by separately reading a
  `com.apple.developer.team-identifier` entitlement and concatenating it with a hardcoded
  suffix — but that entitlement was never actually present in the app's signed output (only
  `com.apple.security.application-groups` was), so the lookup always returned nil and every
  read/write silently fell back to a bare, non-team-prefixed suite name that the real App
  Group container never sees. Confirmed via direct filesystem inspection: selections were
  landing in `~/Library/Preferences/group.com.alexandersalinka.MushroomSignal.plist` (wrong,
  unprefixed) while the real container
  (`~/Library/Group Containers/UMPK75W8X6.group.com.alexandersalinka.MushroomSignal/Library/Preferences/`)
  stayed empty. Fixed by reading the App Group ID directly from the already-correctly-resolved
  `com.apple.security.application-groups` entitlement instead of reconstructing it — see
  `RegionStore.swift`. Verified end-to-end against a real signed build (not just unit tests,
  which never exercised the real entitlement path). Also added logging on the
  `RegionStore.init` silent-nil-failure path in `AppState.swift`, per the observability gap
  this issue originally flagged.
- **Three duplicated copies of the scoring pipeline** — extracted `SignalPipeline` into
  `MushroomSignalCore` (`Signal/SignalPipeline.swift`). `AppState.refresh()`, the widget's
  `ShortlistProvider.fetchEntry`, and `DominantSpeciesResolver` (used by
  `MapScreenState.dominantSpecies(at:)`) all now go through `SignalPipeline.rankedSignals(...)`
  instead of each reimplementing filter → score → rank independently.
- **No AppIcon asset catalog** — added `Assets.xcassets/AppIcon.appiconset` with a placeholder
  icon (programmatically generated, on-brand with `DesignSystem`'s forest/mushroom-cap
  palette) at all required macOS sizes, wired via `ASSETCATALOG_COMPILER_APPICON_NAME` in
  `project.yml`. Build warning resolved; `CFBundleIconName`/`AppIcon.icns` confirmed present
  in the built bundle. Swap the placeholder PNGs for real art whenever it's ready — same
  `Contents.json`, no other wiring needed.
- **Design-system bypasses (app-side)** — `SpeciesDetailView`'s `.frame(width: 220, height:
  160)` and `InteractiveMapView`'s hardcoded legend-dot `8` now route through new
  `DesignSystem.detailPhotoWidth`/`detailPhotoHeight`/`legendDotSize` tokens. The
  `ShortlistWidgetView` (widget) bypasses are intentionally left alone — out of scope while
  the widget is deprioritized.
- **No weather caching** — implemented. New `WeatherSnapshotCache` in `MushroomSignalCore`
  persists the last successful `WeatherSnapshot` per region in the same App Group suite as
  `RegionStore`, so app and widget always share the same last-known-good data regardless of
  which process fetched it. `AppState.refresh()` now falls back to the cached snapshot on
  failure instead of blanking the list — `isShowingStaleData` flags this so `ShortlistView`
  shows the fallback in caution-amber with "Zobrazujú sa staršie údaje z HH:mm" instead of a
  hard red failure, and only shows the old hard-failure message when nothing is cached yet
  (first-ever failure). The widget's `ShortlistProvider.fetchEntry` does the same, and passes
  the cached snapshot's `fetchedAt` as the entry's `date` so the widget's own timestamp label
  reflects reality instead of looking falsely fresh.

## Open Issues
- **Dataset common names need a native-speaker pass** — the v1 final review flagged a few
  possibly-off Slovak common names (e.g. `coprinus-comatus` → "Hnojník obyčajný" vs. the
  more standard "hnojník ochlpený"; `calocybe-gambosa` → "Penízovka hľuznatá" uses what may
  be a Czech-influenced form). Alexander (20 years foraging experience) is doing this review
  personally rather than delegating it to research.
