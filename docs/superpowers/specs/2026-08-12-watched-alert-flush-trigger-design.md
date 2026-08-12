# WatchedAlertEvaluator Flush-Trigger Fix — Design

**Status: approved, implementation-ready.**

## Why

`WatchedAlertEvaluator.evaluate` always scores watched species with `flushTriggered:
false` (`WatchedAlertEvaluator.swift`, hardcoded literal). Its own doc comment already
names the reason: it batches weather via `fetchSnapshots(for points:)`, which only
requests aggregated fields (mean temp/humidity, precip sum) — not the per-day max-temp/
precip data `FlushTriggerDetector.triggered` needs. So right after a real
flush-triggering rain event, a watched species can score visibly lower via the
notification path than the widget's own live shortlist shows for the same region/day —
the two code paths silently disagree about whether a flush is happening.

## Goals

`WatchedAlertEvaluator` computes a real `flushTriggered` per watched region, matching
what `AppState`/the widget's own shortlist would show, while preserving its existing
"one batched fetch per distinct region, not per alert" design principle.

## Out of Scope

- The map's `fetchSnapshots` usage (`MapScreenState`/`InteractiveMapView`) —
  `KNOWN_ISSUES.md`'s "Map intentionally unaffected" stands; this fix doesn't touch it.
- Anything about *when* `WatchedAlertEvaluator.evaluate` runs (its widget-timeline
  cadence, `NotificationPoster.swift`) — only what data it evaluates against.

## Design

### One new batched fetch, mirroring `fetchSnapshots`' existing pattern

`WeatherClient` gains a new protocol method — a daily-breakdown counterpart to the
existing multi-point `fetchSnapshots`:

```swift
func fetchDailyBreakdowns(for points: [GridPoint], pastDays: Int) async throws -> [String: [DailyWeather]]
```

`OpenMeteoClient`'s implementation mirrors `fetchSnapshots`' single-request,
comma-joined-lat/lon batching (Open-Meteo returns a JSON array, one entry per point, for
a multi-coordinate request — already the exact mechanism `fetchSnapshots` uses), but
requests the daily-breakdown field set (`temperature_2m_max,temperature_2m_min,
temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum`) that
`fetchDailyBreakdown` already uses for a single point, and decodes an array of
`OpenMeteoDailyResponse` instead of a single one:

```swift
public func fetchDailyBreakdowns(for points: [GridPoint], pastDays: Int) async throws -> [String: [DailyWeather]] {
    guard !points.isEmpty else { return [:] }

    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [
        URLQueryItem(name: "latitude", value: points.map { String($0.latitude) }.joined(separator: ",")),
        URLQueryItem(name: "longitude", value: points.map { String($0.longitude) }.joined(separator: ",")),
        URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum"),
        URLQueryItem(name: "past_days", value: String(pastDays)),
        URLQueryItem(name: "forecast_days", value: "0"),
        URLQueryItem(name: "timezone", value: "auto")
    ]

    let (data, response) = try await session.data(from: components.url!)
    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw WeatherClientError.invalidResponse
    }

    let decoded = try JSONDecoder().decode([OpenMeteoDailyResponse].self, from: data)
    guard decoded.count == points.count else {
        throw WeatherClientError.invalidResponse
    }

    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    dateFormatter.timeZone = TimeZone(identifier: "UTC")

    var result: [String: [DailyWeather]] = [:]
    for (point, pointResponse) in zip(points, decoded) {
        var days: [DailyWeather] = []
        for index in pointResponse.daily.time.indices {
            guard index < pointResponse.daily.temperature2mMax.count,
                  index < pointResponse.daily.temperature2mMin.count,
                  index < pointResponse.daily.temperature2mMean.count,
                  index < pointResponse.daily.relativeHumidity2mMean.count,
                  index < pointResponse.daily.precipitationSum.count,
                  let date = dateFormatter.date(from: pointResponse.daily.time[index]),
                  let maxTemp = pointResponse.daily.temperature2mMax[index],
                  let minTemp = pointResponse.daily.temperature2mMin[index],
                  let meanTemp = pointResponse.daily.temperature2mMean[index],
                  let humidity = pointResponse.daily.relativeHumidity2mMean[index],
                  let precipitation = pointResponse.daily.precipitationSum[index] else { continue }
            days.append(DailyWeather(date: date, meanTempC: meanTemp, maxTempC: maxTemp, minTempC: minTemp, precipitationMm: precipitation, humidityPercent: humidity))
        }
        result[point.id] = days
    }
    return result
}
```

### `WatchedAlertEvaluator` unifies to one fetch (Alexander's call, 2026-08-12)

Rather than keeping `fetchSnapshots` and adding a second call just for the flush check,
`evaluate` switches entirely to the new batched daily-breakdown fetch and derives both
the score-relevant snapshot AND the flush trigger from the same data — the same "derive,
don't double-fetch" pattern the weather-fetch-consolidation design (Item 1) establishes
for `AppState`. This makes `WatchedAlertEvaluator` depend on
`WeatherSnapshot.derive(regionId:from:windowDays:asOf:)` existing, which Item 1 adds —
**this spec should be implemented after Item 1 lands**, matching the already-planned
brainstorm order.

```swift
public static func evaluate(
    alerts: [WatchedAlert],
    species: [Species],
    weatherClient: WeatherClient,
    month: Int,
    now: Date = Date()
) async -> [WatchedAlertUpdate] {
    guard !alerts.isEmpty else { return [] }

    let speciesByID = Dictionary(uniqueKeysWithValues: species.map { ($0.id, $0) })
    let distinctRegions = Set(alerts.map(\.regionId)).compactMap { RegionDatabase.find(id: $0) }
    let points = distinctRegions.map { GridPoint(id: $0.id, latitude: $0.latitude, longitude: $0.longitude) }
    let dailyByRegion = (try? await weatherClient.fetchDailyBreakdowns(for: points, pastDays: 10)) ?? [:]

    var updates: [WatchedAlertUpdate] = []
    for alert in alerts {
        guard let speciesForAlert = speciesByID[alert.speciesId],
              let region = RegionDatabase.find(id: alert.regionId),
              let dailyWeather = dailyByRegion[alert.regionId],
              let snapshot = WeatherSnapshot.derive(regionId: alert.regionId, from: dailyWeather, asOf: now) else { continue }
        let flushTriggered = FlushTriggerDetector.triggered(in: dailyWeather, asOf: now)
        guard let signal = SignalPipeline.rankedSignals(species: [speciesForAlert], region: region, weather: snapshot, month: month, flushTriggered: flushTriggered, limit: 1).first else { continue }
        let notify = NotificationThreshold.shouldNotify(previousScore: alert.lastKnownScore, newScore: signal.score, threshold: alert.threshold)
        updates.append(WatchedAlertUpdate(alert: alert, newScore: signal.score, shouldNotify: notify))
    }
    return updates
}
```

`pastDays: 10` (not 30, unlike `AppState`'s window) — `WatchedAlertEvaluator` never
renders a chart or does forward-looking rain detection, it only needs enough trailing
history for `WeatherSnapshot.derive`'s 10-day window and `FlushTriggerDetector`'s 2-7-day
lookback. The added `now: Date = Date()` parameter defaults to the real caller's existing
behavior (`NotificationPoster.swift` is unchanged) while making the evaluation instant
injectable in tests, matching the `now: () -> Date` pattern `AppState` already uses.

`fetchSnapshots(for points:)` itself is **not removed** — the map still uses it. Only
`WatchedAlertEvaluator` stops calling it.

### Protocol-conformance blast radius

Adding a new `WeatherClient` protocol requirement breaks every existing conformer until
each implements it. Confirmed exactly 5 files conform to `WeatherClient` today:

1. `OpenMeteoClient.swift` — the real implementation (above).
2. `MushroomSignalCore/Tests/MushroomSignalCoreTests/WatchedAlertEvaluatorTests.swift`'s
   `StubClient` — test-only, needs a `fetchDailyBreakdowns` stub returning injectable
   per-region `[DailyWeather]` (replacing/extending its current `snapshots`-only fixture
   shape, since tests will now need to supply daily arrays instead of pre-built
   snapshots for most cases).
3. `MushroomSignalTests/StubWeatherClient.swift`'s `StubWeatherClient` (actor) — already
   has a `dailyWeather`/`dailyShouldThrow` fixture pair for the single-point
   `fetchDailyBreakdown`; add a parallel `gridDailyWeather: [String: [DailyWeather]]` /
   `gridDailyShouldThrow: Bool` pair for the new batched method, following the exact
   naming convention its existing `gridSnapshots`/`gridShouldThrow` pair already
   established for `fetchSnapshots`.
4. `MushroomSignalTests/StubWeatherClient.swift`'s `DelayedWeatherClient` (actor) — add a
   trivial `fetchDailyBreakdowns` returning `[:]`, matching its existing trivial
   `fetchSnapshots`/`fetchDailyBreakdown` stubs (this type exists to test refresh-timing/
   cancellation, not weather content).
5. `MushroomSignalTests/AppStateTests.swift`'s `TriggeringWeatherClient` (a local struct
   inside `testRefreshAppliesFlushTriggerFromDailyBreakdown`) — this test exercises
   `AppState.refresh()`, never the grid/batch path, and its existing `fetchSnapshots`
   stub already just returns `[:]` unconditionally. Add `fetchDailyBreakdowns` returning
   `[:]` the same way — no new fixture data needed.

### Testing

- `OpenMeteoClient.fetchDailyBreakdowns`: extend `OpenMeteoClientTests.swift`'s existing
  `MockURLProtocol` pattern — multi-point request round-trips to a `[String: [DailyWeather]]`
  keyed by point id, matching how `fetchSnapshots`' existing tests (if any — confirm during
  implementation) or `fetchDailyBreakdown`'s existing tests are structured.
- `WatchedAlertEvaluator`: extend the existing 5 tests in `WatchedAlertEvaluatorTests.swift`
  to build `StubClient` fixtures from `[DailyWeather]` arrays instead of pre-built
  `WeatherSnapshot`s. Add at least one new test asserting a watched alert's score reflects
  `flushTriggered: true` when the stubbed daily data contains a qualifying trigger day
  2-7 days before the injected `now`, using the same `daysAgo`-style fixture helper
  pattern `FlushTriggerDetectorTests.swift` already established.
