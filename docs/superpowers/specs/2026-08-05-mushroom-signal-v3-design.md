> **Superseded 2026-08-07** by `2026-08-07-mushroom-signal-roadmap-design.md`, which reprioritizes this
> work below a scoring-algorithm/data-intelligence pass and consolidates it with v4 into one roadmap.
> The design below is still accurate and is referenced from the new doc — it just isn't next.

# Mushroom Signal v3 — Find Log, Notifications, Trends

## Relationship to v1/v2

v1 (merged) shipped the widget, companion app, region-based shortlist, and signal scoring. v2 (spec written, not yet built) adds the interactive map, species library, and widget resizing. This spec proposes three further additions, chosen independently rather than requested feature-by-feature — each builds on existing infrastructure (the v2 map, the weather client, the widget's periodic refresh) rather than introducing a new subsystem from scratch.

## Goals

1. **Personal find log** — a private, local journal of actual finds (species, date, map location, optional photo/notes), viewable as a distinct pin layer on the v2 map and as a chronological list.
2. **Proactive local notifications** — alert when a chosen species crosses a likelihood threshold in the selected region, instead of requiring you to check the widget.
3. **Trend timeline per species** — a compact sparkline showing a species' score trajectory across recent past days and the near-term forecast, instead of only today's single snapshot.

## Out of Scope

- Any cloud sync, backend, or account system — the find log is purely local (this app has no server anywhere; that doesn't change now).
- Automatic GPS/location capture for finds — consistent with v1's deliberate "no CoreLocation" decision, a find's location is set by tapping the v2 map, not device location.
- Social/sharing features (posting finds, following other foragers) — explicitly not wanted for a personal, non-distributed app.
- Push notifications via a remote server — these are local notifications only, computed on-device from data the app already fetches.
- Any change to the core signal-scoring algorithm, the species dataset, or v1/v2's existing screens beyond what's needed to add the map's new "My Finds" layer and a species detail view's new trend chart.

## 1. Personal Find Log

**New data model** (first genuinely persistent user-generated data in the app — everything before this is either bundled reference data or a cached forecast):

```swift
public struct Find: Identifiable, Codable, Sendable {
    public let id: UUID
    public let speciesId: String
    public let date: Date
    public let latitude: Double
    public let longitude: Double
    public let photoData: Data?      // optional, stored locally, not uploaded anywhere
    public let notes: String?
}
```

**Storage:** SwiftData (Apple's modern local persistence framework, available at the app's macOS 14.0+ deployment target) rather than a hand-rolled JSON file or repurposing `UserDefaults` — this is the first feature that needs real structured local storage with querying (e.g. "finds this season," "finds of species X"), which is exactly what SwiftData is for and what the app hasn't needed until now.

**Location capture:** tapping a point on the v2 interactive map while adding a find sets its coordinates — manual placement, not automatic GPS, consistent with v1's explicit decision to avoid `CoreLocation` entirely.

**UI:**
- A toggleable "My Finds" layer on the v2 map (distinct pin marker/color from the species heat-mosaic layer, so your own history is never confused with the forecast).
- A chronological list view of past finds (species, date, thumbnail if a photo exists).
- An add/edit flow: pick species (reuses the existing species picker UI pattern from the library), tap the map for location, optionally attach a photo and notes.
- Tapping a find (on the map or in the list) opens its detail (photo, notes, species info reused from the library).

## 2. Proactive Local Notifications

**Preferences:** a small new settings surface — which species to watch (default: none, opt-in), and a threshold (e.g. "notify when score reaches 3/3" vs "notify on any increase"). Persisted via a lightweight `NotificationPreferences` store, same `UserDefaults`-backed pattern already used by `RegionStore`, scoped to the same App Group (so both the app and the widget's timeline provider can read it).

**Trigger point:** the widget's `TimelineProvider` already recomputes every watched region's signal scores on its periodic refresh (currently every 12h) regardless of whether the app is open — this is the natural place to also check watched-species thresholds and post a local notification via `UNUserNotificationCenter`, since it means the alert doesn't depend on the app being launched. On each refresh, compare the new score for each watched species against the last-known score (persisted in the same App Group store) and fire a notification only on a threshold-crossing transition, not on every refresh that happens to still be above threshold — otherwise it would notify repeatedly for the same still-good conditions.

**Permission:** requested contextually the first time notifications are enabled in settings, not on app launch — standard `UNUserNotificationCenter.requestAuthorization`.

## 3. Trend Timeline Per Species

**Weather client extension:** `OpenMeteoClient` currently fetches `past_days=10, forecast_days=1` and immediately collapses the result into a single average temperature + total precipitation. This adds a second method that keeps the **daily** breakdown instead of collapsing it, and extends the forecast window:

```swift
public struct DailyWeather: Codable, Sendable {
    public let date: Date
    public let meanTempC: Double
    public let precipitationMm: Double
}

public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]
    func fetchDailyBreakdown(for region: Region, forecastDays: Int) async throws -> [DailyWeather]
}
```

**Trend computation:** for a given species and region, run `SignalAlgorithm.computeSignal` once per day in the returned window (each day treated as if it were "today" for calendar-fit purposes, using that day's own weather in place of the aggregate) to produce a day-by-day score series — reuses the existing scoring function entirely, no new algorithm.

**UI:** a compact sparkline (Swift Charts, available at the deployment target) in a species' detail view (reached from the library, per v2's design), showing roughly the last 10 days plus a few forecast days, so "getting better," "today is peak," or "past peak, declining" is visible at a glance instead of inferred from a single number.

## Testing

- `Find` persistence: SwiftData model round-trip (save, fetch, delete) — standard SwiftData testing pattern, in-memory container for tests.
- Notification threshold-crossing logic: pure function (`previousScore`, `newScore`, `threshold` → `shouldNotify: Bool`), unit-testable in isolation, covering "crosses upward → true," "stays above → false (already notified)," "drops back down → false."
- `fetchDailyBreakdown`: unit test with a mocked multi-day JSON response, verifying correct per-day parsing (extends the existing `MockURLProtocol` pattern).
- Trend computation (per-day `computeSignal` series): unit test with a fixed species and a synthetic multi-day weather series, verifying the output series length and that known peak/off-season days score as expected — same style as the existing `SignalAlgorithmTests`.
- SwiftUI views (find add/edit flow, map pin layer, sparkline): verified via build + Xcode previews, same as all prior UI work in this project — no meaningful unit-test surface for pure layout.

## Open Questions for the Implementation Plan

- Exact notification copy/wording (Slovak, matching the rest of the app) — decided during implementation, not frozen here.
- Whether `Find` photos should have any size/compression limit before persisting as `Data` in SwiftData — a reasonable cap (e.g. downscale before storing) is worth adding during implementation to avoid unbounded local storage growth, not a hard requirement to design now.
- How many forecast days is actually useful to show in the trend sparkline (proposed 3-5, matching typical forecast reliability) — a judgment call to make while building, not a blocking decision.
