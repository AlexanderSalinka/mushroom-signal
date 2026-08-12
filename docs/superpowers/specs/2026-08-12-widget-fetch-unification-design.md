# Widget Fetch Unification — Design

**Status: approved, implementation-ready.**

## Why

`KNOWN_ISSUES.md`'s "AppState/widget fetch the weather snapshot and daily breakdown
sequentially" item originally covered both `AppState.refresh()` and the widget's
`ShortlistProvider.fetchEntry` — both made two back-to-back network calls
(`fetchSnapshot` then `fetchDailyBreakdown`) instead of overlapping them.

The weather-fetch-consolidation design (Item 1) already eliminates this for `AppState`
entirely — after Item 1, `AppState.refresh()` makes exactly one call and derives
`WeatherSnapshot` from it via `WeatherSnapshot.derive(regionId:from:windowDays:asOf:)`.
That leaves only the widget's `ShortlistProvider.fetchEntry` (`MushroomSignalWidget.swift`)
still making two sequential calls — Item 1 deliberately left the widget untouched (it
runs in a separate process on its own 12h `TimelineProvider` schedule).

## Goals

Apply the same "derive, don't double-fetch" pattern Item 1 establishes to the widget:
one network call instead of two, reusing `WeatherSnapshot.derive` rather than adding
`async let` parallelism around two calls that don't need to both exist. This resolves the
original issue by elimination, not by making two requests faster.

## Out of Scope

- `AppState` — already resolved by Item 1, not touched again here.
- The map's `fetchSnapshots` (`MapScreenState`) — separate, batched, multi-point call,
  unaffected.
- `WatchedAlertEvaluator` — Item 3 handles its fetch pattern separately.
- Any change to the widget's 12h timeline cadence or `NotificationPoster` call — only
  `fetchEntry`'s internal fetch strategy changes.

## Design

### `ShortlistProvider.fetchEntry` — one fetch, derived snapshot

Current (`MushroomSignalWidget.swift`):

```swift
let client = OpenMeteoClient()
let weather = try await client.fetchSnapshot(for: region)
WeatherSnapshotCache()?.store(weather)
let dailyWeather: [DailyWeather]
do {
    dailyWeather = try await client.fetchDailyBreakdown(for: region, pastDays: 10)
} catch {
    dailyWeather = []
    widgetLogger.error("Daily breakdown fetch failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
}
let flushTriggered = FlushTriggerDetector.triggered(in: dailyWeather, asOf: Date())
```

Becomes:

```swift
let client = OpenMeteoClient()
let dailyWeather = try await client.fetchDailyBreakdown(for: region, pastDays: 10)
guard let weather = WeatherSnapshot.derive(regionId: region.id, from: dailyWeather, asOf: Date()) else {
    throw WeatherClientError.emptyDailyData
}
WeatherSnapshotCache()?.store(weather)
let flushTriggered = FlushTriggerDetector.triggered(in: dailyWeather, asOf: Date())
```

`WeatherClientError.emptyDailyData` is an existing case, already thrown by the current
`fetchSnapshot` implementation for the same "nothing usable came back" condition — reused
here rather than introducing a new error case for the same meaning.

**Deliberate behavior change, consistent with Item 1's precedent:** today, if
`fetchSnapshot` succeeds but the separate `fetchDailyBreakdown` fails, the widget still
shows real signals (just with `flushTriggered` forced false via the empty-array
fallback) — a partial-success state. After unification, one failure fails the whole
fetch and falls through to the existing stale-cache branch (`WeatherSnapshotCache`,
unchanged) instead. This trades a narrower partial-degrade path for the same single
clean failure mode Item 1 already established for `AppState` — one fetch, one outcome,
consistent behavior across both the app and the widget rather than each having its own
distinct partial-failure shape.

**Not changed:** the stale-fallback `catch` block, `WeatherSnapshotCache` itself
(unchanged, still the cross-process shared cache read by both the app and the widget —
per Item 1's spec, extending it was explicitly avoided), and the widget's timeline/
notification-posting logic.

### Testing

- No new unit test infrastructure needed — `ShortlistProvider`/`fetchEntry` has no
  existing dedicated test file (SwiftUI/WidgetKit provider logic isn't unit-tested
  elsewhere in this codebase either), consistent with the established convention.
  Verified by building and checking the widget gallery/preview renders correctly (subject
  to this project's pre-existing widget-gallery visibility bug documented in `CLAUDE.md`
  — the same limitation every other widget-touching change in this project has worked
  around, not something this task needs to newly solve).
- `WeatherSnapshot.derive` itself is already covered by Item 1's test plan — no duplicate
  tests needed here.
