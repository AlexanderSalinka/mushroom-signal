# Mushroom Signal — Trend Sparkline, Proactive Notifications, Predpoveď Tab

## Relationship to prior specs

Historical trend sparkline and proactive notifications were informally scoped in
`2026-08-05-mushroom-signal-v3-design.md` (sections 2-3), itself superseded by the
2026-08-07 roadmap consolidation. This spec resurrects both, redesigned against the current
codebase — the old spec's exact API assumptions (`fetchDailyBreakdown(forecastDays:)`, a
0-3 score scale) are stale; only its product intent (Slovak copy, contextual permission
requests, threshold-crossing-only firing) carries forward. The Predpoveď tab has no prior
spec at all — designed fresh here, from Alexander's own description mid-conversation
(2026-08-10).

## Why

Two gaps in the current app, identified while planning what to build next after the
2026-08-10 map-markers pass:

1. The UI only ever shows *today's* score for a species — no sense of whether conditions are
   improving or fading. A trend view fixes this per-species.
2. The app derives 0-4 scores everywhere but never shows the *raw weather data* behind them.
   Alexander wants a dedicated place to see "the real actual data which Mushroom Signal
   actually gets its prognosis from" — daily high/low temperature, humidity, rainfall — styled
   like a native weather app, plus what's typically in season this month regardless of the
   live weather (a reference view, not a forecast).

Additionally, none of the app's periodic refresh currently notifies the user proactively —
you have to open the app or glance at the widget to know conditions changed.

## Goals

1. **Per-species trend chart** in `SpeciesDetailView`: ~10 past days + a few forecast days of
   score, so a flush building or fading is visible at a glance.
2. **Proactive local notifications**: alert when a user-chosen species crosses a score
   threshold in a chosen region, checked on the widget's periodic background refresh —
   without the app needing to be open.
3. **A new "Predpoveď" tab** (third tab, alongside Zoznam/Mapa): raw daily weather
   (temp min/max, humidity, rainfall) for the selected region, sourced live from Open-Meteo,
   rendered as a real chart — plus a season-calendar section listing which species are
   typically in season this month for that region.

## Out of Scope

- **Personal find log / GPS pinning.** A different, larger idea from the old v3 spec, not
  part of this pass.
- **Photo-ID, watchOS, share-export, community reports, Apple Developer Program
  enrollment.** All explicitly deprioritized by Alexander (see `FUTURE_IDEAS.md`'s 2026-08-10
  entry) — Developer Program moved to end-of-Beta, watchOS to Beta-earliest, the rest
  unchanged in the backlog.
- **Push notifications via a remote server.** Local notifications only, computed on-device —
  consistent with the app's zero-backend architecture.
- **Changing `SignalAlgorithm`'s scoring weights or dimensions.** All three features reuse
  the existing scoring function; none introduce a new algorithm.
- **A settings screen beyond notification watches.** No general app-preferences screen —
  the new settings surface exists only to configure watched-species alerts.

## Design

### 1. Weather-client extension (shared foundation)

`DailyWeather` (`MushroomSignalCore/Sources/MushroomSignalCore/Weather/DailyWeather.swift`)
gains two fields:

```swift
public struct DailyWeather: Codable, Equatable, Sendable {
    public let date: Date
    public let meanTempC: Double
    public let maxTempC: Double
    public let minTempC: Double            // NEW — Predpoveď's "night and daily" temps
    public let precipitationMm: Double
    public let humidityPercent: Double     // NEW — needed for faithful per-day scoring
}
```

`WeatherClient.fetchDailyBreakdown` gains forecast-day support. Swift doesn't allow default
parameter values in protocol requirements, so the existing 2-arg call
(`fetchDailyBreakdown(for:pastDays:)`, used today by `AppState.refresh()` and
`ShortlistProvider.fetchEntry`) is preserved via a protocol extension rather than changed:

```swift
public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]
    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather]
}
public extension WeatherClient {
    func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
        try await fetchDailyBreakdown(for: region, pastDays: pastDays, forecastDays: 0)
    }
}
```

`OpenMeteoClient`'s daily query gains `temperature_2m_min` and `relative_humidity_2m_mean`
(mirroring how `max`/`mean` temp and precipitation were already added for the flush-trigger
pass), and a `forecast_days` parameter driven by the new argument (currently hardcoded `"0"`).

### 2. Trend computation (single-day scoring — a deliberate simplification)

`SignalAlgorithm.computeSignal` scores against a `WeatherSnapshot` — a 10-day rolling
aggregate (`averageTempLast10DaysC`, `averageHumidityLast10DaysPercent`,
`totalPrecipitationLast10DaysMm`). Nothing in the struct enforces those fields actually being
10-day averages; they're plain `Double`s. Rather than synthesizing a true rolling-10-day
window ending on each trend day (which would need ~20 days of daily breakdown fetched and
per-day averaging logic), each trend point is scored from that single day's own readings:

```swift
public extension WeatherSnapshot {
    /// Builds a WeatherSnapshot from ONE day's readings, reusing SignalAlgorithm's existing
    /// fit functions for trend-chart scoring. Deliberate simplification: not a true 10-day
    /// rolling aggregate, so a trend dot may not exactly equal what the shortlist showed that
    /// historical day — the value here is showing direction (improving/fading), not
    /// reproducing history exactly.
    static func singleDay(regionId: String, day: DailyWeather) -> WeatherSnapshot
}
```

New `SpeciesTrendCalculator` (pure, no I/O):

```swift
public struct TrendPoint: Equatable, Sendable {
    public let date: Date
    public let score: Int
    public let isForecast: Bool
}
public enum SpeciesTrendCalculator {
    public static func trend(
        species: Species,
        dailyWeather: [DailyWeather],
        regionId: String,
        today: Date = Date()
    ) -> [TrendPoint]
}
```

One `SignalAlgorithm.computeSignal` call per day (via `WeatherSnapshot.singleDay`), per-day
month for `calendarFit`, per-day `FlushTriggerDetector.triggered(asOf:)` for the flush bonus —
no new scoring logic, only new call sites of the existing function.

`SpeciesDetailView` gains a `Charts`-based section (`LineMark`/`PointMark`) fed by a new
`SpeciesTrendState` view-model that fetches `fetchDailyBreakdown(pastDays: 10, forecastDays: 4)`
and runs it through `SpeciesTrendCalculator`.

### 3. Proactive notifications

No code in the main app runs periodically without it being open — `AppState.refresh()` only
fires on view-appear, manual refresh, or region change. The widget's
`ShortlistProvider.getTimeline` is the only code in the repo that runs on a background cadence
(~12h, WidgetKit-budget-controlled), so it's where the threshold check must live.

New `Notifications/WatchedAlert.swift`:

```swift
public struct WatchedAlert: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(speciesId)|\(regionId)" }
    public let speciesId: String
    public let regionId: String
    public let threshold: Int          // 1...4 — old spec's "3/3" language is stale, scale is 0-4 now
    public var lastKnownScore: Int?
}
```

New `Notifications/NotificationPreferences.swift` — App-Group `UserDefaults` store mirroring
`WeatherSnapshotCache`'s pattern (failable init, JSON round-trip via `Data`, not the simpler
primitive-value `RegionStore` pattern since this persists a `Codable` array).

New `Notifications/NotificationThreshold.swift` — pure
`shouldNotify(previousScore: Int?, newScore: Int, threshold: Int) -> Bool`, firing only on an
upward crossing (not every refresh that's still above threshold — mirrors the old spec's
intent). A `nil` previous score (first-ever observation) returns `false`: adding a watch
establishes a silent baseline rather than notifying immediately, even if already above
threshold — avoids a surprise notification burst the moment a watch is added.

New `Notifications/WatchedAlertEvaluator.swift` — given the current `[WatchedAlert]`, fetches
weather per **distinct** watched `regionId`, not just the widget's own displayed region (a
watch on region Y must fire based on region Y's weather even when Y isn't currently
displayed), scores each via the existing `SignalPipeline`, returns per-alert
notify-or-not decisions. No `UNUserNotificationCenter` dependency — fully unit-testable.

Widget hook: inside `ShortlistProvider.getTimeline`'s existing `Task { ... }`, **after**
building the shortlist entry but **before** calling `completion(timeline)`, an awaited call
evaluates watched alerts and posts via `UNUserNotificationCenter.current().add(request:)`.
This ordering is load-bearing: posting after `completion()` risks WidgetKit suspending the
extension before the async call finishes, silently dropping the notification. Wrapped in its
own error handling so a notifications bug can never regress the shortlist entry itself.
Confirmed via macOS's `UNUserNotificationCenter` model: the widget extension can post using
authorization already granted to the host app — no separate extension-side authorization
request, no new entitlement needed (verified against both `.entitlements` files).

New settings surface — a toolbar gear button in `ContentView` (not a fourth tab; this is
infrequently-visited configuration, not primary navigation) opening a sheet: permission-status
affordance with a contextual "Povoliť upozornenia" request (not requested on launch), an
add-watch row (species picker, region picker, threshold picker 1-4), and a list of existing
watches with delete.

### 4. Predpoveď tab

A third `TabView` tab (`ContentView`'s `Tab` enum gains `case forecast`), region-scoped via
the same `appState.selectedRegion` binding `RegionPickerView` already provides to every tab —
no new region-selection UI.

Distinct from the trend sparkline: the sparkline shows a *mushroom score* over time for one
species; Predpoveď shows *raw weather* for the whole region. Both consume the same extended
`fetchDailyBreakdown`, rendered differently.

New `RegionWeatherState` fetches `fetchDailyBreakdown(pastDays: 10, forecastDays: 5)` for the
selected region (5 forecast days — matches what Open-Meteo's free tier reliably returns and
roughly what a native weather app shows), re-loading on region change.

New `PredpovedView`: a hero section (today's high/low + condition summary from the most
recent `DailyWeather` entry), a horizontal daily strip (`Charts`, one `BarMark`/range-style
mark per day showing min→max temp, styled after native Weather-app daily rows — past and
forecast days visually distinguished, matching `TrendPoint`'s `isForecast` convention),
separate small humidity/rainfall sections below, and a season-calendar section.

Season calendar: `SignalAlgorithm.calendarFit(species:month:)` is currently non-public — made
`public` so it can be reused directly (never reimplement scoring logic). Species with
`regionalAffinity.contains(selectedRegion.id)` are grouped by `calendarFit(...) > 0` (in
season or edge-of-season this month) vs not — pure local computation from the already-loaded
species dataset, no network call.

## Testing

- **Weather client**: extend `OpenMeteoClientTests.swift` for min-temp/humidity parsing and
  `forecastDays` query-parameter construction (`MockURLProtocol` pattern, per existing tests).
- **`SpeciesTrendCalculator`**: series length, an off-season day scores 0, a flush-bonus day,
  forecast days still score — synthetic fixtures, no network.
- **`NotificationThreshold`**: crosses-upward → true, stays-above → false, drops-then-rises →
  true, nil-baseline → false.
- **`NotificationPreferences`**: UUID-suite + `removePersistentDomain` cleanup, per
  `RegionStoreTests`' established pattern.
- **`WatchedAlertEvaluator`**: multi-region alert set with a local stub `WeatherClient`,
  verifying correct per-region fetch fan-out and notify decisions.
- **SwiftUI views** (`SpeciesDetailView`'s chart section, `PredpovedView`, notification
  settings): build + manual visual check, this project's established convention — no UI
  testing framework exists here.
- **Widget notification posting**: cannot be unit-tested — verify against a real signed
  build (add a watch guaranteed to cross threshold given current weather, force/wait for a
  widget refresh, confirm a real macOS notification appears with correct Slovak copy).

## Open Questions for the Implementation Plan

- Exact Slovak notification copy — decided during implementation, matching the app's existing
  tone (e.g. `"Hríby sa dnes darí — <species> v <region>"`).
- Exact chart styling details for `PredpovedView`'s daily strip (cell width, color treatment
  for forecast vs. past days) — a judgment call during implementation, not frozen here.
- Whether `Task 10`'s season-calendar section is a distinct visual block or interleaved with
  the daily-weather content — implementation detail, not a blocking design decision.
