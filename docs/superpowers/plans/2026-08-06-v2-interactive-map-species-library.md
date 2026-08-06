# Mushroom Signal v2 — Interactive Map & Species Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the schematic 8-kraj grid in the companion app with a real, pannable MapKit map showing a dominant-species heat mosaic over ~30-50 weather sample points, combined with a browsable species library (27 species, toggleable on/off the map, best-effort photos).

**Architecture:** New pure-logic pieces (grid generation, batched weather fetch, dominant-species resolution, color assignment) live in `MushroomSignalCore` and are unit-tested. A new `MapScreenState` observable object (mirroring the existing `AppState` pattern) owns grid/species/photo data and drives three new SwiftUI views in the app target, which replace `RegionMapView` in `ContentView`'s "Mapa" tab. No changes to the shortlist tab, region picker, signal-scoring algorithm, `species.json` schema, or the widget target — this plan touches none of the code involved in this week's signing/trust investigation.

**Scope vs. the v2 spec:** the full spec has 6 sections. §5 (widget family expansion) and §6 (widget region-sync fix) already shipped today (`4b4fcc6`, `9e47664`) — pulled forward ahead of the map work. §4's typography tokens (`captionSize`/`bodySize`/`titleSize`/`heroSize`) also already shipped as part of that same work; only §4's species color palette is still outstanding. This plan covers the remainder: §1 (weather grid), §2 (heat rendering), §3 (species library), and the outstanding half of §4 (color palette).

**Tech Stack:** Swift 5.10, SwiftUI, MapKit (`Map`/`MapCircle`, macOS 14+ SwiftUI API), XCTest, existing `MockURLProtocol` pattern for network tests.

## Global Constraints

- No changes to `species.json`'s schema, the region-picker mechanism (`RegionPickerView`), the shortlist tab, or `SignalAlgorithm`'s scoring logic — reuse `SignalAlgorithm.computeSignal` and `ShortlistRanker`'s tie-break exactly as-is (spec §2).
- Bounding-box + rough-shape filter for Slovakia is acceptable; no survey-grade border polygon (spec, Out of Scope).
- No historical/time-based views, no full species "atlas" — library stays to name + up to 3 photos + existing `Species` fields (spec, Out of Scope).
- All new UI styling routes through `DesignSystem` — no ad hoc literal colors/sizes (project convention, `CLAUDE.md`).
- Every build in this plan uses `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build` or Xcode's own Run — never combine unsigned/headless flags (`CODE_SIGNING_ALLOWED=NO`) with the pinned `-derivedDataPath`, and never hand-run raw `codesign` on the build product afterward. `DEVELOPMENT_TEAM` is already baked into `project.yml`; a plain build is sufficient and required to keep the widget-gallery trust registration intact (see `CLAUDE.md` "Widget-gallery visibility requires..." — this plan doesn't touch the widget target, but a broken build habit here would still break trust registration for the *whole app*, taking the widget down with it).

---

### Task 1: GridPoint model + Slovakia grid generation

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Models/GridPoint.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SlovakiaGridTests.swift`

**Interfaces:**
- Produces: `GridPoint { id: String, latitude: Double, longitude: Double }` (Identifiable, Hashable, Sendable), `SlovakiaGrid.generate() -> [GridPoint]`, `SlovakiaGrid.latitudeRange: ClosedRange<Double>`, `SlovakiaGrid.longitudeRange: ClosedRange<Double>`.

- [ ] **Step 1: Write the failing test**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/SlovakiaGridTests.swift
import XCTest
@testable import MushroomSignalCore

final class SlovakiaGridTests: XCTestCase {
    func testGeneratePointCountLandsInExpectedRange() {
        let points = SlovakiaGrid.generate()
        XCTAssertGreaterThanOrEqual(points.count, 30)
        XCTAssertLessThanOrEqual(points.count, 50)
    }

    func testEveryPointFallsWithinBoundingBox() {
        let points = SlovakiaGrid.generate()
        for point in points {
            XCTAssertTrue(SlovakiaGrid.latitudeRange.contains(point.latitude), "lat \(point.latitude) out of range")
            XCTAssertTrue(SlovakiaGrid.longitudeRange.contains(point.longitude), "lon \(point.longitude) out of range")
        }
    }

    func testPointIDsAreUnique() {
        let points = SlovakiaGrid.generate()
        XCTAssertEqual(Set(points.map(\.id)).count, points.count)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path MushroomSignalCore --filter SlovakiaGridTests`
Expected: FAIL to compile — `GridPoint`/`SlovakiaGrid` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Models/GridPoint.swift
import Foundation

public struct GridPoint: Identifiable, Hashable, Sendable {
    public let id: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, latitude: Double, longitude: Double) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
    }
}
```

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift
import Foundation

/// Generates an evenly-spaced sample grid over Slovakia's bounding box, trimmed by a rough
/// diamond-shaped filter approximating the country's silhouette. Not survey-grade — these points
/// only drive a heat-map visualization, not an authoritative boundary claim (see v2 spec, Out of Scope).
public enum SlovakiaGrid {
    public static let latitudeRange: ClosedRange<Double> = 47.7...49.6
    public static let longitudeRange: ClosedRange<Double> = 16.8...22.6

    private static let latitudeStep = 0.4
    private static let longitudeStep = 0.6
    /// Sum of normalized distance-from-center along each axis must stay within this to be kept —
    /// trims the bounding box's four corners, which fall outside Slovakia's actual silhouette.
    private static let diamondThreshold = 1.4

    public static func generate() -> [GridPoint] {
        let latMid = (latitudeRange.lowerBound + latitudeRange.upperBound) / 2
        let lonMid = (longitudeRange.lowerBound + longitudeRange.upperBound) / 2
        let latSpan = (latitudeRange.upperBound - latitudeRange.lowerBound) / 2
        let lonSpan = (longitudeRange.upperBound - longitudeRange.lowerBound) / 2

        var points: [GridPoint] = []
        var index = 0
        var lat = latitudeRange.lowerBound
        while lat <= latitudeRange.upperBound + 1e-9 {
            var lon = longitudeRange.lowerBound
            while lon <= longitudeRange.upperBound + 1e-9 {
                let normalizedLat = abs(lat - latMid) / latSpan
                let normalizedLon = abs(lon - lonMid) / lonSpan
                if normalizedLat + normalizedLon <= diamondThreshold {
                    points.append(GridPoint(id: "grid-\(String(format: "%02d", index))", latitude: lat, longitude: lon))
                    index += 1
                }
                lon += longitudeStep
            }
            lat += latitudeStep
        }
        return points
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter SlovakiaGridTests`
Expected: PASS, all 3 tests. (Verified during planning: this exact step/threshold combination produces 39 points, comfortably inside 30-50.)

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Models/GridPoint.swift MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SlovakiaGridTests.swift
git commit -m "feat: add GridPoint model and Slovakia sample-grid generation"
```

---

### Task 2: Batched weather fetch (`WeatherClient.fetchSnapshots`)

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift`
- Modify: `MushroomSignalTests/StubWeatherClient.swift` (both actors must keep conforming to the protocol)
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift`

**Interfaces:**
- Consumes: `GridPoint` (Task 1), existing `WeatherSnapshot { regionId, averageTempLast10DaysC, totalPrecipitationLast10DaysMm, fetchedAt }`.
- Produces: `WeatherClient.fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]` keyed by `GridPoint.id`. A point whose response has no usable daily data is **omitted from the result dictionary** (not thrown) — the map view renders a missing point the same as a zero-score point (neutral/dimmed), so a partial-data grid degrades gracefully instead of blanking the whole map.

- [ ] **Step 1: Write the failing test**

```swift
// Append to MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift, inside OpenMeteoClientTests

func testFetchSnapshotsDecodesMultiLocationArrayInOrder() async throws {
    let points = [
        GridPoint(id: "grid-00", latitude: 48.1, longitude: 17.1),
        GridPoint(id: "grid-01", latitude: 49.2, longitude: 18.7)
    ]
    let json = """
    [
      { "daily": { "temperature_2m_mean": [10.0, 12.0], "precipitation_sum": [1.0, 3.0] } },
      { "daily": { "temperature_2m_mean": [20.0, 22.0], "precipitation_sum": [5.0, 5.0] } }
    ]
    """.data(using: .utf8)!

    MockURLProtocol.requestHandler = { request in
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
    }

    let client = OpenMeteoClient(session: makeMockedSession())
    let result = try await client.fetchSnapshots(for: points)

    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result["grid-00"]?.averageTempLast10DaysC, 11.0, accuracy: 0.001)
    XCTAssertEqual(result["grid-00"]?.totalPrecipitationLast10DaysMm, 4.0, accuracy: 0.001)
    XCTAssertEqual(result["grid-01"]?.averageTempLast10DaysC, 21.0, accuracy: 0.001)
}

func testFetchSnapshotsOmitsPointsWithEmptyDailyData() async throws {
    let points = [
        GridPoint(id: "grid-00", latitude: 48.1, longitude: 17.1),
        GridPoint(id: "grid-01", latitude: 49.2, longitude: 18.7)
    ]
    let json = """
    [
      { "daily": { "temperature_2m_mean": [], "precipitation_sum": [] } },
      { "daily": { "temperature_2m_mean": [20.0], "precipitation_sum": [5.0] } }
    ]
    """.data(using: .utf8)!

    MockURLProtocol.requestHandler = { request in
        (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
    }

    let client = OpenMeteoClient(session: makeMockedSession())
    let result = try await client.fetchSnapshots(for: points)

    XCTAssertNil(result["grid-00"])
    XCTAssertNotNil(result["grid-01"])
}

func testFetchSnapshotsReturnsEmptyForEmptyInput() async throws {
    let client = OpenMeteoClient(session: makeMockedSession())
    let result = try await client.fetchSnapshots(for: [])
    XCTAssertTrue(result.isEmpty)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path MushroomSignalCore --filter OpenMeteoClientTests`
Expected: FAIL to compile — `fetchSnapshots` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift
import Foundation

public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot]
}
```

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift — add this method to the existing OpenMeteoClient struct
public func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
    guard !points.isEmpty else { return [:] }

    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [
        URLQueryItem(name: "latitude", value: points.map { String($0.latitude) }.joined(separator: ",")),
        URLQueryItem(name: "longitude", value: points.map { String($0.longitude) }.joined(separator: ",")),
        URLQueryItem(name: "daily", value: "temperature_2m_mean,precipitation_sum"),
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
        let precipitation = pointResponse.daily.precipitationSum.compactMap { $0 }
        guard !temps.isEmpty, !precipitation.isEmpty else { continue }
        result[point.id] = WeatherSnapshot(
            regionId: point.id,
            averageTempLast10DaysC: temps.reduce(0, +) / Double(temps.count),
            totalPrecipitationLast10DaysMm: precipitation.reduce(0, +),
            fetchedAt: Date()
        )
    }
    return result
}
```

```swift
// MushroomSignalTests/StubWeatherClient.swift — replace the whole file
import MushroomSignalCore

actor StubWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}

    private var snapshots: [WeatherSnapshot?]
    private var callIndex = 0
    private let gridSnapshots: [String: WeatherSnapshot]
    private let gridShouldThrow: Bool

    init(snapshots: [WeatherSnapshot?], gridSnapshots: [String: WeatherSnapshot] = [:], gridShouldThrow: Bool = false) {
        self.snapshots = snapshots
        self.gridSnapshots = gridSnapshots
        self.gridShouldThrow = gridShouldThrow
    }

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        let index = min(callIndex, snapshots.count - 1)
        callIndex += 1
        guard let snapshot = snapshots[index] else { throw StubError() }
        return snapshot
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        if gridShouldThrow { throw StubError() }
        return gridSnapshots
    }
}

actor DelayedWeatherClient: WeatherClient {
    struct StubError: Error, Sendable {}
    private var callCount = 0

    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot {
        callCount += 1
        if callCount == 1 {
            try? await Task.sleep(for: .milliseconds(200))
            throw StubError()
        }
        return WeatherSnapshot(regionId: region.id, averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 20, fetchedAt: .now)
    }

    func fetchSnapshots(for points: [GridPoint]) async throws -> [String: WeatherSnapshot] {
        [:]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter OpenMeteoClientTests`
Expected: PASS, all tests including the 3 new ones.

Then confirm the app target (which depends on `StubWeatherClient`) still compiles:
Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift MushroomSignalTests/StubWeatherClient.swift
git commit -m "feat: add batched multi-location weather fetch for the map grid"
```

---

### Task 3: Dominant-species resolution

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/DominantSpeciesResolver.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift`

**Interfaces:**
- Consumes: existing `SignalAlgorithm.computeSignal(species:weather:month:) -> SpeciesSignal`, existing `ShortlistRanker.topSpecies(from:limit:) -> [SpeciesSignal]`, existing `Species`, `WeatherSnapshot`.
- Produces: `DominantSpeciesResolver.resolve(activeSpecies: [Species], weather: WeatherSnapshot, month: Int) -> Species?` — `nil` means "render neutral" (no active species, or every active species scored 0 at this point).

- [ ] **Step 1: Write the failing test**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift
import XCTest
@testable import MushroomSignalCore

final class DominantSpeciesResolverTests: XCTestCase {
    private let warmWetWeather = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 16, totalPrecipitationLast10DaysMm: 25, fetchedAt: .now)

    private func species(id: String, name: String, edibility: Edibility, minC: Double, maxC: Double, months: Set<Int> = [6, 7, 8, 9]) -> Species {
        Species(id: id, commonNameSk: name, latinName: id, edibility: edibility, fruitingMonths: months, idealTempMinC: minC, idealTempMaxC: maxC, rainfallSensitivity: .low, habitat: "test", regionalAffinity: [])
    }

    func testResolvesHighestScoringActiveSpecies() {
        let strongMatch = species(id: "a", name: "Alpha", edibility: .edible, minC: 10, maxC: 20)
        let weakMatch = species(id: "b", name: "Beta", edibility: .edible, minC: 30, maxC: 35)
        let result = DominantSpeciesResolver.resolve(activeSpecies: [strongMatch, weakMatch], weather: warmWetWeather, month: 7)
        XCTAssertEqual(result?.id, "a")
    }

    func testReturnsNilWhenNoActiveSpecies() {
        let result = DominantSpeciesResolver.resolve(activeSpecies: [], weather: warmWetWeather, month: 7)
        XCTAssertNil(result)
    }

    func testReturnsNilWhenEveryActiveSpeciesScoresZero() {
        let outOfSeason = species(id: "a", name: "Alpha", edibility: .edible, minC: 10, maxC: 20, months: [1])
        let result = DominantSpeciesResolver.resolve(activeSpecies: [outOfSeason], weather: warmWetWeather, month: 7)
        XCTAssertNil(result)
    }

    func testTiesBreakByEdibilityThenName() {
        let poisonousA = species(id: "a", name: "Zeta", edibility: .poisonous, minC: 10, maxC: 20)
        let edibleB = species(id: "b", name: "Alpha", edibility: .edible, minC: 10, maxC: 20)
        let result = DominantSpeciesResolver.resolve(activeSpecies: [poisonousA, edibleB], weather: warmWetWeather, month: 7)
        XCTAssertEqual(result?.id, "b", "edible should win the tie over poisonous regardless of name order")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path MushroomSignalCore --filter DominantSpeciesResolverTests`
Expected: FAIL to compile — `DominantSpeciesResolver` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Signal/DominantSpeciesResolver.swift
import Foundation

/// Picks which active species "wins" the color at a single map grid point. Reuses the exact same
/// scoring (`SignalAlgorithm`) and tie-break (`ShortlistRanker`) as the shortlist — no new algorithm
/// (v2 spec §2).
public enum DominantSpeciesResolver {
    public static func resolve(activeSpecies: [Species], weather: WeatherSnapshot, month: Int) -> Species? {
        guard !activeSpecies.isEmpty else { return nil }
        let signals = activeSpecies.map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
        guard let top = ShortlistRanker.topSpecies(from: signals, limit: 1).first, top.score > 0 else {
            return nil
        }
        return top.species
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter DominantSpeciesResolverTests`
Expected: PASS, all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Signal/DominantSpeciesResolver.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/DominantSpeciesResolverTests.swift
git commit -m "feat: add dominant-species resolver for map heat rendering"
```

---

### Task 4: Species photo model + loader

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Models/SpeciesPhoto.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Data/SpeciesPhotoDatabase.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Data/species-photos.json`
- Modify: `MushroomSignalCore/Package.swift` (register the new resource)
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesPhotoDatabaseTests.swift`

**Interfaces:**
- Produces: `SpeciesPhoto { id, speciesId, imageURL: URL, photographer: String, license: String, sourceURL: URL }` (Codable, Identifiable, Sendable), `SpeciesPhotoDatabase.loadAll() throws -> [SpeciesPhoto]`.

**Deliberate scope note (Hard Rule 4 — tech debt, declared):** `species-photos.json` ships as an empty `[]` in this task. Photo curation means finding and verifying real Wikimedia Commons URLs/photographer credits per species — fabricating plausible-looking entries here would violate the "never invent facts" rule and could ship dead links or wrong attribution. Cost: the species library shows the placeholder image for all 27 species until curated. Follow-up: Alexander adds real entries to `species-photos.json` by hand over time (matches the spec's own framing: "an ongoing, independent task"). The decode logic and zero-photos path are still fully tested below.

- [ ] **Step 1: Write the failing test**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesPhotoDatabaseTests.swift
import XCTest
@testable import MushroomSignalCore

final class SpeciesPhotoDatabaseTests: XCTestCase {
    func testSpeciesPhotoDecodesFromJSON() throws {
        let json = """
        {
          "id": "boletus-edulis-1",
          "speciesId": "boletus-edulis",
          "imageURL": "https://upload.wikimedia.org/wikipedia/commons/example.jpg",
          "photographer": "Jane Doe",
          "license": "CC BY-SA 4.0",
          "sourceURL": "https://commons.wikimedia.org/wiki/File:example.jpg"
        }
        """.data(using: .utf8)!

        let photo = try JSONDecoder().decode(SpeciesPhoto.self, from: json)

        XCTAssertEqual(photo.speciesId, "boletus-edulis")
        XCTAssertEqual(photo.license, "CC BY-SA 4.0")
        XCTAssertEqual(photo.imageURL, URL(string: "https://upload.wikimedia.org/wikipedia/commons/example.jpg"))
    }

    func testLoadAllReturnsEmptyArrayForCurrentBundledFile() throws {
        // species-photos.json ships empty pending manual curation — this proves the loader
        // handles the zero-photos case cleanly rather than throwing.
        let photos = try SpeciesPhotoDatabase.loadAll()
        XCTAssertEqual(photos, [])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path MushroomSignalCore --filter SpeciesPhotoDatabaseTests`
Expected: FAIL to compile — `SpeciesPhoto`/`SpeciesPhotoDatabase` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Models/SpeciesPhoto.swift
import Foundation

public struct SpeciesPhoto: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let speciesId: String
    public let imageURL: URL
    public let photographer: String
    public let license: String
    public let sourceURL: URL

    public init(id: String, speciesId: String, imageURL: URL, photographer: String, license: String, sourceURL: URL) {
        self.id = id
        self.speciesId = speciesId
        self.imageURL = imageURL
        self.photographer = photographer
        self.license = license
        self.sourceURL = sourceURL
    }
}
```

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Data/SpeciesPhotoDatabase.swift
import Foundation

public enum SpeciesPhotoDatabaseError: Error, Equatable {
    case resourceNotFound
}

public enum SpeciesPhotoDatabase {
    public static func loadAll() throws -> [SpeciesPhoto] {
        guard let url = Bundle.module.url(forResource: "species-photos", withExtension: "json") else {
            throw SpeciesPhotoDatabaseError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([SpeciesPhoto].self, from: data)
    }
}
```

```json
// MushroomSignalCore/Sources/MushroomSignalCore/Data/species-photos.json
[]
```

```swift
// MushroomSignalCore/Package.swift — modify the .target resources list
.target(
    name: "MushroomSignalCore",
    resources: [.process("Data/species.json"), .process("Data/species-photos.json")]
),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter SpeciesPhotoDatabaseTests`
Expected: PASS, both tests.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Models/SpeciesPhoto.swift MushroomSignalCore/Sources/MushroomSignalCore/Data/SpeciesPhotoDatabase.swift MushroomSignalCore/Sources/MushroomSignalCore/Data/species-photos.json MushroomSignalCore/Package.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesPhotoDatabaseTests.swift
git commit -m "feat: add species photo model and loader (empty dataset pending curation)"
```

---

### Task 5: Species color palette + toggle-order color assignment

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/SpeciesColorAssigner.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesColorAssignerTests.swift`

**Interfaces:**
- Produces: `DesignSystem.Colors.speciesPalette: [Color]` (8 curated hues), `SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: [String]) -> [String: Color]`.

- [ ] **Step 1: Write the failing test**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesColorAssignerTests.swift
import XCTest
import SwiftUI
@testable import MushroomSignalCore

final class SpeciesColorAssignerTests: XCTestCase {
    func testAssignsDistinctColorsInToggleOrder() {
        let result = SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: ["a", "b", "c"])
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result["a"], DesignSystem.Colors.speciesPalette[0])
        XCTAssertEqual(result["b"], DesignSystem.Colors.speciesPalette[1])
        XCTAssertEqual(result["c"], DesignSystem.Colors.speciesPalette[2])
    }

    func testCyclesPaletteWhenMoreSpeciesThanColors() {
        let paletteSize = DesignSystem.Colors.speciesPalette.count
        let ids = (0..<(paletteSize + 2)).map { "species-\($0)" }
        let result = SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: ids)
        XCTAssertEqual(result[ids[0]], result[ids[paletteSize]], "should wrap back to the first color")
    }

    func testEmptyInputReturnsEmptyMapping() {
        XCTAssertTrue(SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: []).isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path MushroomSignalCore --filter SpeciesColorAssignerTests`
Expected: FAIL to compile — `SpeciesColorAssigner` / `speciesPalette` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift — add inside `public enum Colors { ... }`, after `caution`
public static let speciesPalette: [Color] = [
    Color(red: 0.90, green: 0.49, blue: 0.13), // amber
    Color(red: 0.36, green: 0.61, blue: 0.84), // sky blue
    Color(red: 0.80, green: 0.36, blue: 0.62), // magenta
    Color(red: 0.95, green: 0.82, blue: 0.25), // gold
    Color(red: 0.42, green: 0.75, blue: 0.70), // teal
    Color(red: 0.65, green: 0.44, blue: 0.86), // violet
    Color(red: 0.85, green: 0.35, blue: 0.32), // coral red
    Color(red: 0.55, green: 0.70, blue: 0.30)  // lime
]
```

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/SpeciesColorAssigner.swift
import SwiftUI

/// Maps active species to map colors in the order they were toggled on, cycling the curated
/// palette if more species are active than there are distinct colors (v2 spec §2).
public enum SpeciesColorAssigner {
    public static func colors(forActiveSpeciesInToggleOrder speciesIDs: [String]) -> [String: Color] {
        let palette = DesignSystem.Colors.speciesPalette
        guard !palette.isEmpty else { return [:] }
        var result: [String: Color] = [:]
        for (index, id) in speciesIDs.enumerated() {
            result[id] = palette[index % palette.count]
        }
        return result
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path MushroomSignalCore --filter SpeciesColorAssignerTests`
Expected: PASS, all 3 tests.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/SpeciesColorAssigner.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesColorAssignerTests.swift
git commit -m "feat: add species accent palette and toggle-order color assignment"
```

---

### Task 6: `MapScreenState`

**Files:**
- Create: `MushroomSignal/MapScreenState.swift`
- Test: `MushroomSignalTests/MapScreenStateTests.swift`

**Interfaces:**
- Consumes: `GridPoint`, `SlovakiaGrid.generate()`, `WeatherClient` (Tasks 1-2), `DominantSpeciesResolver` (Task 3), `SpeciesPhoto`, `SpeciesPhotoDatabase` (Task 4), `SpeciesColorAssigner` (Task 5), existing `Species`, `SpeciesDatabase`.
- Produces: `MapScreenState` (`@MainActor`, `ObservableObject`) with:
  - `@Published var activeSpeciesOrder: [String]`
  - `@Published var snapshots: [String: WeatherSnapshot]`
  - `@Published var isLoading: Bool`
  - `@Published var errorMessage: String?`
  - `let gridPoints: [GridPoint]`
  - `let allSpecies: [Species]`
  - `let photosBySpeciesID: [String: [SpeciesPhoto]]`
  - `func toggleSpecies(_ id: String)`
  - `func isActive(_ id: String) -> Bool`
  - `func loadGrid() async`
  - `func dominantSpecies(at pointID: String) -> Species?`
  - `var speciesColors: [String: Color]`

- [ ] **Step 1: Write the failing test**

```swift
// MushroomSignalTests/MapScreenStateTests.swift
import XCTest
@testable import MushroomSignal
import MushroomSignalCore

@MainActor
final class MapScreenStateTests: XCTestCase {
    func testLoadGridPopulatesSnapshotsOnSuccess() async {
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let client = StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot])
        let state = MapScreenState(weatherClient: client)

        await state.loadGrid()

        XCTAssertEqual(state.snapshots["grid-00"], snapshot)
        XCTAssertNil(state.errorMessage)
        XCTAssertFalse(state.isLoading)
    }

    func testLoadGridSetsErrorMessageOnFailure() async {
        let client = StubWeatherClient(snapshots: [nil], gridShouldThrow: true)
        let state = MapScreenState(weatherClient: client)

        await state.loadGrid()

        XCTAssertTrue(state.snapshots.isEmpty)
        XCTAssertNotNil(state.errorMessage)
    }

    func testToggleSpeciesTracksOnOffOrder() {
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil]))
        XCTAssertFalse(state.isActive("boletus-edulis"))

        state.toggleSpecies("boletus-edulis")
        XCTAssertTrue(state.isActive("boletus-edulis"))
        XCTAssertEqual(state.activeSpeciesOrder, ["boletus-edulis"])

        state.toggleSpecies("boletus-edulis")
        XCTAssertFalse(state.isActive("boletus-edulis"))
        XCTAssertEqual(state.activeSpeciesOrder, [])
    }

    func testDominantSpeciesReturnsNilWithNoActiveSpecies() async {
        // Load a real snapshot first so the assertion below exercises the "no active species"
        // path specifically, not the separate "no snapshot for this point" early-return.
        let snapshot = WeatherSnapshot(regionId: "grid-00", averageTempLast10DaysC: 15, totalPrecipitationLast10DaysMm: 10, fetchedAt: .now)
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil], gridSnapshots: ["grid-00": snapshot]))
        await state.loadGrid()

        XCTAssertNil(state.dominantSpecies(at: "grid-00"))
    }

    func testDominantSpeciesReturnsNilWhenSnapshotMissing() {
        let state = MapScreenState(weatherClient: StubWeatherClient(snapshots: [nil]))
        state.toggleSpecies("boletus-edulis")
        XCTAssertNil(state.dominantSpecies(at: "grid-00"), "no snapshot was ever loaded for this point")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData -only-testing:MushroomSignalTests/MapScreenStateTests`
Expected: FAIL to compile — `MapScreenState` not defined.

- [ ] **Step 3: Write minimal implementation**

```swift
// MushroomSignal/MapScreenState.swift
import Foundation
import SwiftUI
import os
import MushroomSignalCore

@MainActor
final class MapScreenState: ObservableObject {
    @Published var activeSpeciesOrder: [String] = []
    @Published var snapshots: [String: WeatherSnapshot] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?

    let gridPoints: [GridPoint]
    let allSpecies: [Species]
    let photosBySpeciesID: [String: [SpeciesPhoto]]

    private let weatherClient: WeatherClient
    private let logger = Logger(subsystem: "com.alexandersalinka.MushroomSignal", category: "MapScreenState")

    init(weatherClient: WeatherClient = OpenMeteoClient()) {
        self.weatherClient = weatherClient
        self.gridPoints = SlovakiaGrid.generate()
        self.allSpecies = (try? SpeciesDatabase.loadAll()) ?? []
        let photos = (try? SpeciesPhotoDatabase.loadAll()) ?? []
        self.photosBySpeciesID = Dictionary(grouping: photos, by: \.speciesId)
    }

    func toggleSpecies(_ id: String) {
        if let index = activeSpeciesOrder.firstIndex(of: id) {
            activeSpeciesOrder.remove(at: index)
        } else {
            activeSpeciesOrder.append(id)
        }
    }

    func isActive(_ id: String) -> Bool {
        activeSpeciesOrder.contains(id)
    }

    func loadGrid() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            snapshots = try await weatherClient.fetchSnapshots(for: gridPoints)
        } catch {
            snapshots = [:]
            errorMessage = "Nepodarilo sa načítať mapu počasia. Skúste to znova."
            logger.error("Grid weather fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    func dominantSpecies(at pointID: String) -> Species? {
        guard let snapshot = snapshots[pointID] else { return nil }
        let active = allSpecies.filter { activeSpeciesOrder.contains($0.id) }
        guard !active.isEmpty else { return nil }
        let month = Calendar.current.component(.month, from: Date())
        return DominantSpeciesResolver.resolve(activeSpecies: active, weather: snapshot, month: month)
    }

    var speciesColors: [String: Color] {
        SpeciesColorAssigner.colors(forActiveSpeciesInToggleOrder: activeSpeciesOrder)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `xcodebuild test -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData -only-testing:MushroomSignalTests/MapScreenStateTests`
Expected: PASS, all 4 tests.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/MapScreenState.swift MushroomSignalTests/MapScreenStateTests.swift
git commit -m "feat: add MapScreenState to drive the interactive map screen"
```

---

### Task 7: `InteractiveMapView`

**Files:**
- Create: `MushroomSignal/Views/InteractiveMapView.swift`

**Interfaces:**
- Consumes: `MapScreenState` (Task 6) — `gridPoints`, `snapshots`, `dominantSpecies(at:)`, `speciesColors`, `isLoading`, `errorMessage`, `loadGrid()`.
- Produces: `InteractiveMapView(mapState: MapScreenState)` SwiftUI View.

- [ ] **Step 1: Write the view**

```swift
// MushroomSignal/Views/InteractiveMapView.swift
import SwiftUI
import MapKit
import MushroomSignalCore

struct InteractiveMapView: View {
    @ObservedObject var mapState: MapScreenState

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.65, longitude: 19.7),
            span: MKCoordinateSpan(latitudeDelta: 2.6, longitudeDelta: 6.6)
        )
    )

    /// Circle radius chosen so ~39 grid points visually tile Slovakia without large gaps.
    private let gridPointRadiusMeters: CLLocationDistance = 18000

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map(position: $cameraPosition) {
                ForEach(mapState.gridPoints) { point in
                    MapCircle(center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), radius: gridPointRadiusMeters)
                        .foregroundStyle(color(for: point))
                        .stroke(.clear)
                }
            }
            .mapStyle(.standard(elevation: .flat))

            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                if mapState.isLoading {
                    ProgressView().padding(DesignSystem.spacingSmall)
                }
                if let error = mapState.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(DesignSystem.Colors.danger)
                        .padding(DesignSystem.spacingSmall)
                        .background(DesignSystem.Colors.forestDeep.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
                }
                legend
            }
            .padding(DesignSystem.spacingMedium)
        }
        .task { await mapState.loadGrid() }
    }

    private func color(for point: GridPoint) -> Color {
        guard let dominant = mapState.dominantSpecies(at: point.id), let assigned = mapState.speciesColors[dominant.id] else {
            return DesignSystem.Colors.bark.opacity(0.3)
        }
        return assigned.opacity(0.75)
    }

    @ViewBuilder
    private var legend: some View {
        if !mapState.activeSpeciesOrder.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                ForEach(mapState.activeSpeciesOrder, id: \.self) { id in
                    if let species = mapState.allSpecies.first(where: { $0.id == id }), let color = mapState.speciesColors[id] {
                        HStack(spacing: DesignSystem.spacingTight * 2) {
                            Circle().fill(color).frame(width: 8, height: 8)
                            Text(species.commonNameSk)
                                .font(.caption2)
                                .foregroundStyle(DesignSystem.Colors.cloud)
                        }
                    }
                }
            }
            .padding(DesignSystem.spacingSmall)
            .background(DesignSystem.Colors.forestDeep.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`. No unit-test surface for pure map layout (matches v1's approach for widget layouts, per spec Testing section) — verify visually via Xcode preview or Task 10's manual run-through.

- [ ] **Step 3: Commit**

```bash
git add MushroomSignal/Views/InteractiveMapView.swift
git commit -m "feat: add InteractiveMapView with dominant-species heat mosaic"
```

---

### Task 8: `SpeciesLibraryView`

**Files:**
- Create: `MushroomSignal/Views/SpeciesLibraryView.swift`

**Interfaces:**
- Consumes: `MapScreenState` (Task 6) — `allSpecies`, `photosBySpeciesID`, `isActive(_:)`, `toggleSpecies(_:)`.
- Produces: `SpeciesLibraryView(mapState: MapScreenState)` SwiftUI View. Internally manages `@State private var columnCount: Int` and `@State private var detailSpecies: Species?` (drives a `.sheet` to `SpeciesDetailView`, built in Task 9).

- [ ] **Step 1: Write the view**

```swift
// MushroomSignal/Views/SpeciesLibraryView.swift
import SwiftUI
import MushroomSignalCore

struct SpeciesLibraryView: View {
    @ObservedObject var mapState: MapScreenState
    @State private var columnCount = 3
    @State private var detailSpecies: Species?

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DesignSystem.spacingSmall), count: columnCount)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            HStack {
                Text("Knižnica druhov")
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.cloud)
                Spacer()
                Stepper("Stĺpce: \(columnCount)", value: $columnCount, in: 2...4)
                    .fixedSize()
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.8))
            }

            LazyVGrid(columns: columns, spacing: DesignSystem.spacingSmall) {
                ForEach(mapState.allSpecies) { species in
                    speciesCard(species)
                }
            }
        }
        .sheet(item: $detailSpecies) { species in
            SpeciesDetailView(species: species, photos: mapState.photosBySpeciesID[species.id] ?? [])
        }
    }

    private func speciesCard(_ species: Species) -> some View {
        let active = mapState.isActive(species.id)
        let photo = mapState.photosBySpeciesID[species.id]?.first

        return VStack(spacing: DesignSystem.spacingTight * 2) {
            ZStack(alignment: .topTrailing) {
                photoThumbnail(photo)
                Button {
                    detailSpecies = species
                } label: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(DesignSystem.Colors.cloud)
                        .background(Circle().fill(DesignSystem.Colors.forestDeep.opacity(0.7)))
                }
                .buttonStyle(.plain)
                .padding(4)
            }

            Text(species.commonNameSk)
                .font(.caption)
                .foregroundStyle(DesignSystem.Colors.cloud)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(DesignSystem.spacingSmall)
        .background(active ? DesignSystem.Colors.mossAccent.opacity(0.35) : DesignSystem.Colors.forestMid.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3)
                .stroke(active ? DesignSystem.Colors.mossAccent : .clear, lineWidth: 2)
        )
        .onTapGesture { mapState.toggleSpecies(species.id) }
    }

    @ViewBuilder
    private func photoThumbnail(_ photo: SpeciesPhoto?) -> some View {
        if let photo {
            AsyncImage(url: photo.imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 4))
        } else {
            placeholder.frame(height: 70)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 4)
            .fill(DesignSystem.Colors.bark.opacity(0.4))
            .overlay(Image(systemName: "photo").foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5)))
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: fails at this point only because `SpeciesDetailView` doesn't exist yet (Task 9) — that's expected; confirm the *only* error is the missing type, not something in this file.

- [ ] **Step 3: Commit**

```bash
git add MushroomSignal/Views/SpeciesLibraryView.swift
git commit -m "feat: add SpeciesLibraryView grid with map-layer toggles"
```

---

### Task 9: `SpeciesDetailView` + `PhotoCreditsView`

**Files:**
- Create: `MushroomSignal/Views/SpeciesDetailView.swift`
- Create: `MushroomSignal/Views/PhotoCreditsView.swift`

**Interfaces:**
- Consumes: `Species`, `SpeciesPhoto` (Task 4).
- Produces: `SpeciesDetailView(species: Species, photos: [SpeciesPhoto])`, `PhotoCreditsView(photos: [SpeciesPhoto])` SwiftUI Views.

- [ ] **Step 1: Write the views**

```swift
// MushroomSignal/Views/SpeciesDetailView.swift
import SwiftUI
import MushroomSignalCore

struct SpeciesDetailView: View {
    let species: Species
    let photos: [SpeciesPhoto]
    @Environment(\.dismiss) private var dismiss
    @State private var showingCredits = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                    if !photos.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: DesignSystem.spacingSmall) {
                                ForEach(photos) { photo in
                                    AsyncImage(url: photo.imageURL) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            DesignSystem.Colors.bark.opacity(0.4)
                                        }
                                    }
                                    .frame(width: 220, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
                                }
                            }
                        }
                    }

                    Text(species.commonNameSk)
                        .font(.title2.bold())
                        .foregroundStyle(DesignSystem.Colors.cloud)
                    Text(species.latinName)
                        .font(.subheadline).italic()
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))

                    if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                        Text(warning)
                            .font(.subheadline.bold())
                            .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                    }

                    detailRow(title: "Biotop", value: species.habitat)
                    if !species.lookAlikes.isEmpty {
                        detailRow(title: "Zámena s", value: species.lookAlikes.joined(separator: ", "))
                    }

                    if !photos.isEmpty {
                        Button("Zdroje fotografií") { showingCredits = true }
                            .font(.caption)
                    }
                }
                .padding(DesignSystem.spacingLarge)
            }
            .background(DesignSystem.Colors.forestDeep)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavrieť") { dismiss() }
                }
            }
            .sheet(isPresented: $showingCredits) {
                PhotoCreditsView(photos: photos)
            }
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            Text(value)
                .font(.body)
                .foregroundStyle(DesignSystem.Colors.cloud)
        }
    }
}
```

```swift
// MushroomSignal/Views/PhotoCreditsView.swift
import SwiftUI
import MushroomSignalCore

struct PhotoCreditsView: View {
    let photos: [SpeciesPhoto]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(photos) { photo in
                VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                    Text(photo.photographer).font(.subheadline.bold())
                    Text(photo.license).font(.caption).foregroundStyle(.secondary)
                    Link(destination: photo.sourceURL) {
                        Text(photo.sourceURL.absoluteString)
                            .font(.caption2)
                            .lineLimit(1)
                    }
                }
            }
            .navigationTitle("Zdroje fotografií")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavrieť") { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **` — this resolves the type Task 8 was missing.

- [ ] **Step 3: Commit**

```bash
git add MushroomSignal/Views/SpeciesDetailView.swift MushroomSignal/Views/PhotoCreditsView.swift
git commit -m "feat: add species detail sheet and photo attribution view"
```

---

### Task 10: Wire the combined map screen into `ContentView`, retire `RegionMapView`

**Files:**
- Create: `MushroomSignal/Views/MapScreenView.swift`
- Modify: `MushroomSignal/ContentView.swift`
- Delete: `MushroomSignal/Views/RegionMapView.swift`

**Interfaces:**
- Consumes: `InteractiveMapView` (Task 7), `SpeciesLibraryView` (Task 8), `MapScreenState` (Task 6).
- Produces: `MapScreenView()` — owns its own `@StateObject private var mapState = MapScreenState()`, combines the map and library per spec §3 ("combined into the map screen, not a separate tab").

- [ ] **Step 1: Write the combined screen**

```swift
// MushroomSignal/Views/MapScreenView.swift
import SwiftUI

struct MapScreenView: View {
    @StateObject private var mapState = MapScreenState()

    var body: some View {
        ScrollView {
            VStack(spacing: DesignSystem.spacingLarge) {
                InteractiveMapView(mapState: mapState)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))

                SpeciesLibraryView(mapState: mapState)
            }
            .padding(DesignSystem.spacingLarge)
        }
        .background(DesignSystem.Colors.forestDeep)
    }
}
```

- [ ] **Step 2: Wire into ContentView**

```swift
// MushroomSignal/ContentView.swift — replace the RegionMapView tab
RegionMapView(appState: appState)
    .tabItem { Label("Mapa", systemImage: "map") }
    .tag(Tab.map)
```
becomes:
```swift
MapScreenView()
    .tabItem { Label("Mapa", systemImage: "map") }
    .tag(Tab.map)
```

- [ ] **Step 3: Delete the superseded schematic map**

```bash
git rm MushroomSignal/Views/RegionMapView.swift
```

- [ ] **Step 4: Build to verify everything compiles together**

Run: `xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`, no references to the deleted `RegionMapView` remain (the build itself proves this — a dangling reference is a compile error).

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/Views/MapScreenView.swift MushroomSignal/ContentView.swift
git commit -m "feat: replace schematic region map with combined interactive map + species library"
```

---

### Task 11: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Run the full Core test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: all tests pass, including every test added in Tasks 1-5.

- [ ] **Step 2: Run the full app test suite via a real Xcode-path build**

Run: `xcodebuild test -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData`
Expected: all tests pass, including `MapScreenStateTests` (Task 6) and every pre-existing test (`AppStateTests`, etc. — this is also a regression check that nothing in this feature broke the shortlist/region-picker/widget-reload code this plan didn't touch).

- [ ] **Step 3: Manual verification — the actual point of this plan**

Run the app via Xcode (⌘R) — **not** headless `xcodebuild`, since Task 10 changes user-facing UI that needs eyes on it, and per this week's finding, an Xcode Run is also what keeps the widget-gallery trust registration intact:
1. Open the "Mapa" tab — confirm the interactive map renders, pans/zooms.
2. Toggle 2-3 species on in the library grid — confirm the map recolors, the legend updates, colors stay stable across toggles.
3. Toggle all of them back off — confirm the map returns to neutral/dimmed.
4. Tap a species card's "i" button — confirm the detail sheet opens with placeholder image (photos are empty per Task 4's declared scope) and correct data.
5. Confirm the widget gallery (right-click Desktop → Edit Widgets) still shows Mushroom Signal in all three sizes — this plan doesn't touch the widget target, but this is the cheap regression check for this week's actual incident.

- [ ] **Step 4: Update `KNOWN_ISSUES.md` and `CLAUDE.md` if manual verification finds anything deferred**

If step 3 surfaces anything not worth blocking on (e.g. map pan performance, exact color contrast), log it in `docs/superpowers/KNOWN_ISSUES.md` rather than silently shipping it unmentioned — matches this project's existing convention.

- [ ] **Step 5: Final commit if any fixes were needed**

```bash
git add -A
git commit -m "fix: close v2 map/library gaps found in manual verification"
```
(Skip this step entirely if step 3 found nothing — don't commit an empty diff.)
