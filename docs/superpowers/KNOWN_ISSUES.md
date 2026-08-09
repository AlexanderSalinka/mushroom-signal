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

## Fixed (2026-08-07 scoring intelligence pass)

- **Scoring algorithm redesigned from 3 asymmetric factors to 4 equal-weight dimensions** —
  calendar, temperature, humidity (new), and rainfall each contribute 25% of the score.
  `computeSignal` gained a `flushTriggered: Bool` parameter driving a new mechanic: a day
  2-7 days ago with max temp ≥26°C and ≥5mm rain boosts the rainfall dimension, scaled by
  species `rainfallSensitivity` (`.high` → full bump, `.medium` → half, `.low` → none). See
  `SignalAlgorithm.swift`, `FlushTriggerDetector.swift`. Out-of-season species still hard-zero
  regardless of the other three dimensions or the trigger — the one deliberate exception to
  equal weighting.
- **Humidity added as a real scoring input** — `WeatherSnapshot.averageHumidityLast10DaysPercent`
  (from Open-Meteo's `relative_humidity_2m_mean`) and `Species.idealHumidityMinPercent/MaxPercent`.
- **New `WeatherClient.fetchDailyBreakdown`** — per-day max/mean temp + precipitation, needed
  only for flush-trigger detection (the existing snapshot methods stay averaged/aggregated).
- **Displayed score widened from 0-3 to 0-4** — matches the four scoring dimensions directly;
  both `ShortlistView` and `ShortlistWidgetView`'s dot rendering updated.
- **Map intentionally unaffected** — `DominantSpeciesResolver` (used only by the map) always
  passes `flushTriggered: false`; a batched per-grid-point daily-breakdown fetch needed for
  map-level trigger awareness is out of scope for this pass.
- **All 27 species re-researched** — humidity ranges (previously nonexistent), and
  temperature/season/rainfall-sensitivity reviewed against multiple synthesized mycological
  sources (not scraped from any single site). A fact-check pass found the research High-
  confidence with no fabrication, and independently confirmed the pass's largest correction:
  `pleurotus-ostreatus`'s fruiting season was inverted in the original v1 data (real sources
  show it's frost-triggered, peaking Nov-Mar, not the old April/September). **Still pending
  Alexander's personal review** (per this project's established data-review pattern) —
  specifically flagged: `pleurotus-ostreatus` (exact month boundary), `boletus-aereus`,
  `leccinum-duriusculum` + `boletus-reticulatus` (both still carry a placeholder-adjacent
  humidity value, not distinctly re-derived), `agaricus-campestris`, `coprinus-comatus`,
  `laetiporus-sulphureus` (a cited source conflicts with the committed months),
  `craterellus-tubaeformis` (December plausibly missing), `xerocomus-badius`, `boletus-edulis`
  (November omitted).
- **Whole-branch review found and fixed two calibration issues in the new flush trigger**,
  both confirmed against live weather data: the trigger originally fired on any trace of rain
  (`>0mm`) during a hot spell — checked against real Bratislava data, this meant a 39°C
  heatwave with a single 0.1mm trace 5 days prior would show "a flush may be coming" for
  `boletus-edulis` mid-drought. Now requires ≥5mm. Separately, the trigger's optimistic reason
  message previously always won over temperature/humidity warnings, even when both were fully
  out of range — now only shows when neither is at 0.0.
- **A pre-existing bug from earlier in the same pass was found and fixed**: a
  `SignalPipelineTests.swift` test meant to prove the flush trigger reaches `computeSignal`
  used a test-helper species hardcoded to `.low` rainfall sensitivity, which structurally
  cannot show a trigger bonus — the test could never have failed for the right reason. Fixed
  by adding an overridable `rainfallSensitivity` parameter to the helper.

## Open Issues
- **Dataset common names need a native-speaker pass** — the v1 final review flagged a few
  possibly-off Slovak common names (e.g. `coprinus-comatus` → "Hnojník obyčajný" vs. the
  more standard "hnojník ochlpený"; `calocybe-gambosa` → "Penízovka hľuznatá" uses what may
  be a Czech-influenced form). Alexander (20 years foraging experience) is doing this review
  personally rather than delegating it to research.
- **Species dataset (temp/humidity/season/rainfall-sensitivity) needs Alexander's review** —
  see the 2026-08-07 scoring intelligence pass above for the specific species flagged.
- **`FlushTriggerDetector` has a narrow UTC/local day-boundary skew** — `fetchDailyBreakdown`
  requests `timezone=auto` (region-local dates), but day-counting normalizes to UTC. During a
  ~2 hour local-midnight window (in CEST, roughly 00:00-02:00), the "days ago" count can shift
  by one. Low real-world impact (the widget refreshes twice daily, so there's a modest chance
  one refresh lands in the window) but a fully correct fix needs the region's actual timezone
  threaded through `DailyWeather`/`FlushTriggerDetector`, not just picking a different single
  calendar — deliberately deferred rather than rushed into the pass that found it.
- **No test asserts `OpenMeteoClient`'s outgoing query parameters** — `MockURLProtocol` ignores
  the request URL entirely, so a typo in a parameter name (e.g. `relative_humidity_2m_mean`)
  would pass all 82 core tests while silently breaking in production.
- **Humidity is now a hard-required field for all weather fetching** — if Open-Meteo ever
  renames or drops `relative_humidity_2m_mean`, `fetchSnapshot`/`fetchSnapshots` both throw
  entirely (shortlist, widget, and map all go dark), not just the humidity dimension.
  Worth considering an optional-with-neutral-fallback design if this proves fragile in practice.
- **`AppState`/widget fetch the weather snapshot and daily breakdown sequentially** — they're
  independent requests; `async let` would roughly halve refresh latency. Performance only, not
  correctness.
- **`species-photos.json`'s `photographer`/`license` fields are all literal `"UNVERIFIED"`
  placeholders** (Task 6 of the 2026-08-08 UI visual redesign, revised 2026-08-09) — Alexander
  supplied 20 direct Wikimedia image URLs himself, license/attribution research was explicitly
  descoped to save tokens. Content confirmed good by Alexander (2026-08-09) — each photo is a
  clear, representative shot of its species. Reusability risk is lower than a generic external
  image would carry: all 20 URLs resolve under `/wikipedia/commons/`, and Wikimedia Commons'
  submission policy only accepts free-licensed content (CC-BY/CC-BY-SA/CC0/public domain),
  unlike Wikipedia's separate non-free/fair-use namespace (`/wikipedia/en/`). What's still
  unconfirmed: the *specific* license per photo and the photographer's name — most Commons
  licenses (CC-BY, CC-BY-SA) legally require attribution by name, which isn't captured yet.
  Fine for local personal use — **must fill in the real photographer + exact license per photo
  before any public release or distribution of the app.**
- **Widget small/medium families never got the 20pt typography floor** — Task 3 of the
  2026-08-08 UI visual redesign, cancelled outright by Alexander on 2026-08-09 (not deferred).
  Widget text still uses its pre-floor sizes. If revisited, re-scope from scratch — see the
  cancelled task's note in `docs/superpowers/plans/2026-08-08-ui-visual-redesign.md`.
