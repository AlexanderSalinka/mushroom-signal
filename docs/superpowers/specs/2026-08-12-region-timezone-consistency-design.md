# Region Timezone Consistency — Design

**Status: approved, implementation-ready.** Confirmed larger in scope than
`KNOWN_ISSUES.md`'s original framing once fully swept — Alexander explicitly chose full
scope (2026-08-12) after seeing the real file count, not the narrower
data-correctness-only option.

## Why

`KNOWN_ISSUES.md`: `FlushTriggerDetector`'s date logic has a narrow UTC/local
day-boundary skew — `OpenMeteoClient` requests region-local dates (`timezone=auto`) but
parses the returned day strings with a hardcoded UTC `DateFormatter`, while several
detector functions then *also* force their internal calendar to UTC regardless of what's
passed in, and several UI call sites use `Calendar.current` (the physical device's
timezone) directly. Three different, mutually inconsistent notions of "what day is it"
coexist in the same data pipeline today.

A full sweep (`grep -rn "Calendar.current"` across all three targets) found **17 call
sites across 8 files** — not just `FlushTriggerDetector` and `PredpovedView` as the
original note described. `WeatherRainChartView` alone has 6 (the "dnes" axis label, the
today-marker lookup, the "naposledy pršalo" day-count caption).

## Goals

One consistent notion of "what day is it" — the region's own timezone — used everywhere
a `DailyWeather` date is interpreted: parsing, scoring, and every UI display, with no
mixing of UTC-forced and device-local logic anywhere in the pipeline.

## Out of Scope

- `MapScreenState.swift:70`'s month computation — the map never computes a flush trigger
  (`KNOWN_ISSUES.md`'s "Map intentionally unaffected," same precedent Item 3 follows).
  Untouched.
- `MushroomSignalWidget.swift:31`'s `nextRefresh` timeline scheduling
  (`Calendar.current.date(byAdding: .hour, value: 12, ...)`) — this picks *when the
  widget's own process next wakes up*, not an interpretation of fetched weather data.
  Correctly device-local, explicitly unchanged.
- `WatchedAlertEvaluator.evaluate`'s single global `month: Int` parameter (applied to
  every alert regardless of the alert's own region) — see the dedicated note under
  Design below; accepted as a residual simplification, not fixed here.

## Design

### `Region` and `GridPoint` gain a timezone, defaulted so most call sites don't change

```swift
// Region.swift
public struct Region: Codable, Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let nameSk: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String

    public init(id: String, nameSk: String, latitude: Double, longitude: Double, timeZoneIdentifier: String = "Europe/Bratislava") {
        self.id = id
        self.nameSk = nameSk
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public extension Region {
    /// The region's own calendar — every date/day-boundary calculation involving this
    /// region's weather data should use this instead of Calendar.current (the physical
    /// device's timezone, which may not match the region being viewed).
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return cal
    }
}
```

Same shape added to `GridPoint`:

```swift
public struct GridPoint: Identifiable, Hashable, Sendable {
    public let id: String
    public let latitude: Double
    public let longitude: Double
    public let timeZoneIdentifier: String

    public init(id: String, latitude: Double, longitude: Double, timeZoneIdentifier: String = "Europe/Bratislava") {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

public extension GridPoint {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return cal
    }
}
```

**`RegionDatabase.swift` needs no changes** — all 8 literal `Region(...)` entries already
get `"Europe/Bratislava"` from the default parameter, since that's every current
region's real timezone. `SlovakiaGrid.swift`'s many synthetic map-grid `GridPoint`
constructions are unaffected the same way. The only construction site that needs an
*explicit* (non-default) value is `WatchedAlertEvaluator.swift:32`'s
`GridPoint(id: $0.id, latitude: $0.latitude, longitude: $0.longitude)` — becomes
`GridPoint(id: $0.id, latitude: $0.latitude, longitude: $0.longitude,
timeZoneIdentifier: $0.timeZoneIdentifier)`, explicitly carrying the source region's own
value forward instead of silently relying on the default matching by coincidence.

### `OpenMeteoClient` parses dates using the point's own timezone, not hardcoded UTC

`fetchDailyBreakdown(for region: Region, ...)`'s date formatter:

```swift
// Before
dateFormatter.timeZone = TimeZone(identifier: "UTC")
// After
dateFormatter.timeZone = TimeZone(identifier: region.timeZoneIdentifier) ?? TimeZone(identifier: "UTC")
```

Same change applies to Item 3's new `fetchDailyBreakdowns(for points: [GridPoint], ...)`
— its per-point date formatter uses each `point.timeZoneIdentifier` instead of a single
hardcoded UTC formatter shared across all points in the batch. (`fetchSnapshot`/
`fetchSnapshots` need no change — their response shape has no `time` field at all; they
aggregate immediately server-side into a single number per field, never constructing a
per-day `Date`.)

### Four detector functions stop force-overriding to UTC

`FlushTriggerDetector.triggered`, `UpcomingRainDetector.nextTriggerEvent`,
`NearMissRainInsight.describe`, and `MostRecentRainfall.find` all currently do:

```swift
var utcCalendar = calendar
utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
```

immediately after receiving their `calendar: Calendar = .current` parameter — silently
discarding whatever timezone the caller passed and substituting UTC regardless. This
line is deleted from all four; each function trusts the `calendar` parameter as given.
Their signatures don't change — only the internal override is removed.

**This is the change that requires every existing test for these four functions to pass
an explicit calendar going forward** (see Testing below) — today's tests rely on the
UTC-forcing to stay deterministic regardless of what timezone the machine running the
tests happens to be in. Once that forcing is gone, a test that doesn't pass an explicit
`calendar:` argument would silently start depending on the test runner's local timezone.

### Call sites thread `region.calendar` explicitly instead of relying on the default

Every call site below currently omits `calendar:` (relying on the `= .current` default)
or uses `Calendar.current` directly, despite having a specific `Region` in scope. Each
one passes `calendar: region.calendar` (or the equivalent already-in-scope value)
instead:

- **`AppState.swift`** — `FlushTriggerDetector.triggered(in: daily, asOf: now(),
  calendar: region.calendar)`; both `Calendar.current.component(.month, from: now())`
  calls (success and stale-fallback paths) become `region.calendar.component(.month,
  from: now())`. `WeatherSnapshot.derive(...)` (Item 1) also gains an explicit
  `calendar: region.calendar` argument at this call site.
- **`WatchedAlertEvaluator.swift`** (post-Item-3) — inside the per-alert loop, both
  `WeatherSnapshot.derive(...)` and `FlushTriggerDetector.triggered(...)` pass
  `calendar: region.calendar` (the `region` already resolved earlier in the same loop
  iteration via `RegionDatabase.find(id: alert.regionId)`).
- **`ShortlistProvider.fetchEntry`** (widget, post-Item-8) — same pattern:
  `WeatherSnapshot.derive`, `FlushTriggerDetector.triggered`, and both month
  computations pass `calendar: region.calendar` / use `region.calendar.component(...)`.
- **`PredpovedView.swift`** — `todayEntry`'s `let calendar = Calendar.current` becomes
  `let calendar = region.calendar`; `inSeasonSpecies`'s `Calendar.current.component(.month,
  from: Date())` becomes `region.calendar.component(.month, from: Date())`.
- **`MushroomSignalHeroView.swift`** — `daysUntil`'s three `Calendar.current` references
  become `region.calendar` (the view already stores `region: Region`); `contextRow`'s
  month computation becomes `region.calendar.component(.month, from: today)`; the `state`
  computed property's call to `MushroomSignalHeroState.resolve(...)` gains `calendar:
  region.calendar`.
- **`MushroomSignalHeroMiniChart.swift`** — gains a new stored property, `let calendar:
  Calendar`, passed in by its caller (`MushroomSignalHeroView`, which already has
  `region.calendar` available: `MushroomSignalHeroMiniChart(dailyWeather: dailyWeather,
  today: today, calendar: region.calendar)`). Its call to
  `RecentWeatherWindow.lastSevenDaysPlusForecast(...)` gains `calendar: calendar`.
- **`WeatherRainChartView.swift`** — gains a new stored property, `let calendar:
  Calendar`, passed in by `PredpovedView`'s call site the same way. All internal
  `Calendar.current` usages (`visibleDays`, `axisMarkDates`, `todayDate`, `lastRainText`'s
  day-count) switch to the stored `calendar`. `todayDate`'s
  `Calendar.current.isDateInToday($0.date)` becomes `calendar.isDate($0.date,
  inSameDayAs: today)` (the `Calendar` API for "is this the same day" against an
  arbitrary calendar, not just the device's own "today"). `lastRainText`'s call to
  `MostRecentRainfall.find(in:asOf:)` gains `calendar: calendar`.

### `WatchedAlertEvaluator`'s single global `month` — accepted residual simplification

`WatchedAlertEvaluator.evaluate(alerts:species:weatherClient:month:now:)` takes one
`month: Int` applied to every alert regardless of that alert's own region — computed
once by the caller (`NotificationPoster.swift`) using the device's local `Date()`/
`Calendar.current`, before any per-region timezone is known. Making this fully
region-correct would mean computing `month` per-alert, inside the loop, from each
region's own calendar — a real API change to `evaluate`'s signature (dropping the
`month:` parameter entirely and deriving it internally per-region) beyond what this pass
takes on. **Accepted as-is**: since every current region shares one timezone, this can
only diverge from a "fully correct" per-region month within the ~1 hour around midnight
on the last calendar day of a month, and only once real regions with different
timezones exist — the same category of simplification `KNOWN_ISSUES.md` already accepts
for the map's flush-trigger handling.

### Testing

- **`FlushTriggerDetectorTests.swift`, `UpcomingRainDetectorTests.swift`,
  `NearMissRainInsightTests.swift`, `MostRecentRainfallTests.swift`**: every existing
  test must be updated to pass an explicit, fixed `calendar:` argument (e.g. a
  `Calendar(identifier: .gregorian)` with `timeZone = TimeZone(identifier: "UTC")!`,
  preserving each test's existing fixed-timestamp-relative-day-math exactly as it
  behaves today) instead of relying on the now-removed internal UTC-forcing. This is
  required, not optional — without it, these tests become dependent on whatever
  timezone the machine running `swift test` happens to be in, and could flake near a day
  boundary depending on CI's local time.
- **`MushroomSignalHeroStateTests.swift`**: same treatment for any test calling
  `MushroomSignalHeroState.resolve(...)` without an explicit `calendar:` — audit and add
  one to each.
- **New unit tests**: `Region.calendar`/`GridPoint.calendar` resolve
  `"Europe/Bratislava"` to the correct `TimeZone`; `OpenMeteoClient`'s date parsing
  (extend `OpenMeteoClientTests.swift`'s existing `MockURLProtocol` pattern) confirms a
  fixture date string parses to the expected instant under a non-UTC region timezone,
  not just under UTC as today's tests implicitly assume.
- **`PredpovedView`/`WeatherRainChartView`/`MushroomSignalHeroView`/
  `MushroomSignalHeroMiniChart`**: no new tests (no SwiftUI View-level test
  infrastructure in this codebase) — verified by building and visually confirming the
  chart's "dnes" marker, the hero's day-counts, and the shortlist's month-based season
  filtering all still render correctly with the device set to its normal (CET/CEST)
  timezone, which should look identical to today's behavior for any device physically in
  Slovakia — this change only becomes externally visible on a device set to a different
  timezone, which isn't practical to test on the implementer's own machine without
  actually changing system settings; a code-level trace confirming every call site now
  passes `region.calendar` is the practical verification bar for this specific case.
