# Weather Fetch Consolidation — Design

**Status: approved, implementation-ready.**

## Why

The Predpoveď tab today triggers up to 3 separate Open-Meteo network calls for the same
region on a single screen load:

1. `AppState.refresh()` → `fetchSnapshot(for:)` — a dedicated endpoint call returning
   10-day averaged temp/humidity/precipitation (`WeatherSnapshot`), used to score species.
2. `AppState.refresh()` → `fetchDailyBreakdown(for:pastDays:10)` — a day-by-day array,
   used only to compute `FlushTriggerDetector.triggered`.
3. `RegionWeatherState.load(regionId:)` → `fetchDailyBreakdown(for:pastDays:30,
   forecastDays:5)` — a wider day-by-day array, used by the full weather chart and the
   Mushroom Signal hero (mini chart, rain-incoming/near-miss detection).

Calls 2 and 3 hit the same endpoint for overlapping data; call 1 could be derived from
either instead of its own round-trip. `AppState` and `RegionWeatherState` are two
independent `@ObservableObject`s with two independent fetch lifecycles, so nothing today
shares results between them — this is `KNOWN_ISSUES.md`'s "PredpovedView triggers a
second, near-duplicate weather fetch on top of AppState's own refresh."

## Goals

One network call per region load, one owner (`AppState`), one error/loading/stale-data
story shared by the shortlist, the chart, and the hero.

## Out of Scope

- `fetchSnapshots(for points: [GridPoint])` — the map's batched per-grid-point fetch
  (`MapScreenState`/`InteractiveMapView`). Entirely separate code path, untouched.
- The widget's own fetch (`ShortlistProvider` in `MushroomSignalWidget.swift`) — a
  different process on its own 12h `TimelineProvider` schedule; it legitimately needs its
  own fetch regardless of what the app does. It keeps calling `fetchSnapshot` +
  `fetchDailyBreakdown(pastDays:10)` exactly as today.
- `WatchedAlertEvaluator` always passing `flushTriggered: false` — a related but distinct
  problem (notification scoring), tracked separately as Item 3.
- Any visual/spacing change to `PredpovedView` — tracked separately as Item 9.

## Design

### One fetch, owned by `AppState`

`AppState.refresh()` makes exactly one network call:
`weatherClient.fetchDailyBreakdown(for: region, pastDays: 30, forecastDays: 5)` — the
superset window `RegionWeatherState` already used, wide enough for the 30-day chart
range, the hero's forward-looking detectors, and `FlushTriggerDetector`'s 2-7-day
lookback (unaffected by widening the window; it only inspects a fixed relative range
within whatever array it's given).

### `WeatherSnapshot` becomes derived, not fetched

The dedicated `fetchSnapshot` network call (a different Open-Meteo query shape, averaged
server-side) is replaced by a new pure function alongside the existing
`WeatherSnapshot.singleDay(...)` factory in `WeatherSnapshot.swift`:

```swift
public extension WeatherSnapshot {
    /// Derives a WeatherSnapshot from an already-fetched daily array — replaces the old
    /// dedicated fetchSnapshot network call. Averages/sums the most recent `windowDays`
    /// calendar days up to and including `asOf` (never forecast days), matching the same
    /// past-day filtering RecentWeatherWindow and WeatherRainChartView.visibleDays already
    /// use elsewhere in this codebase. Returns nil if fewer than 1 day of historical data
    /// is available (nothing to average).
    static func derive(regionId: String, from dailyWeather: [DailyWeather], windowDays: Int = 10, asOf today: Date, calendar: Calendar = .current) -> WeatherSnapshot? {
        let todayStart = calendar.startOfDay(for: today)
        let window = dailyWeather
            .filter { calendar.startOfDay(for: $0.date) <= todayStart }
            .sorted { $0.date < $1.date }
            .suffix(windowDays)
        guard !window.isEmpty else { return nil }

        let temps = window.map(\.meanTempC)
        let humidity = window.map(\.humidityPercent)
        let precipitation = window.map(\.precipitationMm)

        return WeatherSnapshot(
            regionId: regionId,
            averageTempLast10DaysC: temps.reduce(0, +) / Double(temps.count),
            averageHumidityLast10DaysPercent: humidity.reduce(0, +) / Double(humidity.count),
            totalPrecipitationLast10DaysMm: precipitation.reduce(0, +),
            fetchedAt: today
        )
    }
}
```

**Uncertainty, to verify empirically during implementation (not assumed here):** the old
`fetchSnapshot` requested `past_days=10, forecast_days=1` from Open-Meteo, which may not
produce byte-identical values to "the most recent 10 calendar days up to and including
today" computed client-side — Open-Meteo's exact `past_days`/`forecast_days` day-boundary
semantics aren't being guessed at here. The implementer should fetch real data for one
region through both the old `fetchSnapshot` path (before deleting it) and the new
`derive(...)` path and confirm the values match within a small tolerance before removing
the old code, the same empirical-check approach already used earlier this project for the
flush-frequency validation. If they diverge meaningfully, that's a decision point for the
implementer to flag, not silently paper over.

### `RegionWeatherState` deleted, folded into `AppState`

`AppState` gains:

```swift
@Published var dailyWeather: [DailyWeather] = []
```

populated by the same `refresh()` call that already sets `signals`. `PredpovedView` drops
its own `@StateObject private var weatherState = RegionWeatherState()` and the
`.task(id: regionId) { await weatherState.load(regionId: regionId) }` block entirely —
region changes already trigger `AppState.refresh()` via `selectRegion(_:)`, so no separate
trigger is needed. Every call site that read `weatherState.dailyWeather` /
`weatherState.isLoading` / `weatherState.errorMessage` reads `appState.dailyWeather` /
`appState.isLoading` / `appState.errorMessage` instead — this also collapses
`PredpovedView`'s two separate error `Text` banners (one for `appState.errorMessage`, one
for `weatherState.errorMessage`) into the one that already exists.

`RegionWeatherState.swift` and `RegionWeatherStateTests.swift` are deleted.

### Stale-data fallback extended to the daily array

Today, `AppState.refresh()`'s failure path falls back to a cached `WeatherSnapshot` via
`WeatherSnapshotCache` so the shortlist shows stale data with a caution banner instead of
going blank — but there is no equivalent for the daily array, so the chart/hero currently
just show "unavailable" on failure. This is fixed by a **second, independent cache with a
single writer**, not by touching `WeatherSnapshotCache`:

```swift
/// Persists the last successful daily weather array per region — the array-shaped
/// counterpart to WeatherSnapshotCache, added so the chart/hero can fall back to stale
/// data the same way the shortlist already does via WeatherSnapshotCache. Deliberately a
/// separate cache, not a merged one: WeatherSnapshotCache is read by the widget
/// (ShortlistProvider) and NotificationPreferences across the process boundary, and
/// neither needs the daily array — extending WeatherSnapshotCache's shape would be a
/// wider, riskier change for no benefit to those consumers. Same App Group UserDefaults
/// suite, same get/store/key pattern.
public struct DailyWeatherCache {
    private let defaults: UserDefaults

    public init?(appGroupId: String = RegionStoreConstants.appGroupId) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        self.defaults = defaults
    }

    public func dailyWeather(for regionId: String) -> [DailyWeather]? {
        guard let data = defaults.data(forKey: key(for: regionId)) else { return nil }
        return try? JSONDecoder().decode([DailyWeather].self, from: data)
    }

    public func store(_ dailyWeather: [DailyWeather], for regionId: String) {
        guard let data = try? JSONEncoder().encode(dailyWeather) else { return }
        defaults.set(data, forKey: key(for: regionId))
    }

    private func key(for regionId: String) -> String {
        "dailyWeatherCache.\(regionId)"
    }
}
```

**Why a single writer prevents the two caches from ever drifting:** `AppState.refresh()`
is the only code that writes either cache, and only on a successful fetch — it fetches
the array once, stores it in `DailyWeatherCache`, derives `WeatherSnapshot` from that
same array via `WeatherSnapshot.derive(...)`, and stores that in `WeatherSnapshotCache`.
Both writes originate from the same fetch in the same method call; neither is ever
written independently. On failure, `refresh()` reads both caches for the same region and
falls back to both together — `isShowingStaleData` covers signals, chart, and hero
uniformly instead of "signals degrade gracefully, chart doesn't."

### Updated `AppState.refresh()` shape

```swift
func refresh() async {
    let refreshID = UUID()
    currentRefreshID = refreshID
    isLoading = true
    errorMessage = nil
    defer {
        if currentRefreshID == refreshID {
            isLoading = false
        }
    }

    let region = selectedRegion
    do {
        let daily = try await weatherClient.fetchDailyBreakdown(for: region, pastDays: 30, forecastDays: 5)
        guard let weather = WeatherSnapshot.derive(regionId: region.id, from: daily, asOf: now()) else {
            throw WeatherClientError.emptyDailyData
        }
        weatherCache?.store(weather)
        dailyWeatherCache?.store(daily, for: region.id)
        let flushTriggered = FlushTriggerDetector.triggered(in: daily, asOf: now())
        let allSpecies = try SpeciesDatabase.loadAll()
        let month = Calendar.current.component(.month, from: now())
        let ranked = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: weather, month: month, flushTriggered: flushTriggered)
        guard currentRefreshID == refreshID else { return }
        signals = ranked
        dailyWeather = daily
        isShowingStaleData = false
    } catch {
        guard currentRefreshID == refreshID else { return }
        if let cachedSnapshot = weatherCache?.snapshot(for: region.id),
           let cachedDaily = dailyWeatherCache?.dailyWeather(for: region.id),
           let allSpecies = try? SpeciesDatabase.loadAll() {
            let month = Calendar.current.component(.month, from: now())
            signals = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: cachedSnapshot, month: month, flushTriggered: false)
            dailyWeather = cachedDaily
            isShowingStaleData = true
            errorMessage = "Zobrazujú sa staršie údaje z \(Self.staleTimeFormatter.string(from: cachedSnapshot.fetchedAt))."
        } else {
            signals = []
            dailyWeather = []
            isShowingStaleData = false
            errorMessage = "Nepodarilo sa načítať údaje o počasí. Skúste to znova."
        }
        logger.error("Refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
    }
}
```

**Deliberate behavior note, settled here, not left to the implementer:** the two caches
are only both present or both absent in practice (single writer, written together), but
the fallback requires *both* `cachedSnapshot` and `cachedDaily` before using either — if
only one exists (e.g. an app upgrade where `WeatherSnapshotCache` has old data from
before `DailyWeatherCache` existed), it falls through to the hard-failure branch rather
than showing signals with an empty chart. Accepted as-is: it's a one-time
first-run-after-upgrade edge case that self-heals on the very next successful fetch, and
"both stale or both fresh" is simpler to reason about than a partial-degrade state.

### Testing

- `WeatherSnapshot.derive(...)`: empty array → nil; single-day array → averages equal that
  day's values; window wider than `windowDays` → only the trailing `windowDays` count;
  forecast (future) days excluded from the average even when present in the input array.
- `DailyWeatherCache`: store/retrieve round-trip, per-region isolation, nil when nothing
  cached — mirrors `WeatherSnapshotCacheTests` exactly.
- `AppState`: existing stale-fallback tests extended to also assert `dailyWeather` reflects
  the cached array on failure, and is cleared on a hard failure with nothing cached.
- `PredpovedView`: no new tests (no SwiftUI View-level test infrastructure in this
  codebase, per established convention) — verified by building and visually checking the
  chart/hero still render correctly reading from `appState` instead of a separate
  `@StateObject`.
