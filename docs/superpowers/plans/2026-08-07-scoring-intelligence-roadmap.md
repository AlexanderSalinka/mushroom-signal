# Scoring Intelligence Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the mushroom-signal scoring algorithm from 3 asymmetric factors to 4 equal-weight factors (calendar/temperature/humidity/rainfall), add a real warm-day+rain "flush trigger," widen the displayed score from 0-3 to 0-4, and enrich the 27-species dataset with researched humidity data — per `docs/superpowers/specs/2026-08-07-mushroom-signal-roadmap-design.md`.

**Architecture:** `MushroomSignalCore`'s `WeatherClient` gains a humidity field on the existing snapshot fetch and a new per-day breakdown fetch (needed only to detect the flush trigger, which must inspect specific days, not an average). `SignalAlgorithm.computeSignal` gains a `flushTriggered: Bool` parameter that callers compute via a new `FlushTriggerDetector` pure function from the daily breakdown. The map's `DominantSpeciesResolver` always passes `flushTriggered: false` — per the spec, the map is intentionally left untouched, and evaluating the trigger per grid point would need a batched daily-breakdown endpoint that's out of scope.

**Tech Stack:** Swift, Swift Package Manager (`MushroomSignalCore`), XCTest, Open-Meteo REST API (no auth).

## Global Constraints

- No scraping any single site (nahuby.sk or otherwise) for species data — synthesize from multiple general mycological sources, write fresh. (Spec §5, restated from `CLAUDE.md`'s existing hard constraint.)
- All new UI/display changes route through `DesignSystem` — no new ad hoc literals. (Existing project-wide `CLAUDE.md` constraint.)
- Every commit must leave `swift test --package-path MushroomSignalCore` and the Xcode-level `MushroomSignalTests` target green — no intermediate broken states.
- Out-of-season species (calendar fit `0.0`) always score `0`, regardless of the other three dimensions — the one deliberate exception to pure equal-weighting. (Spec §1.)

---

## Task 1: Add Humidity to `WeatherSnapshot` and `OpenMeteoClient`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift`
- Modify (call-site updates only, listed below): `MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift`, `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift`, `MushroomSignalCore/Tests/MushroomSignalCoreTests/WeatherSnapshotCacheTests.swift`, `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift`, `MushroomSignalTests/StubWeatherClient.swift`, `MushroomSignalTests/MapScreenStateTests.swift`, `MushroomSignalTests/AppStateTests.swift`

**Interfaces:**
- Produces: `WeatherSnapshot.averageHumidityLast10DaysPercent: Double` (new field, inserted between `averageTempLast10DaysC` and `totalPrecipitationLast10DaysMm` in both the struct and its `init`).

- [ ] **Step 1: Update the `WeatherSnapshot` struct**

Replace the full contents of `WeatherSnapshot.swift`:

```swift
import Foundation

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public let regionId: String
    public let averageTempLast10DaysC: Double
    public let averageHumidityLast10DaysPercent: Double
    public let totalPrecipitationLast10DaysMm: Double
    public let fetchedAt: Date

    public init(regionId: String, averageTempLast10DaysC: Double, averageHumidityLast10DaysPercent: Double, totalPrecipitationLast10DaysMm: Double, fetchedAt: Date) {
        self.regionId = regionId
        self.averageTempLast10DaysC = averageTempLast10DaysC
        self.averageHumidityLast10DaysPercent = averageHumidityLast10DaysPercent
        self.totalPrecipitationLast10DaysMm = totalPrecipitationLast10DaysMm
        self.fetchedAt = fetchedAt
    }
}
```

- [ ] **Step 2: Update every test call site to compile again**

This alone will not compile yet (production code isn't updated), but do it now so Step 3-4's production changes and Step 5's test changes land together correctly. Update each line below to insert `averageHumidityLast10DaysPercent:` in the same position as the struct above, right after `averageTempLast10DaysC:`. Use `75.0` as the value at every site below (a plausible mid-range humidity, not meaningful to these tests — they don't test humidity):

`MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift:6`
```swift
    private let warmWetWeather = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 16, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: .now)
```

`MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift:5`
```swift
    private let warmWetWeather = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 16, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: .now)
```

`MushroomSignalCore/Tests/MushroomSignalCoreTests/WeatherSnapshotCacheTests.swift:18,29,30,43,44` — insert `averageHumidityLast10DaysPercent: 75, ` after each `averageTempLast10DaysC: <n>,` on those five lines (values 14.5/14.5/18/10/20 stay unchanged; humidity cache round-tripping isn't semantically tested there, `WeatherSnapshot.Equatable` conformance already covers it once the field exists).

`MushroomSignalTests/StubWeatherClient.swift:40`
```swift
        return WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
```
Also update `DelayedWeatherClient.fetchSnapshot` in the same file (the `return WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)` line inside its success branch) the same way.

`MushroomSignalTests/MapScreenStateTests.swift:8,45`
```swift
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
```

`MushroomSignalTests/AppStateTests.swift:9`
```swift
        let snapshot = WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
```

`MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift` — **do not edit yet**. This whole file is rewritten from scratch in Task 5; editing it now would be wasted work.

- [ ] **Step 3: Update `OpenMeteoClientTests.swift` for the new humidity field**

In `testFetchSnapshotParsesAverageTempAndTotalPrecipitation`, replace the JSON and assertions:

```swift
    func testFetchSnapshotParsesAverageTempAndTotalPrecipitation() async throws {
        let json = """
        { "daily": { "temperature_2m_mean": [10.0, 12.0, 14.0], "relative_humidity_2m_mean": [60.0, 70.0, 80.0], "precipitation_sum": [0.0, 5.0, 3.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let snapshot = try await client.fetchSnapshot(for: region)

        XCTAssertEqual(snapshot.averageTempLast10DaysC, 12.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.averageHumidityLast10DaysPercent, 70.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalPrecipitationLast10DaysMm, 8.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.regionId, "zilinsky")
    }
```

In `testFetchSnapshotIgnoresNullDailyValues`, replace the JSON and add a humidity assertion:

```swift
    func testFetchSnapshotIgnoresNullDailyValues() async throws {
        let json = """
        { "daily": { "temperature_2m_mean": [10.0, null, 14.0], "relative_humidity_2m_mean": [60.0, null, 80.0], "precipitation_sum": [null, 5.0, 3.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let snapshot = try await client.fetchSnapshot(for: region)

        XCTAssertEqual(snapshot.averageTempLast10DaysC, 12.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.averageHumidityLast10DaysPercent, 70.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalPrecipitationLast10DaysMm, 8.0, accuracy: 0.001)
    }
```

In `testFetchSnapshotThrowsOnEmptyDailyData`, add `"relative_humidity_2m_mean": []` to the JSON (keep the rest unchanged):

```swift
        let json = """
        { "daily": { "temperature_2m_mean": [], "relative_humidity_2m_mean": [], "precipitation_sum": [] } }
        """.data(using: .utf8)!
```

In `testFetchSnapshotsDecodesMultiLocationArrayInOrder`, replace the JSON and add humidity assertions:

```swift
    func testFetchSnapshotsDecodesMultiLocationArrayInOrder() async throws {
        let points = [
            GridPoint(id: "grid-00", latitude: 48.1, longitude: 17.1),
            GridPoint(id: "grid-01", latitude: 49.2, longitude: 18.7)
        ]
        let json = """
        [
          { "daily": { "temperature_2m_mean": [10.0, 12.0], "relative_humidity_2m_mean": [50.0, 60.0], "precipitation_sum": [1.0, 3.0] } },
          { "daily": { "temperature_2m_mean": [20.0, 22.0], "relative_humidity_2m_mean": [70.0, 80.0], "precipitation_sum": [5.0, 5.0] } }
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchSnapshots(for: points)

        XCTAssertEqual(result.count, 2)
        guard let snapshot0 = result["grid-00"] else { XCTFail("Missing grid-00"); return }
        XCTAssertEqual(snapshot0.averageTempLast10DaysC, 11.0, accuracy: 0.001)
        XCTAssertEqual(snapshot0.averageHumidityLast10DaysPercent, 55.0, accuracy: 0.001)
        XCTAssertEqual(snapshot0.totalPrecipitationLast10DaysMm, 4.0, accuracy: 0.001)
        guard let snapshot1 = result["grid-01"] else { XCTFail("Missing grid-01"); return }
        XCTAssertEqual(snapshot1.averageTempLast10DaysC, 21.0, accuracy: 0.001)
        XCTAssertEqual(snapshot1.averageHumidityLast10DaysPercent, 75.0, accuracy: 0.001)
    }
```

In `testFetchSnapshotsOmitsPointsWithEmptyDailyData`, add `"relative_humidity_2m_mean"` arrays matching each point's other array lengths:

```swift
        let json = """
        [
          { "daily": { "temperature_2m_mean": [], "relative_humidity_2m_mean": [], "precipitation_sum": [] } },
          { "daily": { "temperature_2m_mean": [20.0], "relative_humidity_2m_mean": [65.0], "precipitation_sum": [5.0] } }
        ]
        """.data(using: .utf8)!
```

- [ ] **Step 4: Run the test suite to confirm these new/updated tests fail correctly**

Run: `swift test --package-path MushroomSignalCore --filter OpenMeteoClientTests`
Expected: FAIL — `averageHumidityLast10DaysPercent` doesn't exist on `WeatherSnapshot` yet (compile error), or once Step 1 alone is in place, decode errors from the missing production-side humidity handling.

- [ ] **Step 5: Implement humidity fetching in `OpenMeteoClient`**

Replace the full contents of `OpenMeteoClient.swift`:

```swift
import Foundation

public enum WeatherClientError: Error, Equatable {
    case invalidResponse
    case emptyDailyData
}

public struct OpenMeteoClient: WeatherClient {
    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared, baseURL: URL = URL(string: "https://api.open-meteo.com/v1/forecast")!) {
        self.session = session
        self.baseURL = baseURL
    }

    public func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(region.latitude)),
            URLQueryItem(name: "longitude", value: String(region.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum"),
            URLQueryItem(name: "past_days", value: "10"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        let temps = decoded.daily.temperature2mMean.compactMap { $0 }
        let humidity = decoded.daily.relativeHumidity2mMean.compactMap { $0 }
        let precipitation = decoded.daily.precipitationSum.compactMap { $0 }
        guard !temps.isEmpty, !humidity.isEmpty, !precipitation.isEmpty else {
            throw WeatherClientError.emptyDailyData
        }

        let averageTemp = temps.reduce(0, +) / Double(temps.count)
        let averageHumidity = humidity.reduce(0, +) / Double(humidity.count)
        let totalPrecipitation = precipitation.reduce(0, +)

        return WeatherSnapshot(
            regionId: region.id,
            averageTempLast10DaysC: averageTemp,
            averageHumidityLast10DaysPercent: averageHumidity,
            totalPrecipitationLast10DaysMm: totalPrecipitation,
            fetchedAt: Date()
        )
    }

    public func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        guard !points.isEmpty else { return [:] }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: points.map { String($0.latitude) }.joined(separator: ",")),
            URLQueryItem(name: "longitude", value: points.map { String($0.longitude) }.joined(separator: ",")),
            URLQueryItem(name: "daily", value: "temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum"),
            URLQueryItem(name: "past_days", value: "10"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode([OpenMeteoResponse].self, from: data)
        guard decoded.count == points.count else {
            throw WeatherClientError.invalidResponse
        }

        var result: [String: WeatherSnapshot] = [:]
        for (point, pointResponse) in zip(points, decoded) {
            let temps = pointResponse.daily.temperature2mMean.compactMap { $0 }
            let humidity = pointResponse.daily.relativeHumidity2mMean.compactMap { $0 }
            let precipitation = pointResponse.daily.precipitationSum.compactMap { $0 }
            guard !temps.isEmpty, !humidity.isEmpty, !precipitation.isEmpty else { continue }
            result[point.id] = WeatherSnapshot(
                regionId: point.id,
                averageTempLast10DaysC: temps.reduce(0, +) / Double(temps.count),
                averageHumidityLast10DaysPercent: humidity.reduce(0, +) / Double(humidity.count),
                totalPrecipitationLast10DaysMm: precipitation.reduce(0, +),
                fetchedAt: Date()
            )
        }
        return result
    }

    public func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(region.latitude)),
            URLQueryItem(name: "longitude", value: String(region.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_mean,precipitation_sum"),
            URLQueryItem(name: "past_days", value: String(pastDays)),
            URLQueryItem(name: "forecast_days", value: "0"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        let (data, response) = try await session.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw WeatherClientError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(OpenMeteoDailyResponse.self, from: data)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        var result: [DailyWeather] = []
        for index in decoded.daily.time.indices {
            guard let date = dateFormatter.date(from: decoded.daily.time[index]),
                  let maxTemp = decoded.daily.temperature2mMax[index],
                  let meanTemp = decoded.daily.temperature2mMean[index],
                  let precipitation = decoded.daily.precipitationSum[index] else { continue }
            result.append(DailyWeather(date: date, meanTempC: meanTemp, maxTempC: maxTemp, precipitationMm: precipitation))
        }
        return result
    }
}

struct OpenMeteoResponse: Codable {
    struct Daily: Codable {
        let temperature2mMean: [Double?]
        let relativeHumidity2mMean: [Double?]
        let precipitationSum: [Double?]

        enum CodingKeys: String, CodingKey {
            case temperature2mMean = "temperature_2m_mean"
            case relativeHumidity2mMean = "relative_humidity_2m_mean"
            case precipitationSum = "precipitation_sum"
        }
    }
    let daily: Daily
}

struct OpenMeteoDailyResponse: Codable {
    struct Daily: Codable {
        let time: [String]
        let temperature2mMax: [Double?]
        let temperature2mMean: [Double?]
        let precipitationSum: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMean = "temperature_2m_mean"
            case precipitationSum = "precipitation_sum"
        }
    }
    let daily: Daily
}
```

Note: `fetchDailyBreakdown` and `DailyWeather` won't compile yet — `DailyWeather` and the `WeatherClient` protocol method are added in Task 2. This step still leaves the build broken until Task 2 lands; that's expected and is the one intentional exception to "every commit stays green" in this plan, because `WeatherSnapshot` and `WeatherClient`/`DailyWeather` are mutually necessary and were designed together. **Do not commit after this step** — continue straight to Task 2 in the same working session, then commit both together at the end of Task 2.

---

## Task 2: Add `DailyWeather` and `fetchDailyBreakdown` to `WeatherClient`

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/DailyWeather.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift`
- Modify: `MushroomSignalTests/StubWeatherClient.swift`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift`

**Interfaces:**
- Consumes: nothing new from other tasks.
- Produces: `DailyWeather` (`date: Date`, `meanTempC: Double`, `maxTempC: Double`, `precipitationMm: Double`), `WeatherClient.fetchDailyBreakdown(for:pastDays:) async throws -> [DailyWeather]`. Task 3's `FlushTriggerDetector` consumes `[DailyWeather]`.

- [ ] **Step 1: Create `DailyWeather.swift`**

```swift
import Foundation

public struct DailyWeather: Codable, Equatable, Sendable {
    public let date: Date
    public let meanTempC: Double
    public let maxTempC: Double
    public let precipitationMm: Double

    public init(date: Date, meanTempC: Double, maxTempC: Double, precipitationMm: Double) {
        self.date = date
        self.meanTempC = meanTempC
        self.maxTempC = maxTempC
        self.precipitationMm = precipitationMm
    }
}
```

- [ ] **Step 2: Add the method to the `WeatherClient` protocol**

Replace the full contents of `WeatherClient.swift`:

```swift
import Foundation

public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]
    func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather]
}
```

- [ ] **Step 3: Build to confirm `OpenMeteoClient` now satisfies the protocol**

Run: `swift build --package-path MushroomSignalCore`
Expected: SUCCEED — `OpenMeteoClient.fetchDailyBreakdown` was already written in Task 1 Step 5 and now has a protocol method + `DailyWeather` type to satisfy.

- [ ] **Step 4: Implement `fetchDailyBreakdown` on the test doubles so `MushroomSignalTests` compiles**

In `MushroomSignalTests/StubWeatherClient.swift`, add to `StubWeatherClient` (inside the `actor StubWeatherClient: WeatherClient` body, alongside the existing methods):

```swift
    func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
        []
    }
```

Add the same method to `DelayedWeatherClient`:

```swift
    func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
        []
    }
```

- [ ] **Step 5: Write the failing test for `fetchDailyBreakdown`**

Add to `OpenMeteoClientTests.swift`:

```swift
    func testFetchDailyBreakdownParsesPerDayValues() async throws {
        let json = """
        { "daily": { "time": ["2026-08-01", "2026-08-02"], "temperature_2m_max": [28.0, 30.0], "temperature_2m_mean": [22.0, 24.0], "precipitation_sum": [0.0, 5.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchDailyBreakdown(for: region, pastDays: 2)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].maxTempC, 28.0, accuracy: 0.001)
        XCTAssertEqual(result[0].meanTempC, 22.0, accuracy: 0.001)
        XCTAssertEqual(result[0].precipitationMm, 0.0, accuracy: 0.001)
        XCTAssertEqual(result[1].maxTempC, 30.0, accuracy: 0.001)
        XCTAssertEqual(result[1].precipitationMm, 5.0, accuracy: 0.001)

        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        let components = utcCalendar.dateComponents([.year, .month, .day], from: result[0].date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 1)
    }

    func testFetchDailyBreakdownSkipsDaysWithNullValues() async throws {
        let json = """
        { "daily": { "time": ["2026-08-01", "2026-08-02"], "temperature_2m_max": [28.0, null], "temperature_2m_mean": [22.0, 24.0], "precipitation_sum": [0.0, 5.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchDailyBreakdown(for: region, pastDays: 2)

        XCTAssertEqual(result.count, 1, "a day with any null field should be skipped, not crash or default to 0")
    }
```

- [ ] **Step 6: Run the new tests to confirm they pass**

Run: `swift test --package-path MushroomSignalCore --filter OpenMeteoClientTests`
Expected: PASS — all `OpenMeteoClientTests` tests, including the two new ones and Task 1's humidity updates.

- [ ] **Step 7: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS — this is the first point since Task 1 Step 5 where the whole package compiles and passes again.

- [ ] **Step 8: Commit Task 1 and Task 2 together**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Weather/ MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/WeatherSnapshotCacheTests.swift MushroomSignalTests/StubWeatherClient.swift MushroomSignalTests/MapScreenStateTests.swift MushroomSignalTests/AppStateTests.swift
git commit -m "feat: add humidity data and daily weather breakdown to WeatherClient"
```

---

## Task 3: `FlushTriggerDetector`

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/FlushTriggerDetector.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/FlushTriggerDetectorTests.swift`

**Interfaces:**
- Consumes: `DailyWeather` (Task 2).
- Produces: `FlushTriggerDetector.triggered(in:asOf:calendar:) -> Bool`. Task 5's `SignalAlgorithm` consumes this indirectly — callers (Tasks 8-9) compute the `Bool` and pass it into `computeSignal`'s new `flushTriggered` parameter.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MushroomSignalCore

final class FlushTriggerDetectorTests: XCTestCase {
    private let today = Date(timeIntervalSince1970: 1_754_524_800) // 2026-08-07 00:00:00 UTC

    private func daysAgo(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(-Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, precipitationMm: precipitationMm)
    }

    func testTriggersOnQualifyingDayTwoDaysAgo() {
        let days = [daysAgo(2, maxTempC: 26.0, precipitationMm: 1.0)]
        XCTAssertTrue(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testTriggersOnQualifyingDaySevenDaysAgo() {
        let days = [daysAgo(7, maxTempC: 30.0, precipitationMm: 5.0)]
        XCTAssertTrue(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testDoesNotTriggerOneDayAgo() {
        let days = [daysAgo(1, maxTempC: 30.0, precipitationMm: 5.0)]
        XCTAssertFalse(FlushTriggerDetector.triggered(in: days, asOf: today), "one day ago is outside the 2-7 day lag window")
    }

    func testDoesNotTriggerEightDaysAgo() {
        let days = [daysAgo(8, maxTempC: 30.0, precipitationMm: 5.0)]
        XCTAssertFalse(FlushTriggerDetector.triggered(in: days, asOf: today), "eight days ago is outside the 2-7 day lag window")
    }

    func testDoesNotTriggerBelowTemperatureThreshold() {
        let days = [daysAgo(3, maxTempC: 25.9, precipitationMm: 5.0)]
        XCTAssertFalse(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testDoesNotTriggerWithoutRain() {
        let days = [daysAgo(3, maxTempC: 30.0, precipitationMm: 0.0)]
        XCTAssertFalse(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testTriggersIfAnyDayInWindowQualifiesEvenIfOthersDont() {
        let days = [
            daysAgo(2, maxTempC: 10.0, precipitationMm: 0.0),
            daysAgo(5, maxTempC: 27.0, precipitationMm: 2.0),
            daysAgo(6, maxTempC: 10.0, precipitationMm: 0.0)
        ]
        XCTAssertTrue(FlushTriggerDetector.triggered(in: days, asOf: today))
    }

    func testEmptyArrayDoesNotTrigger() {
        XCTAssertFalse(FlushTriggerDetector.triggered(in: [], asOf: today))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --package-path MushroomSignalCore --filter FlushTriggerDetectorTests`
Expected: FAIL — `FlushTriggerDetector` doesn't exist.

- [ ] **Step 3: Implement `FlushTriggerDetector`**

```swift
import Foundation

/// A day 2-7 days ago with a maximum temperature of at least 26°C and measurable rain
/// reliably precedes a mushroom flush within about a week — a real foraging pattern, not
/// an arbitrary rule. See the roadmap spec §1.
public enum FlushTriggerDetector {
    public static func triggered(in dailyWeather: [DailyWeather], asOf today: Date, calendar: Calendar = .current) -> Bool {
        var utcCalendar = calendar
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let todayStart = utcCalendar.startOfDay(for: today)

        return dailyWeather.contains { day in
            let dayStart = utcCalendar.startOfDay(for: day.date)
            guard let daysAgo = utcCalendar.dateComponents([.day], from: dayStart, to: todayStart).day else { return false }
            guard (2...7).contains(daysAgo) else { return false }
            return day.maxTempC >= 26.0 && day.precipitationMm > 0.0
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter FlushTriggerDetectorTests`
Expected: PASS — all 8 tests.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/FlushTriggerDetector.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/FlushTriggerDetectorTests.swift
git commit -m "feat: add FlushTriggerDetector for the warm-day-plus-rain scoring signal"
```

---

## Task 4: Add Humidity Fields to `Species`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Models/Species.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift`, `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift`, `MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift`
- Modify: `MushroomSignalWidget/ShortlistWidgetView.swift`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesDataTests.swift`

**Interfaces:**
- Produces: `Species.idealHumidityMinPercent: Double`, `Species.idealHumidityMaxPercent: Double`. Task 5's `humidityFit` consumes these.

**Note on `species.json` in this task:** every one of the 27 entries gets a **uniform placeholder** `idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90` here — deliberately temporary, so decoding and every existing test stays green while the schema change lands. Task 11 replaces these with real per-species researched values. This is not a "TBD" left in code — it's a concrete, working interim value with a concrete follow-up task, the same pattern the spec itself proposed.

- [ ] **Step 1: Update the `Species` struct**

Replace the full contents of `Species.swift`:

```swift
import Foundation

public enum Edibility: String, Codable, Equatable, Sendable {
    case edible
    case caution
    case poisonous
}

public enum RainfallSensitivity: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct Species: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let commonNameSk: String
    public let latinName: String
    public let edibility: Edibility
    public let lookAlikes: [String]
    public let fruitingMonths: Set<Int>
    public let idealTempMinC: Double
    public let idealTempMaxC: Double
    public let idealHumidityMinPercent: Double
    public let idealHumidityMaxPercent: Double
    public let rainfallSensitivity: RainfallSensitivity
    public let habitat: String
    public let regionalAffinity: Set<String>

    public init(
        id: String,
        commonNameSk: String,
        latinName: String,
        edibility: Edibility,
        lookAlikes: [String] = [],
        fruitingMonths: Set<Int>,
        idealTempMinC: Double,
        idealTempMaxC: Double,
        idealHumidityMinPercent: Double,
        idealHumidityMaxPercent: Double,
        rainfallSensitivity: RainfallSensitivity,
        habitat: String,
        regionalAffinity: Set<String>
    ) {
        self.id = id
        self.commonNameSk = commonNameSk
        self.latinName = latinName
        self.edibility = edibility
        self.lookAlikes = lookAlikes
        self.fruitingMonths = fruitingMonths
        self.idealTempMinC = idealTempMinC
        self.idealTempMaxC = idealTempMaxC
        self.idealHumidityMinPercent = idealHumidityMinPercent
        self.idealHumidityMaxPercent = idealHumidityMaxPercent
        self.rainfallSensitivity = rainfallSensitivity
        self.habitat = habitat
        self.regionalAffinity = regionalAffinity
    }
}
```

- [ ] **Step 2: Bulk-add the placeholder humidity fields to `species.json`**

Run this from the repo root — it inserts the two new keys into every entry, immediately after `idealTempMaxC`, preserving key order and all existing data:

```bash
python3 -c "
import json
path = 'MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json'
with open(path) as f:
    species = json.load(f)
for s in species:
    new_entry = {}
    for k, v in s.items():
        new_entry[k] = v
        if k == 'idealTempMaxC':
            new_entry['idealHumidityMinPercent'] = 60
            new_entry['idealHumidityMaxPercent'] = 90
    s.clear()
    s.update(new_entry)
with open(path, 'w') as f:
    json.dump(species, f, indent=2, ensure_ascii=False)
    f.write('\n')
"
```

- [ ] **Step 3: Verify the JSON is well-formed and has the right shape**

Run: `python3 -c "import json; d=json.load(open('MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json')); print(len(d)); print(all('idealHumidityMinPercent' in s and 'idealHumidityMaxPercent' in s for s in d))"`
Expected: `27` then `True`.

- [ ] **Step 4: Update direct `Species(...)` construction call sites**

`MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift:8-10` — the `species(id:name:edibility:minC:maxC:months:)` helper. Replace it:

```swift
    private func species(id: String, name: String, edibility: Edibility, minC: Double, maxC: Double, months: Set<Int> = [6, 7, 8, 9]) -> Species {
        Species(id: id, commonNameSk: name, latinName: id, edibility: edibility, fruitingMonths: months, idealTempMinC: minC, idealTempMaxC: maxC, idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90, rainfallSensitivity: .low, habitat: "test", regionalAffinity: [])
    }
```

`MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift:8-10` — the `species(id:name:edibility:affinity:months:)` helper. Replace it:

```swift
    private func species(id: String, name: String, edibility: Edibility = .edible, affinity: Set<String> = ["trenciansky"], months: Set<Int> = [6, 7, 8, 9]) -> Species {
        Species(id: id, commonNameSk: name, latinName: id, edibility: edibility, fruitingMonths: months, idealTempMinC: 10, idealTempMaxC: 20, idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90, rainfallSensitivity: .low, habitat: "test", regionalAffinity: affinity)
    }
```

`MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift` — find the `makeSpecies(id:name:edibility:)` helper and add the two new fields with the same `60`/`90` placeholder values, in the same position (after `idealTempMaxC`). Read the file first to get its exact current field values for `idealTempMinC`/`idealTempMaxC`/`rainfallSensitivity`/etc. before editing, so nothing else changes.

`MushroomSignalWidget/ShortlistWidgetView.swift` — the `previewSignal` helper's `Species(...)` construction (around line 163). Add `idealHumidityMinPercent: 60,` and `idealHumidityMaxPercent: 90,` right after the existing `idealTempMaxC: 18,` line.

- [ ] **Step 5: Write the new schema-validation test**

Add to `MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesDataTests.swift`:

```swift
    func testHumidityRangeIsValidForAllSpecies() throws {
        let species = try SpeciesDatabase.loadAll()
        for s in species {
            XCTAssertLessThanOrEqual(s.idealHumidityMinPercent, s.idealHumidityMaxPercent, "\(s.id) has an inverted humidity range")
            XCTAssertTrue((0...100).contains(s.idealHumidityMinPercent), "\(s.id) has an out-of-range humidity minimum")
            XCTAssertTrue((0...100).contains(s.idealHumidityMaxPercent), "\(s.id) has an out-of-range humidity maximum")
        }
    }
```

- [ ] **Step 6: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS — everything, including the new humidity-range test.

- [ ] **Step 7: Build the full Xcode project to confirm the widget preview code compiles**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Models/Species.swift MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesDataTests.swift MushroomSignalWidget/ShortlistWidgetView.swift
git commit -m "feat: add humidity range fields to Species (placeholder data, Task 11 fills in real values)"
```

---

## Task 5: Redesign `SignalAlgorithm.computeSignal`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift`
- Replace entirely: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift`

**Interfaces:**
- Consumes: `Species.idealHumidityMinPercent/MaxPercent` (Task 4), `WeatherSnapshot.averageHumidityLast10DaysPercent` (Task 1).
- Produces: `SignalAlgorithm.computeSignal(species:weather:month:flushTriggered:) -> SpeciesSignal` — **signature change**, adds a required `flushTriggered: Bool` parameter. `SpeciesSignal.score` range changes from `0...3` to `0...4`. Task 6's `SignalPipeline` consumes this new signature directly.

- [ ] **Step 1: Replace `SignalAlgorithmTests.swift` entirely**

```swift
import XCTest
@testable import MushroomSignalCore

final class SignalAlgorithmTests: XCTestCase {
    private let sampleSpecies = Species(
        id: "boletus-edulis",
        commonNameSk: "Hríb smrekový",
        latinName: "Boletus edulis",
        edibility: .edible,
        lookAlikes: [],
        fruitingMonths: [6, 7, 8, 9, 10],
        idealTempMinC: 12,
        idealTempMaxC: 22,
        idealHumidityMinPercent: 60,
        idealHumidityMaxPercent: 90,
        rainfallSensitivity: .high,
        habitat: "smrekové lesy",
        regionalAffinity: ["zilinsky"]
    )

    func testPeakSeasonWithGoodTempHumidityAndRainScoresFour() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)

        XCTAssertEqual(signal.score, 4)
        XCTAssertNil(signal.reason)
    }

    func testOffSeasonScoresZeroRegardlessOfWeather() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        // January: not in fruitingMonths, not adjacent to them either.
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 1, flushTriggered: false)

        XCTAssertEqual(signal.score, 0)
        XCTAssertEqual(signal.reason, "mimo hlavnej sezóny")
    }

    func testOffSeasonScoresZeroEvenWithFlushTriggered() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 1, flushTriggered: true)

        XCTAssertEqual(signal.score, 0, "the out-of-season hard gate must override the flush trigger too — see spec §1's one exception to equal weighting")
    }

    func testDrySpellPenalizesHighRainfallSensitivitySpecies() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 1, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)

        XCTAssertEqual(signal.score, 3)
        XCTAssertEqual(signal.reason, "málo zrážok v poslednej dobe")
    }

    func testShoulderMonthContributesPartialCalendarScoreUnderEqualWeighting() {
        // 24°C is 2°C above idealTempMaxC (22) — within the 3°C tolerance band, so partial temp credit.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 24, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        // Month 11 is adjacent to fruitingMonths' last month (10) but not itself in season.
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 11, flushTriggered: false)

        // calendar 0.5 + temp 0.5 + humidity 1.0 + rain 1.0 = 3.0
        XCTAssertEqual(signal.score, 3)
        XCTAssertEqual(signal.reason, "teplota mimo ideálneho rozsahu")
    }

    func testHumidityOutOfRangeReducesScoreAndSetsReason() {
        // 30% humidity is far below idealHumidityMinPercent (60) — outside the 10-point tolerance.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 30, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)

        // calendar 1.0 + temp 1.0 + humidity 0.0 + rain 1.0 = 3.0
        XCTAssertEqual(signal.score, 3)
        XCTAssertEqual(signal.reason, "vlhkosť mimo ideálneho rozsahu")
    }

    func testHumidityWithinToleranceBandGetsPartialCredit() {
        // 95% humidity is 5 points above idealHumidityMaxPercent (90) — within the 10-point tolerance.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 95, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)

        // calendar 1.0 + temp 1.0 + humidity 0.5 + rain 1.0 = 3.5, rounds to 4
        XCTAssertEqual(signal.score, 4)
    }

    func testFlushTriggerBumpsRainfallScoreForHighSensitivitySpecies() {
        // temp 25 is 3°C above idealTempMaxC (22) — exactly at the tolerance boundary, partial credit.
        // precipitation 10mm with .high sensitivity is >=8 but <20 — partial baseline rain credit (0.5).
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 25, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 10, fetchedAt: Date())

        let withoutTrigger = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: false)
        let withTrigger = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: true)

        // withoutTrigger: calendar 1.0 + temp 0.5 + humidity 1.0 + rain 0.5 = 3.0
        XCTAssertEqual(withoutTrigger.score, 3)
        XCTAssertEqual(withoutTrigger.reason, "málo zrážok v poslednej dobe")

        // withTrigger: rain bumped by 1.0 (high sensitivity), capped at 1.0 -> calendar 1.0 + temp 0.5 + humidity 1.0 + rain 1.0 = 3.5, rounds to 4
        XCTAssertEqual(withTrigger.score, 4)
        XCTAssertEqual(withTrigger.reason, "nedávno teplo a dážď — čoskoro môže prísť nová vlna")
    }

    func testFlushTriggerDoesNotAffectLowSensitivitySpecies() {
        let lowSensitivitySpecies = Species(
            id: "pleurotus-ostreatus",
            commonNameSk: "Hliva ustricovitá",
            latinName: "Pleurotus ostreatus",
            edibility: .edible,
            lookAlikes: [],
            fruitingMonths: [9, 10, 11],
            idealTempMinC: 2,
            idealTempMaxC: 15,
            idealHumidityMinPercent: 70,
            idealHumidityMaxPercent: 95,
            rainfallSensitivity: .low,
            habitat: "odumreté stromy",
            regionalAffinity: ["zilinsky"]
        )
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 10, averageHumidityLast10DaysPercent: 80, totalPrecipitationLast10DaysMm: 0, fetchedAt: Date())

        let withoutTrigger = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: weather, month: 10, flushTriggered: false)
        let withTrigger = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: weather, month: 10, flushTriggered: true)

        XCTAssertEqual(withoutTrigger.score, 4)
        XCTAssertEqual(withTrigger.score, 4)
        XCTAssertEqual(withoutTrigger.score, withTrigger.score, "low rainfall sensitivity gets no trigger bonus, since it never needed rain to score well")
    }

    func testLowRainfallSensitivitySpeciesScoreIsInvariantToRainfallWithPartialTempMatch() {
        let lowSensitivitySpecies = Species(
            id: "pleurotus-ostreatus",
            commonNameSk: "Hliva ustricovitá",
            latinName: "Pleurotus ostreatus",
            edibility: .edible,
            lookAlikes: [],
            fruitingMonths: [9, 10, 11],
            idealTempMinC: 2,
            idealTempMaxC: 15,
            idealHumidityMinPercent: 70,
            idealHumidityMaxPercent: 95,
            rainfallSensitivity: .low,
            habitat: "odumreté stromy",
            regionalAffinity: ["zilinsky"]
        )
        // 17°C is 2°C above idealTempMaxC (15) — within the 3°C tolerance band, so partial temp credit.
        let dryWeather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 80, totalPrecipitationLast10DaysMm: 0, fetchedAt: Date())
        let wetWeather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 80, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let drySignal = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: dryWeather, month: 10, flushTriggered: false)
        let wetSignal = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: wetWeather, month: 10, flushTriggered: false)

        XCTAssertEqual(drySignal.score, wetSignal.score, "low-sensitivity species score must not depend on rainfall")
        XCTAssertEqual(drySignal.score, 4)
        XCTAssertEqual(wetSignal.score, 4)
        XCTAssertEqual(drySignal.reason, "teplota mimo ideálneho rozsahu")
        XCTAssertEqual(wetSignal.reason, "teplota mimo ideálneho rozsahu")
    }

    func testScoreNeverExceedsFour() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8, flushTriggered: true)
        XCTAssertLessThanOrEqual(signal.score, 4)
    }
}
```

- [ ] **Step 2: Run to verify the tests fail**

Run: `swift test --package-path MushroomSignalCore --filter SignalAlgorithmTests`
Expected: FAIL — `computeSignal` doesn't accept `flushTriggered:` yet, and the old 3-factor formula produces different scores than these tests expect.

- [ ] **Step 3: Implement the redesigned `SignalAlgorithm`**

Replace the full contents of `SignalAlgorithm.swift`:

```swift
import Foundation

public enum SignalAlgorithm {
    public static func computeSignal(species: Species, weather: WeatherSnapshot, month: Int, flushTriggered: Bool) -> SpeciesSignal {
        let calendarScore = calendarFit(species: species, month: month)

        guard calendarScore > 0 else {
            return SpeciesSignal(species: species, score: 0, reason: "mimo hlavnej sezóny")
        }

        let tempScore = temperatureFit(species: species, weather: weather)
        let humidityScore = humidityFit(species: species, weather: weather)
        let rainScore = rainfallFit(species: species, weather: weather, flushTriggered: flushTriggered)

        let total = calendarScore + tempScore + humidityScore + rainScore
        let score = Int(total.rounded())

        let reason = reasonText(species: species, tempScore: tempScore, humidityScore: humidityScore, rainScore: rainScore, flushTriggered: flushTriggered)

        return SpeciesSignal(species: species, score: min(4, max(0, score)), reason: reason)
    }

    static func calendarFit(species: Species, month: Int) -> Double {
        if species.fruitingMonths.contains(month) { return 1.0 }
        let previousMonth = month == 1 ? 12 : month - 1
        let nextMonth = month == 12 ? 1 : month + 1
        if species.fruitingMonths.contains(previousMonth) || species.fruitingMonths.contains(nextMonth) {
            return 0.5
        }
        return 0.0
    }

    static func temperatureFit(species: Species, weather: WeatherSnapshot) -> Double {
        let temp = weather.averageTempLast10DaysC
        if temp >= species.idealTempMinC && temp <= species.idealTempMaxC {
            return 1.0
        }
        let distance = temp < species.idealTempMinC ? species.idealTempMinC - temp : temp - species.idealTempMaxC
        return distance <= 3.0 ? 0.5 : 0.0
    }

    static func humidityFit(species: Species, weather: WeatherSnapshot) -> Double {
        let humidity = weather.averageHumidityLast10DaysPercent
        if humidity >= species.idealHumidityMinPercent && humidity <= species.idealHumidityMaxPercent {
            return 1.0
        }
        let distance = humidity < species.idealHumidityMinPercent ? species.idealHumidityMinPercent - humidity : humidity - species.idealHumidityMaxPercent
        return distance <= 10.0 ? 0.5 : 0.0
    }

    static func rainfallFit(species: Species, weather: WeatherSnapshot, flushTriggered: Bool) -> Double {
        let precipitation = weather.totalPrecipitationLast10DaysMm
        let baseScore: Double
        switch species.rainfallSensitivity {
        case .high:
            if precipitation >= 20 { baseScore = 1.0 }
            else if precipitation >= 8 { baseScore = 0.5 }
            else { baseScore = 0.0 }
        case .medium:
            if precipitation >= 10 { baseScore = 1.0 }
            else if precipitation >= 3 { baseScore = 0.5 }
            else { baseScore = 0.0 }
        case .low:
            baseScore = 1.0
        }

        guard flushTriggered else { return baseScore }

        let bonus: Double
        switch species.rainfallSensitivity {
        case .high: bonus = 1.0
        case .medium: bonus = 0.5
        case .low: bonus = 0.0
        }
        return min(1.0, baseScore + bonus)
    }

    static func reasonText(species: Species, tempScore: Double, humidityScore: Double, rainScore: Double, flushTriggered: Bool) -> String? {
        if flushTriggered && species.rainfallSensitivity != .low {
            return "nedávno teplo a dážď — čoskoro môže prísť nová vlna"
        }
        if rainScore < 1.0 && species.rainfallSensitivity != .low {
            return "málo zrážok v poslednej dobe"
        }
        if tempScore < 1.0 {
            return "teplota mimo ideálneho rozsahu"
        }
        if humidityScore < 1.0 {
            return "vlhkosť mimo ideálneho rozsahu"
        }
        return nil
    }
}
```

- [ ] **Step 4: Run to verify all tests pass**

Run: `swift test --package-path MushroomSignalCore --filter SignalAlgorithmTests`
Expected: PASS — all 11 tests.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift
git commit -m "feat: redesign computeSignal as 4 equal-weight dimensions with flush-trigger rainfall bonus"
```

---

## Task 6: Thread `flushTriggered` Through `SignalPipeline`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalPipeline.swift`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift`

**Interfaces:**
- Consumes: `SignalAlgorithm.computeSignal(species:weather:month:flushTriggered:)` (Task 5).
- Produces: `SignalPipeline.rankedSignals(candidates:weather:month:flushTriggered:limit:)` and `SignalPipeline.rankedSignals(species:region:weather:month:flushTriggered:limit:)` — both gain a required `flushTriggered: Bool` parameter. Tasks 7-9 consume these.

- [ ] **Step 1: Write the failing test**

Add to `SignalPipelineTests.swift`:

```swift
    func testFlushTriggeredIsPassedThroughToComputeSignal() {
        // high-sensitivity species, low rain (baseline 0.0), so the trigger bump is visible in the ranked order.
        let lowRainCandidate = species(id: "a", name: "Alpha", edibility: .edible)
        let weather = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 16, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 1, fetchedAt: .now)

        let withoutTrigger = SignalPipeline.rankedSignals(candidates: [lowRainCandidate], weather: weather, month: 7, flushTriggered: false)
        let withTrigger = SignalPipeline.rankedSignals(candidates: [lowRainCandidate], weather: weather, month: 7, flushTriggered: true)

        XCTAssertLessThan(withoutTrigger[0].score, withTrigger[0].score, "flushTriggered must actually reach computeSignal, not be silently dropped")
    }
```

Update the existing `testRegionOverloadFiltersByRegionalAffinity`, `testRegionOverloadRespectsLimit`, `testRegionOverloadDefaultsToAllMatchingCandidatesWhenLimitOmitted`, and `testCandidatesOverloadDoesNotFilterByRegion` tests: add `flushTriggered: false` to every `SignalPipeline.rankedSignals(...)` call in the file.

- [ ] **Step 2: Run to verify the new test fails**

Run: `swift test --package-path MushroomSignalCore --filter SignalPipelineTests`
Expected: FAIL — `rankedSignals` doesn't accept `flushTriggered:` yet (compile error).

- [ ] **Step 3: Update `SignalPipeline`**

Replace the full contents of `SignalPipeline.swift`:

```swift
import Foundation

/// The one shared score→rank path for turning candidate species into a ranked shortlist.
/// Used by the app's `AppState.refresh()`, the widget's `ShortlistProvider`, and (via
/// `DominantSpeciesResolver`) the map's per-point dominant-species resolution — previously
/// each reimplemented filter→score→rank independently (see KNOWN_ISSUES.md).
public enum SignalPipeline {
    /// Scores the given candidates against weather/month and returns them ranked
    /// (best score first, then edibility, then name — see `ShortlistRanker`).
    public static func rankedSignals(
        candidates: [Species],
        weather: WeatherSnapshot,
        month: Int,
        flushTriggered: Bool,
        limit: Int? = nil
    ) -> [SpeciesSignal] {
        let signals = candidates.map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month, flushTriggered: flushTriggered) }
        return ShortlistRanker.topSpecies(from: signals, limit: limit ?? signals.count)
    }

    /// Convenience for the common case: candidates are every species with affinity for
    /// `region`, scored and ranked. Used by the app's shortlist and the widget's timeline.
    public static func rankedSignals(
        species: [Species],
        region: Region,
        weather: WeatherSnapshot,
        month: Int,
        flushTriggered: Bool,
        limit: Int? = nil
    ) -> [SpeciesSignal] {
        rankedSignals(
            candidates: species.filter { $0.regionalAffinity.contains(region.id) },
            weather: weather,
            month: month,
            flushTriggered: flushTriggered,
            limit: limit
        )
    }
}
```

- [ ] **Step 4: Run to verify all tests pass**

Run: `swift test --package-path MushroomSignalCore --filter SignalPipelineTests`
Expected: PASS.

- [ ] **Step 5: Run the full core package suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: FAIL — `DominantSpeciesResolver.swift`, `AppState.swift`, and `MushroomSignalWidget.swift` call `SignalPipeline.rankedSignals` without `flushTriggered:` and no longer compile. This is expected; Tasks 7-9 fix each caller. Confirm the failures are exactly these three compile errors and nothing else, then proceed.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalPipeline.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalPipelineTests.swift
git commit -m "feat: thread flushTriggered through SignalPipeline"
```

---

## Task 7: Wire `DominantSpeciesResolver` (Map — Trigger Intentionally Off)

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/DominantSpeciesResolver.swift`

**Interfaces:**
- Consumes: `SignalPipeline.rankedSignals(candidates:weather:month:flushTriggered:limit:)` (Task 6).
- Produces: `DominantSpeciesResolver.resolve(activeSpecies:weather:month:)` — signature unchanged, internal call updated.

- [ ] **Step 1: Update the internal call and its doc comment**

Replace the full contents of `DominantSpeciesResolver.swift`:

```swift
import Foundation

/// Picks which active species "wins" the color at a single map grid point. Reuses the exact same
/// scoring (`SignalAlgorithm`) and tie-break (`ShortlistRanker`) as the shortlist, via the shared
/// `SignalPipeline` — no new algorithm (v2 spec §2).
///
/// Always passes `flushTriggered: false` — the map's per-grid-point coloring intentionally does not
/// evaluate the warm-day+rain flush trigger. Doing so would need a batched per-point daily-breakdown
/// fetch, which is out of scope; see the 2026-08-07 roadmap spec §1, which also directs that the map
/// itself stay untouched in this phase.
public enum DominantSpeciesResolver {
    public static func resolve(activeSpecies: [Species], weather: WeatherSnapshot, month: Int) -> Species? {
        guard !activeSpecies.isEmpty else { return nil }
        guard let top = SignalPipeline.rankedSignals(candidates: activeSpecies, weather: weather, month: month, flushTriggered: false, limit: 1).first,
              top.score > 0 else {
            return nil
        }
        return top.species
    }
}
```

- [ ] **Step 2: Run `DominantSpeciesResolverTests` to confirm no regressions**

Run: `swift test --package-path MushroomSignalCore --filter DominantSpeciesResolverTests`
Expected: PASS — all 5 existing tests, unchanged behavior (they only assert *which* species wins, not exact scores).

- [ ] **Step 3: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/DominantSpeciesResolver.swift
git commit -m "fix: wire DominantSpeciesResolver to the new SignalPipeline signature (trigger off for the map)"
```

---

## Task 8: Wire the Flush Trigger into `AppState.refresh()`

**Files:**
- Modify: `MushroomSignal/AppState.swift`
- Modify: `MushroomSignalTests/AppStateTests.swift`

**Interfaces:**
- Consumes: `WeatherClient.fetchDailyBreakdown(for:pastDays:)` (Task 2), `FlushTriggerDetector.triggered(in:asOf:)` (Task 3), `SignalPipeline.rankedSignals(species:region:weather:month:flushTriggered:limit:)` (Task 6).
- Produces: no new public interface — `AppState.refresh()`'s internal behavior changes only.

- [ ] **Step 1: Update `AppState.refresh()`**

In `MushroomSignal/AppState.swift`, replace the `refresh()` method body:

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
            let weather = try await weatherClient.fetchSnapshot(for: region)
            weatherCache?.store(weather)
            let dailyWeather = (try? await weatherClient.fetchDailyBreakdown(for: region, pastDays: 10)) ?? []
            let flushTriggered = FlushTriggerDetector.triggered(in: dailyWeather, asOf: Date())
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let ranked = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: weather, month: month, flushTriggered: flushTriggered)
            guard currentRefreshID == refreshID else { return }
            signals = ranked
            isShowingStaleData = false
        } catch {
            guard currentRefreshID == refreshID else { return }
            if let cached = weatherCache?.snapshot(for: region.id), let allSpecies = try? SpeciesDatabase.loadAll() {
                let month = Calendar.current.component(.month, from: Date())
                signals = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: cached, month: month, flushTriggered: false)
                isShowingStaleData = true
                errorMessage = "Zobrazujú sa staršie údaje z \(Self.staleTimeFormatter.string(from: cached.fetchedAt))."
            } else {
                signals = []
                isShowingStaleData = false
                errorMessage = "Nepodarilo sa načítať údaje o počasí. Skúste to znova."
            }
            logger.error("Refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
```

Two deliberate design choices worth being explicit about:
- The daily-breakdown fetch failing (`try?`, falling back to `[]`) does not fail the whole refresh — `FlushTriggerDetector.triggered(in: [], ...)` returns `false`, so a broken/unavailable daily-breakdown endpoint just means no trigger bonus this refresh, not a lost shortlist. The primary `fetchSnapshot` call is unaffected and still uses its own real `try`.
- The stale-data fallback path (`catch` block) always passes `flushTriggered: false` — it has no fresh daily breakdown to evaluate (the cached path only has a cached `WeatherSnapshot`, not cached `DailyWeather`), and re-showing a trigger bonus from a previous, possibly-stale refresh would misrepresent how current that signal is.

- [ ] **Step 2: Update `AppStateTests.swift`**

The `StubWeatherClient` and `DelayedWeatherClient` used by these tests already implement `fetchDailyBreakdown` returning `[]` (Task 2), so `FlushTriggerDetector.triggered` will always evaluate to `false` in these tests — no test assertions need to change. Just confirm the file still compiles and passes as-is:

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/AppStateTests`
Expected: PASS — all 4 existing tests, unchanged.

- [ ] **Step 3: Add a test proving the trigger actually reaches `AppState`**

Add to `AppStateTests.swift`. This needs a small test-only `WeatherClient` that returns real daily-breakdown data — add it directly in this test file since it's used only here:

```swift
    func testRefreshAppliesFlushTriggerFromDailyBreakdown() async {
        struct TriggeringWeatherClient: WeatherClient {
            func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
                WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 16, averageHumidityLast10DaysPercent: 75, totalPrecipitationLast10DaysMm: 1, fetchedAt: .now)
            }
            func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] { [:] }
            func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
                [DailyWeather(date: Date().addingTimeInterval(-3 * 86400), meanTempC: 22, maxTempC: 27, precipitationMm: 5)]
            }
        }

        let appState = AppState(store: nil, weatherCache: nil, weatherClient: TriggeringWeatherClient())
        await appState.refresh()

        XCTAssertFalse(appState.signals.isEmpty, "precondition: some species should be in season and scoring")
        XCTAssertTrue(appState.signals.contains { $0.reason == "nedávno teplo a dážď — čoskoro môže prísť nová vlna" }, "a high/medium rainfall-sensitivity species in low-rain conditions should show the trigger reason once a qualifying day is in the daily breakdown")
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:MushroomSignalTests/AppStateTests`
Expected: PASS — all 5 tests. (If it fails because no real species happens to have `.high`/`.medium` sensitivity and be in the current real month's season, adjust the test's `averageTempLast10DaysC`/month expectations after checking `species.json` — but do not weaken the assertion to something that doesn't prove the trigger reached `AppState`.)

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/AppState.swift MushroomSignalTests/AppStateTests.swift
git commit -m "feat: wire the flush trigger into AppState.refresh()"
```

---

## Task 9: Wire the Flush Trigger into the Widget's `ShortlistProvider`

**Files:**
- Modify: `MushroomSignalWidget/MushroomSignalWidget.swift`

**Interfaces:**
- Consumes: same as Task 8.
- Produces: no new public interface.

- [ ] **Step 1: Update `fetchEntry`**

Replace the full contents of `MushroomSignalWidget.swift`'s `fetchEntry` method:

```swift
    private func fetchEntry(region: Region, limit: Int) async -> ShortlistEntry {
        do {
            let client = OpenMeteoClient()
            let weather = try await client.fetchSnapshot(for: region)
            WeatherSnapshotCache()?.store(weather)
            let dailyWeather = (try? await client.fetchDailyBreakdown(for: region, pastDays: 10)) ?? []
            let flushTriggered = FlushTriggerDetector.triggered(in: dailyWeather, asOf: Date())
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let shortlist = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: weather, month: month, flushTriggered: flushTriggered, limit: limit)
            return ShortlistEntry(date: Date(), region: region, signals: shortlist)
        } catch {
            widgetLogger.error("Timeline refresh failed for region \(region.id, privacy: .public): \(String(describing: error), privacy: .public)")
            if let cached = WeatherSnapshotCache()?.snapshot(for: region.id), let allSpecies = try? SpeciesDatabase.loadAll() {
                let month = Calendar.current.component(.month, from: Date())
                let shortlist = SignalPipeline.rankedSignals(species: allSpecies, region: region, weather: cached, month: month, flushTriggered: false, limit: limit)
                return ShortlistEntry(date: cached.fetchedAt, region: region, signals: shortlist)
            }
            return ShortlistEntry(date: Date(), region: region, signals: [])
        }
    }
```

(Note the switch from `OpenMeteoClient().fetchSnapshot(...)` to a shared `client` local — needed since `fetchDailyBreakdown` is now also called on it; avoids constructing two separate client instances for one entry.)

- [ ] **Step 2: Build the whole project**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **` — this is the first point since Task 6 Step 5 where the whole project builds again (Tasks 7-9 each fixed one of the three broken call sites).

- [ ] **Step 3: Run the full Xcode test suite**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **` — every test in `MushroomSignalTests`.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignalWidget/MushroomSignalWidget.swift
git commit -m "feat: wire the flush trigger into the widget's ShortlistProvider"
```

---

## Task 10: Widen the Displayed Score from 0-3 to 0-4

**Files:**
- Modify: `MushroomSignal/Views/ShortlistView.swift`
- Modify: `MushroomSignalWidget/ShortlistWidgetView.swift`

**Interfaces:**
- Consumes: `SpeciesSignal.score` now ranging `0...4` (Task 5).
- Produces: no new interface — display-only change.

- [ ] **Step 1: Update `ShortlistView.swift`**

At `MushroomSignal/Views/ShortlistView.swift:29,36`, replace:

```swift
        let clampedScore = max(0, min(3, signal.score))
```

with:

```swift
        let clampedScore = max(0, min(4, signal.score))
```

and replace:

```swift
                Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
```

with:

```swift
                Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 4 - clampedScore))
```

- [ ] **Step 2: Update `ShortlistWidgetView.swift`**

At lines `106`/`135` and `142`/`154`, apply the identical two substitutions (`min(3,` → `min(4,`, and `count: 3 - clampedScore` → `count: 4 - clampedScore`) at both occurrences — this file branches per widget family (small/medium vs. large) and has the same dot-rendering pattern duplicated in each branch.

- [ ] **Step 3: Build to confirm no other code assumes a 0-3 range**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manually verify via Xcode preview**

Open `ShortlistWidgetView.swift` in Xcode, check its preview canvas renders 4 dots (not 3) for a score-4 preview signal, across small/medium/large families. Same convention as all prior UI work in this project — no meaningful unit-test surface for pure dot-count layout.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/Views/ShortlistView.swift MushroomSignalWidget/ShortlistWidgetView.swift
git commit -m "feat: widen displayed score from 0-3 to 0-4 dots"
```

---

## Task 11: Species Data Enrichment (Replace Placeholder Humidity, Review Existing Fields)

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json`

**Interfaces:**
- Consumes: nothing new — operates on the existing `Species` schema (Task 4).
- Produces: nothing new — same schema, real values.

This task is research and data-writing, not algorithm work — the process is concrete below, but the actual per-species numbers are the deliverable of doing the research, not something to pre-write into this plan.

- [ ] **Step 1: For each of the 27 species in `species.json`, research and write real values**

List the current 27 ids first (`python3 -c "import json; print([s['id'] for s in json.load(open('MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json'))])"`) to work through systematically, one at a time. For each species:

- Replace the placeholder `idealHumidityMinPercent: 60, idealHumidityMaxPercent: 90` with a real range researched for that specific species — most fungi cluster in the 60-95% relative humidity band, but sensitivity varies (e.g., a dry-adapted species like some `Boletus` might tolerate a wider/lower band than a moisture-dependent species like most `Amanita`).
- Review `idealTempMinC`/`idealTempMaxC` against the same sources and correct if the existing v1 values look off.
- Review `fruitingMonths` the same way.
- Review `rainfallSensitivity` (`.low`/`.medium`/`.high`) the same way.

Source from multiple general mycological references per species — field guides, academic mycology resources, Wikipedia among others — cross-referenced, not copied verbatim from any one source, per this plan's Global Constraints and the roadmap spec §5. Do not fetch or scrape nahuby.sk.

- [ ] **Step 2: After every species is updated, verify the JSON is still well-formed and complete**

Run: `python3 -c "import json; d=json.load(open('MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json')); print(len(d)); print(all('idealHumidityMinPercent' in s and 'idealHumidityMaxPercent' in s for s in d))"`
Expected: `27` then `True` (same check as Task 4 Step 3 — confirms nothing was accidentally dropped while editing 27 entries by hand).

- [ ] **Step 3: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS — in particular `SpeciesDataTests.testHumidityRangeIsValidForAllSpecies` (Task 4) now validates real researched values, not placeholders, and every other existing `SpeciesDataTests` check (unique ids, valid look-alike references, valid regions, valid months, at least one poisonous entry) still passes since this task only changes field values, not structure.

- [ ] **Step 4: Full Xcode build + test**

Run: `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json
git commit -m "data: research and write real humidity ranges, review temp/season/rainfall data for all 27 species"
```

- [ ] **Step 6: Flag for Alexander's review**

This is data content, not code — per the spec, Alexander verifies it against his own 20 years of foraging experience before it's considered final. Note in the handoff/summary that this commit is pending his review, same as the original `species.json` compile and the in-progress Slovak-name review.

---

## Final Verification

- [ ] Run `swift test --package-path MushroomSignalCore` — full pass.
- [ ] Run `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData` — full pass.
- [ ] Run a full signed build (`xcodebuild -scheme MushroomSignal -configuration Release -derivedDataPath DerivedData build`) and launch the app to visually confirm the shortlist shows 4 dots and real numbers look sane for at least one region.
- [ ] Update `docs/superpowers/KNOWN_ISSUES.md` if this work surfaces anything it doesn't already close (it doesn't appear to close any existing open item — the only remaining open item, the Slovak-name review, is separate from this plan's humidity/temp/season/rainfall enrichment).
