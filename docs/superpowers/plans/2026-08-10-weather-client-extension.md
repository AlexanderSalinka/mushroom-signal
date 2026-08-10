# Weather Client Extension Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `DailyWeather`/`WeatherClient`/`OpenMeteoClient` with minimum temperature, humidity, and forecast-day support — the shared foundation both the trend sparkline and the Predpoveď tab plans depend on.

**Architecture:** Add two fields to `DailyWeather` (`minTempC`, `humidityPercent`) and one parameter to `WeatherClient.fetchDailyBreakdown` (`forecastDays`), implemented in `OpenMeteoClient` by extending its existing daily-breakdown query and response parsing. A protocol extension preserves the existing 2-arg call so today's two call sites (`AppState.refresh`, `ShortlistProvider.fetchEntry`) keep compiling unchanged.

**Tech Stack:** Swift, Foundation, `URLSession`/`URLProtocol` mocking (existing `MockURLProtocol` pattern), XCTest, Swift Package Manager.

## Global Constraints

- `swift test --package-path MushroomSignalCore` must pass after every step touching `MushroomSignalCore`.
- `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData` must pass after every step touching `MushroomSignal`/`MushroomSignalTests` (no new files are added in this plan, so `xcodegen generate` is a formality, not a requirement, but cheap to run anyway).
- Never hardcode ad hoc values — none needed here, this plan is pure data-model/network-layer work.
- Do not change `AppState.refresh()` or `ShortlistProvider.fetchEntry`'s own behavior — both must keep compiling and passing unchanged, calling the same 2-arg `fetchDailyBreakdown(for:pastDays:)` they call today.

---

### Task 1: Extend `DailyWeather`, `WeatherClient`, and `OpenMeteoClient`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/DailyWeather.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift`
- Modify: `MushroomSignalCore/Tests/MushroomSignalCoreTests/FlushTriggerDetectorTests.swift`
- Modify: `MushroomSignalTests/StubWeatherClient.swift`
- Modify: `MushroomSignalTests/AppStateTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces: `DailyWeather` gains `minTempC: Double` and `humidityPercent: Double` (both required in `init`, positioned after `maxTempC` and after `precipitationMm` respectively — exact order below). `WeatherClient.fetchDailyBreakdown(for:pastDays:forecastDays:)` is the new protocol requirement; `fetchDailyBreakdown(for:pastDays:)` remains callable via a protocol-extension default. Both the trend-sparkline plan and the Predpoveď-tab plan call `fetchDailyBreakdown(for:pastDays:forecastDays:)` directly.

- [ ] **Step 1: Update `OpenMeteoClientTests.swift`'s daily-breakdown tests first (TDD red)**

Read the current three `testFetchDailyBreakdown*` tests in
`MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift` (lines 164-220).
Replace all three with versions that include `temperature_2m_min` and
`relative_humidity_2m_mean` in the mocked JSON and assert the new fields, plus a new test for
the `forecast_days` query parameter:

Replace:
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

    func testFetchDailyBreakdownHandlesMismatchedArrayLengths() async throws {
        let json = """
        { "daily": { "time": ["2026-08-01", "2026-08-02"], "temperature_2m_max": [28.0], "temperature_2m_mean": [22.0, 24.0], "precipitation_sum": [0.0, 5.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchDailyBreakdown(for: region, pastDays: 2)

        XCTAssertEqual(result.count, 1, "days with out-of-bounds indices should be skipped, not crash")
        XCTAssertEqual(result[0].maxTempC, 28.0, accuracy: 0.001)
    }
```

with:
```swift
    func testFetchDailyBreakdownParsesPerDayValues() async throws {
        let json = """
        { "daily": { "time": ["2026-08-01", "2026-08-02"], "temperature_2m_max": [28.0, 30.0], "temperature_2m_min": [16.0, 18.0], "temperature_2m_mean": [22.0, 24.0], "relative_humidity_2m_mean": [65.0, 70.0], "precipitation_sum": [0.0, 5.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchDailyBreakdown(for: region, pastDays: 2, forecastDays: 0)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].maxTempC, 28.0, accuracy: 0.001)
        XCTAssertEqual(result[0].minTempC, 16.0, accuracy: 0.001)
        XCTAssertEqual(result[0].meanTempC, 22.0, accuracy: 0.001)
        XCTAssertEqual(result[0].humidityPercent, 65.0, accuracy: 0.001)
        XCTAssertEqual(result[0].precipitationMm, 0.0, accuracy: 0.001)
        XCTAssertEqual(result[1].maxTempC, 30.0, accuracy: 0.001)
        XCTAssertEqual(result[1].minTempC, 18.0, accuracy: 0.001)
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
        { "daily": { "time": ["2026-08-01", "2026-08-02"], "temperature_2m_max": [28.0, null], "temperature_2m_min": [16.0, 17.0], "temperature_2m_mean": [22.0, 24.0], "relative_humidity_2m_mean": [65.0, 70.0], "precipitation_sum": [0.0, 5.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchDailyBreakdown(for: region, pastDays: 2, forecastDays: 0)

        XCTAssertEqual(result.count, 1, "a day with any null field should be skipped, not crash or default to 0")
    }

    func testFetchDailyBreakdownHandlesMismatchedArrayLengths() async throws {
        let json = """
        { "daily": { "time": ["2026-08-01", "2026-08-02"], "temperature_2m_max": [28.0], "temperature_2m_min": [16.0, 17.0], "temperature_2m_mean": [22.0, 24.0], "relative_humidity_2m_mean": [65.0, 70.0], "precipitation_sum": [0.0, 5.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let result = try await client.fetchDailyBreakdown(for: region, pastDays: 2, forecastDays: 0)

        XCTAssertEqual(result.count, 1, "days with out-of-bounds indices should be skipped, not crash")
        XCTAssertEqual(result[0].maxTempC, 28.0, accuracy: 0.001)
    }

    func testFetchDailyBreakdownSendsForecastDaysQueryParameter() async throws {
        let json = """
        { "daily": { "time": ["2026-08-01"], "temperature_2m_max": [28.0], "temperature_2m_min": [16.0], "temperature_2m_mean": [22.0], "relative_humidity_2m_mean": [65.0], "precipitation_sum": [0.0] } }
        """.data(using: .utf8)!

        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        _ = try await client.fetchDailyBreakdown(for: region, pastDays: 10, forecastDays: 5)

        XCTAssertEqual(capturedURL?.query?.contains("forecast_days=5"), true, "forecastDays must be forwarded to Open-Meteo's forecast_days query parameter")
    }

    func testFetchDailyBreakdownTwoArgOverloadDefaultsForecastDaysToZero() async throws {
        let json = """
        { "daily": { "time": ["2026-08-01"], "temperature_2m_max": [28.0], "temperature_2m_min": [16.0], "temperature_2m_mean": [22.0], "relative_humidity_2m_mean": [65.0], "precipitation_sum": [0.0] } }
        """.data(using: .utf8)!

        var capturedURL: URL?
        MockURLProtocol.requestHandler = { request in
            capturedURL = request.url
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client: WeatherClient = OpenMeteoClient(session: makeMockedSession())
        _ = try await client.fetchDailyBreakdown(for: region, pastDays: 10)

        XCTAssertEqual(capturedURL?.query?.contains("forecast_days=0"), true, "the existing 2-arg call site must still request 0 forecast days")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path MushroomSignalCore --filter OpenMeteoClientTests`
Expected: FAIL to compile — `DailyWeather` has no member `minTempC`/`humidityPercent`, `fetchDailyBreakdown` has no 3-arg overload. This is the correct red signal.

- [ ] **Step 3: Extend `DailyWeather`**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/Weather/DailyWeather.swift`, replace:

```swift
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

with:

```swift
public struct DailyWeather: Codable, Equatable, Sendable {
    public let date: Date
    public let meanTempC: Double
    public let maxTempC: Double
    public let minTempC: Double
    public let precipitationMm: Double
    public let humidityPercent: Double

    public init(date: Date, meanTempC: Double, maxTempC: Double, minTempC: Double, precipitationMm: Double, humidityPercent: Double) {
        self.date = date
        self.meanTempC = meanTempC
        self.maxTempC = maxTempC
        self.minTempC = minTempC
        self.precipitationMm = precipitationMm
        self.humidityPercent = humidityPercent
    }
}
```

- [ ] **Step 4: Extend `WeatherClient`**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift`, replace the
entire file contents:

```swift
import Foundation

public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]
    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather]
}

public extension WeatherClient {
    /// Preserves the pre-existing 2-arg call (`AppState.refresh`, `ShortlistProvider.fetchEntry`)
    /// unchanged — Swift doesn't allow default parameter values directly on protocol
    /// requirements, so the default lives here instead.
    func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
        try await fetchDailyBreakdown(for: region, pastDays: pastDays, forecastDays: 0)
    }
}
```

- [ ] **Step 5: Extend `OpenMeteoClient`'s daily-breakdown query and parsing**

Edit `MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift`, replace:

```swift
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
            guard index < decoded.daily.temperature2mMax.count,
                  index < decoded.daily.temperature2mMean.count,
                  index < decoded.daily.precipitationSum.count,
                  let date = dateFormatter.date(from: decoded.daily.time[index]),
                  let maxTemp = decoded.daily.temperature2mMax[index],
                  let meanTemp = decoded.daily.temperature2mMean[index],
                  let precipitation = decoded.daily.precipitationSum[index] else { continue }
            result.append(DailyWeather(date: date, meanTempC: meanTemp, maxTempC: maxTemp, precipitationMm: precipitation))
        }
        return result
    }
```

with:

```swift
    public func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(region.latitude)),
            URLQueryItem(name: "longitude", value: String(region.longitude)),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum"),
            URLQueryItem(name: "past_days", value: String(pastDays)),
            URLQueryItem(name: "forecast_days", value: String(forecastDays)),
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
            guard index < decoded.daily.temperature2mMax.count,
                  index < decoded.daily.temperature2mMin.count,
                  index < decoded.daily.temperature2mMean.count,
                  index < decoded.daily.relativeHumidity2mMean.count,
                  index < decoded.daily.precipitationSum.count,
                  let date = dateFormatter.date(from: decoded.daily.time[index]),
                  let maxTemp = decoded.daily.temperature2mMax[index],
                  let minTemp = decoded.daily.temperature2mMin[index],
                  let meanTemp = decoded.daily.temperature2mMean[index],
                  let humidity = decoded.daily.relativeHumidity2mMean[index],
                  let precipitation = decoded.daily.precipitationSum[index] else { continue }
            result.append(DailyWeather(date: date, meanTempC: meanTemp, maxTempC: maxTemp, minTempC: minTemp, precipitationMm: precipitation, humidityPercent: humidity))
        }
        return result
    }
```

Then replace the `OpenMeteoDailyResponse` struct at the bottom of the same file:

```swift
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

with:

```swift
struct OpenMeteoDailyResponse: Codable {
    struct Daily: Codable {
        let time: [String]
        let temperature2mMax: [Double?]
        let temperature2mMin: [Double?]
        let temperature2mMean: [Double?]
        let relativeHumidity2mMean: [Double?]
        let precipitationSum: [Double?]

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2mMax = "temperature_2m_max"
            case temperature2mMin = "temperature_2m_min"
            case temperature2mMean = "temperature_2m_mean"
            case relativeHumidity2mMean = "relative_humidity_2m_mean"
            case precipitationSum = "precipitation_sum"
        }
    }
    let daily: Daily
}
```

- [ ] **Step 6: Run the `OpenMeteoClientTests` to verify they pass**

Run: `swift test --package-path MushroomSignalCore --filter OpenMeteoClientTests`
Expected: PASS, all tests including the two new ones.

- [ ] **Step 7: Fix `FlushTriggerDetectorTests.swift`'s `DailyWeather` construction helper**

Edit `MushroomSignalCore/Tests/MushroomSignalCoreTests/FlushTriggerDetectorTests.swift`, replace:

```swift
    private func daysAgo(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(-Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, precipitationMm: precipitationMm)
    }
```

with:

```swift
    private func daysAgo(_ n: Int, maxTempC: Double, precipitationMm: Double) -> DailyWeather {
        DailyWeather(date: today.addingTimeInterval(-Double(n) * 86400), meanTempC: maxTempC - 5, maxTempC: maxTempC, minTempC: maxTempC - 10, precipitationMm: precipitationMm, humidityPercent: 70)
    }
```

- [ ] **Step 8: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS, no missing-symbol errors, no leftover 4-arg `DailyWeather(...)` call sites in `MushroomSignalCore`.

- [ ] **Step 9: Fix `MushroomSignalTests/StubWeatherClient.swift`'s two conformances**

Read the current file. Replace:

```swift
    func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
        []
    }
```

(this exact 3-line body appears twice — once in `StubWeatherClient`, once in `DelayedWeatherClient`) with, in **both** places:

```swift
    func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
        []
    }
```

- [ ] **Step 10: Fix `MushroomSignalTests/AppStateTests.swift`'s ad-hoc `TriggeringWeatherClient` conformance**

Edit `MushroomSignalTests/AppStateTests.swift`, replace:

```swift
            func fetchDailyBreakdown(for region: Region, pastDays: Int) async throws -> [DailyWeather] {
                // 3 days before the injected "now" so it always lands inside the detector's
                // 2-7 day lag window, regardless of when the test actually runs.
                [DailyWeather(date: referenceDate.addingTimeInterval(-3 * 86400), meanTempC: 22, maxTempC: 27, precipitationMm: 5)]
            }
```

with:

```swift
            func fetchDailyBreakdown(for region: Region, pastDays: Int, forecastDays: Int) async throws -> [DailyWeather] {
                // 3 days before the injected "now" so it always lands inside the detector's
                // 2-7 day lag window, regardless of when the test actually runs.
                [DailyWeather(date: referenceDate.addingTimeInterval(-3 * 86400), meanTempC: 22, maxTempC: 27, minTempC: 17, precipitationMm: 5, humidityPercent: 70)]
            }
```

This is the one call site not caught by a simple grep for the struct name alone — `TriggeringWeatherClient` is an ad-hoc `WeatherClient` conformance local to a test function, not a named stub class. Confirmed via `grep -rn ": WeatherClient"` across the whole repo that exactly four types conform: `OpenMeteoClient`, `StubWeatherClient`, `DelayedWeatherClient`, and this one — all four are covered by Steps 5, 9, and 10.

- [ ] **Step 11: Run the full app test suite**

Run: `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **` — this exercises `AppState.refresh()` (via `AppStateTests`) and confirms the 2-arg convenience overload still works end-to-end through real app code, not just in isolation.

- [ ] **Step 12: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Weather/DailyWeather.swift MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/FlushTriggerDetectorTests.swift MushroomSignalTests/StubWeatherClient.swift MushroomSignalTests/AppStateTests.swift
git commit -m "feat: extend DailyWeather/WeatherClient with min temp, humidity, forecast days"
```

---

## Final Verification

- [ ] Run `swift test --package-path MushroomSignalCore` — full pass.
- [ ] Run `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData` — full pass.
- [ ] `grep -rn "DailyWeather(" --include="*.swift" .` (excluding `.build`/`DerivedData`) — confirm every construction call site now passes all 6 arguments (`date`, `meanTempC`, `maxTempC`, `minTempC`, `precipitationMm`, `humidityPercent`).
- [ ] `grep -rn "fetchDailyBreakdown(for:" --include="*.swift" .` — confirm every conformance implements the 3-arg requirement, and every call site either passes `forecastDays:` explicitly or relies on the 2-arg protocol-extension default intentionally (the two existing production call sites in `AppState.swift`/`MushroomSignalWidget.swift` should still read `fetchDailyBreakdown(for: region, pastDays: 10)`, unchanged).
