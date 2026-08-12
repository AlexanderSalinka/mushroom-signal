# OpenMeteoClient Query-Parameter Test Coverage — Design

**Status: approved, implementation-ready.**

## Why

`KNOWN_ISSUES.md`: `MockURLProtocol` ignores the request URL entirely in most existing
tests, so a typo in a `daily=` field name (e.g. `relative_humidity_2m_mean`) would pass
every test while silently returning no data for that field in production (Open-Meteo
just omits an unrecognized field rather than erroring).

**Partially stale as written** — `OpenMeteoClientTests.swift` already has 2 tests
(`testFetchDailyBreakdownSendsForecastDaysQueryParameter`,
`testFetchDailyBreakdownTwoArgOverloadDefaultsForecastDaysToZero`) that capture
`request.url` and assert on it, using exactly the pattern this fix needs. They only
check `forecast_days=`, though — not the `daily=` field-name list, which is the specific
risk the issue named. This design extends the existing pattern, not invents a new one.

## Goals

At least one test per `WeatherClient` fetch method asserting the exact `daily=`
query-parameter value sent to Open-Meteo — the thing a field-name typo would actually
break.

## Out of Scope

- Any production code change — `OpenMeteoClient`'s query-building is already correct;
  this is pure test-coverage addition to catch a *future* regression.
- Asserting every query parameter (`latitude`/`longitude`/`timezone`) on every method —
  one additional coverage test confirms the pattern generalizes, not four redundant
  full-parameter dumps.

## Design

### Extend `OpenMeteoClientTests.swift` with `daily=` field-list assertions

Following the exact `capturedURL` pattern the two existing tests already use, one new
test per fetch method:

```swift
func testFetchSnapshotSendsExpectedDailyFieldList() async throws {
    let json = """
    { "daily": { "temperature_2m_mean": [10.0], "relative_humidity_2m_mean": [60.0], "precipitation_sum": [0.0] } }
    """.data(using: .utf8)!
    var capturedURL: URL?
    MockURLProtocol.requestHandler = { request in
        capturedURL = request.url
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
    }
    let client = OpenMeteoClient(session: makeMockedSession())
    _ = try await client.fetchSnapshot(for: region)

    let daily = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "daily" })?.value
    XCTAssertEqual(daily, "temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum", "a typo in any field name here would silently return no data for that field instead of failing loudly")
}

func testFetchSnapshotsSendsExpectedDailyFieldList() async throws {
    let json = "[]".data(using: .utf8)!
    var capturedURL: URL?
    MockURLProtocol.requestHandler = { request in
        capturedURL = request.url
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
    }
    let client = OpenMeteoClient(session: makeMockedSession())
    _ = try await client.fetchSnapshots(for: [GridPoint(id: "grid-00", latitude: 48.1, longitude: 17.1)])

    let daily = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "daily" })?.value
    XCTAssertEqual(daily, "temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum")
}

func testFetchDailyBreakdownSendsExpectedDailyFieldList() async throws {
    let json = """
    { "daily": { "time": ["2026-08-01"], "temperature_2m_max": [28.0], "temperature_2m_min": [16.0], "temperature_2m_mean": [22.0], "relative_humidity_2m_mean": [65.0], "precipitation_sum": [0.0] } }
    """.data(using: .utf8)!
    var capturedURL: URL?
    MockURLProtocol.requestHandler = { request in
        capturedURL = request.url
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
    }
    let client = OpenMeteoClient(session: makeMockedSession())
    _ = try await client.fetchDailyBreakdown(for: region, pastDays: 1, forecastDays: 0)

    let daily = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "daily" })?.value
    XCTAssertEqual(daily, "temperature_2m_max,temperature_2m_min,temperature_2m_mean,relative_humidity_2m_mean,precipitation_sum")
}

func testFetchDailyBreakdownSendsExpectedLatitudeLongitudeAndTimezoneParameters() async throws {
    let json = """
    { "daily": { "time": ["2026-08-01"], "temperature_2m_max": [28.0], "temperature_2m_min": [16.0], "temperature_2m_mean": [22.0], "relative_humidity_2m_mean": [65.0], "precipitation_sum": [0.0] } }
    """.data(using: .utf8)!
    var capturedURL: URL?
    MockURLProtocol.requestHandler = { request in
        capturedURL = request.url
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
    }
    let client = OpenMeteoClient(session: makeMockedSession())
    _ = try await client.fetchDailyBreakdown(for: region, pastDays: 1, forecastDays: 0)

    let items = URLComponents(url: capturedURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
    XCTAssertEqual(items.first(where: { $0.name == "latitude" })?.value, String(region.latitude))
    XCTAssertEqual(items.first(where: { $0.name == "longitude" })?.value, String(region.longitude))
    XCTAssertEqual(items.first(where: { $0.name == "timezone" })?.value, "auto")
}
```

If Item 3 (`WatchedAlertEvaluator` flush-trigger fix, which adds
`fetchDailyBreakdowns(for points:, pastDays:)`) has already landed by the time this is
implemented, add the same `daily=` field-list test for that method too, following the
identical pattern — it requests the same 5-field list as `fetchDailyBreakdown`.

### Testing

This entire task *is* the testing — no separate testing section needed. Run the full
Core suite afterward as a regression check; all existing tests should be unaffected
(purely additive).
