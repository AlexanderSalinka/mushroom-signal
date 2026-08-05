# Mushroom Signal MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS small-widget + companion app that shows a ranked shortlist of mushroom species likely fruiting in the user's selected Slovak region, based on an original species knowledge base and live Open-Meteo weather data.

**Architecture:** A local Swift package (`MushroomSignalCore`) holds all data models, the species dataset, the weather client, and the signal-scoring algorithm — fully buildable and testable via `swift test`, no Xcode required. An Xcode project (generated via XcodeGen from `project.yml`) wraps that package in two targets: the `MushroomSignal` app and the `MushroomSignalWidgetExtension` widget, sharing selected-region state through an App Group.

**Tech Stack:** Swift 6 / SwiftUI / WidgetKit, Swift Package Manager, XcodeGen, Open-Meteo REST API (no key required), XCTest.

## Global Constraints

- Platform: macOS 14.0+ (Sonoma), native Swift/SwiftUI + WidgetKit only — no backend/server, everything on-device.
- No secrets/API keys anywhere — Open-Meteo requires none.
- No scraping of nahuby.sk or any third-party site — species data is original content compiled by Claude.
- Widget supports `.systemSmall` family only for v1.
- All user-facing UI copy is in Slovak.
- Visual design follows a forest/nature palette (deep greens, bark browns, water blue, cloud grey/white) with a golden-ratio (1.618) spacing scale — defined once in `DesignSystem` and reused everywhere, never inlined ad hoc.
- Species dataset: ~25-30 entries, each with a stable `id`, compiled from general mycological knowledge, not copied from any single source.
- Location is a manual 8-kraj picker — no GPS/CoreLocation.
- Because the dataset includes poisonous species (e.g. Amanita phalloides) and lookalike pairs, the companion app must show a foraging-safety disclaimer and flag poisonous entries — this is not optional polish, it's a correctness requirement given the domain.

---

## Phase A — Core logic (Swift Package, buildable/testable right now, no Xcode needed)

### Task 1: Package scaffold + Species/Region models

**Files:**
- Create: `MushroomSignalCore/Package.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Models/Species.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Models/Region.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/ModelDecodingTests.swift`

**Interfaces:**
- Produces: `Species` (Codable, Identifiable, Equatable, Sendable), `Region` (Codable, Identifiable, Equatable, Sendable, Hashable), `Edibility` enum (`.edible`/`.caution`/`.poisonous`), `RainfallSensitivity` enum (`.low`/`.medium`/`.high`).

- [ ] **Step 1: Create the package structure and `Package.swift`**

```bash
mkdir -p ~/Coding/mushroom-signal/MushroomSignalCore/Sources/MushroomSignalCore/Models
mkdir -p ~/Coding/mushroom-signal/MushroomSignalCore/Tests/MushroomSignalCoreTests
```

```swift
// MushroomSignalCore/Package.swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MushroomSignalCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MushroomSignalCore", targets: ["MushroomSignalCore"])
    ],
    targets: [
        .target(name: "MushroomSignalCore"),
        .testTarget(
            name: "MushroomSignalCoreTests",
            dependencies: ["MushroomSignalCore"]
        )
    ]
)
```

- [ ] **Step 2: Write the failing test**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/ModelDecodingTests.swift
import XCTest
@testable import MushroomSignalCore

final class ModelDecodingTests: XCTestCase {
    func testSpeciesDecodesFromJSON() throws {
        let json = """
        {
          "id": "boletus-edulis",
          "commonNameSk": "Hríb smrekový",
          "latinName": "Boletus edulis",
          "edibility": "edible",
          "lookAlikes": ["tylopilus-felleus"],
          "fruitingMonths": [6,7,8,9,10],
          "idealTempMinC": 12,
          "idealTempMaxC": 22,
          "rainfallSensitivity": "high",
          "habitat": "smrekové a borovicové lesy",
          "regionalAffinity": ["zilinsky", "presovsky"]
        }
        """.data(using: .utf8)!

        let species = try JSONDecoder().decode(Species.self, from: json)

        XCTAssertEqual(species.id, "boletus-edulis")
        XCTAssertEqual(species.commonNameSk, "Hríb smrekový")
        XCTAssertEqual(species.edibility, .edible)
        XCTAssertEqual(species.fruitingMonths, [6, 7, 8, 9, 10])
        XCTAssertEqual(species.rainfallSensitivity, .high)
        XCTAssertEqual(species.regionalAffinity, ["zilinsky", "presovsky"])
    }

    func testRegionDecodesFromJSON() throws {
        let json = """
        { "id": "zilinsky", "nameSk": "Žilinský kraj", "latitude": 49.2231, "longitude": 18.7394 }
        """.data(using: .utf8)!

        let region = try JSONDecoder().decode(Region.self, from: json)

        XCTAssertEqual(region.id, "zilinsky")
        XCTAssertEqual(region.latitude, 49.2231, accuracy: 0.0001)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore`
Expected: FAIL to compile — `Species`/`Region` do not exist yet.

- [ ] **Step 4: Implement the models**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Models/Species.swift
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
        self.rainfallSensitivity = rainfallSensitivity
        self.habitat = habitat
        self.regionalAffinity = regionalAffinity
    }
}
```

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Models/Region.swift
import Foundation

public struct Region: Codable, Identifiable, Equatable, Sendable, Hashable {
    public let id: String
    public let nameSk: String
    public let latitude: Double
    public let longitude: Double

    public init(id: String, nameSk: String, latitude: Double, longitude: Double) {
        self.id = id
        self.nameSk = nameSk
        self.latitude = latitude
        self.longitude = longitude
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore`
Expected: PASS (2 tests)

- [ ] **Step 6: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalCore
git commit -m "feat: add Species and Region models"
```

---

### Task 2: Region database (8 Slovak kraje)

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Data/RegionDatabase.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/RegionDatabaseTests.swift`

**Interfaces:**
- Consumes: `Region` (Task 1)
- Produces: `RegionDatabase.all: [Region]`, `RegionDatabase.find(id: String) -> Region?`

- [ ] **Step 1: Write the failing test**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/RegionDatabaseTests.swift
import XCTest
@testable import MushroomSignalCore

final class RegionDatabaseTests: XCTestCase {
    func testContainsAllEightKraje() {
        XCTAssertEqual(RegionDatabase.all.count, 8)
    }

    func testAllIdsAreUnique() {
        let ids = Set(RegionDatabase.all.map(\.id))
        XCTAssertEqual(ids.count, RegionDatabase.all.count)
    }

    func testFindReturnsCorrectRegion() {
        let region = RegionDatabase.find(id: "zilinsky")
        XCTAssertEqual(region?.nameSk, "Žilinský kraj")
    }

    func testFindReturnsNilForUnknownId() {
        XCTAssertNil(RegionDatabase.find(id: "does-not-exist"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter RegionDatabaseTests`
Expected: FAIL to compile — `RegionDatabase` does not exist.

- [ ] **Step 3: Implement**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Data/RegionDatabase.swift
import Foundation

public enum RegionDatabase {
    public static let all: [Region] = [
        Region(id: "bratislavsky", nameSk: "Bratislavský kraj", latitude: 48.1486, longitude: 17.1077),
        Region(id: "trnavsky", nameSk: "Trnavský kraj", latitude: 48.3709, longitude: 17.5886),
        Region(id: "trenciansky", nameSk: "Trenčiansky kraj", latitude: 48.8945, longitude: 18.0444),
        Region(id: "nitriansky", nameSk: "Nitriansky kraj", latitude: 48.3081, longitude: 18.0873),
        Region(id: "zilinsky", nameSk: "Žilinský kraj", latitude: 49.2231, longitude: 18.7394),
        Region(id: "banskobystricky", nameSk: "Banskobystrický kraj", latitude: 48.7395, longitude: 19.1535),
        Region(id: "presovsky", nameSk: "Prešovský kraj", latitude: 49.0018, longitude: 21.2393),
        Region(id: "kosicky", nameSk: "Košický kraj", latitude: 48.7164, longitude: 21.2611)
    ]

    public static func find(id: String) -> Region? {
        all.first { $0.id == id }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter RegionDatabaseTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalCore
git commit -m "feat: add 8-kraj region database"
```

---

### Task 3: Full species dataset + loader

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Data/SpeciesDatabase.swift`
- Modify: `MushroomSignalCore/Package.swift` — add `resources: [.process("Data/species.json")]` to the `MushroomSignalCore` target
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesDataTests.swift`

**Interfaces:**
- Consumes: `Species`, `RegionDatabase` (Tasks 1-2)
- Produces: `SpeciesDatabase.loadAll() throws -> [Species]`, `SpeciesDatabaseError.resourceNotFound`

- [ ] **Step 1: Write the failing test**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesDataTests.swift
import XCTest
@testable import MushroomSignalCore

final class SpeciesDataTests: XCTestCase {
    func testLoadsAtLeastTwentyFiveSpecies() throws {
        let species = try SpeciesDatabase.loadAll()
        XCTAssertGreaterThanOrEqual(species.count, 25)
    }

    func testAllIdsAreUnique() throws {
        let species = try SpeciesDatabase.loadAll()
        let ids = Set(species.map(\.id))
        XCTAssertEqual(ids.count, species.count)
    }

    func testAllLookAlikeReferencesResolve() throws {
        let species = try SpeciesDatabase.loadAll()
        let ids = Set(species.map(\.id))
        for s in species {
            for lookAlikeId in s.lookAlikes {
                XCTAssertTrue(ids.contains(lookAlikeId), "\(s.id) references unknown look-alike \(lookAlikeId)")
            }
        }
    }

    func testAllRegionalAffinityReferencesAreKnownRegions() throws {
        let species = try SpeciesDatabase.loadAll()
        let regionIds = Set(RegionDatabase.all.map(\.id))
        for s in species {
            for regionId in s.regionalAffinity {
                XCTAssertTrue(regionIds.contains(regionId), "\(s.id) references unknown region \(regionId)")
            }
        }
    }

    func testFruitingMonthsAreValidCalendarMonths() throws {
        let species = try SpeciesDatabase.loadAll()
        for s in species {
            for month in s.fruitingMonths {
                XCTAssertTrue((1...12).contains(month), "\(s.id) has invalid month \(month)")
            }
        }
    }

    func testContainsAtLeastOnePoisonousEntryForSafetyTesting() throws {
        let species = try SpeciesDatabase.loadAll()
        XCTAssertTrue(species.contains { $0.edibility == .poisonous })
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter SpeciesDataTests`
Expected: FAIL to compile — `SpeciesDatabase` does not exist.

- [ ] **Step 3: Add the resource declaration to Package.swift**

Modify the `.target(name: "MushroomSignalCore")` line to:

```swift
.target(
    name: "MushroomSignalCore",
    resources: [.process("Data/species.json")]
),
```

- [ ] **Step 4: Create the species dataset**

27 species compiled from general mycological knowledge — common Slovak forest/meadow species plus safety-relevant poisonous/caution lookalikes (Amanita phalloides for young Agaricus, Gyromitra esculenta for spring Morchella).

```json
[
  {
    "id": "boletus-edulis",
    "commonNameSk": "Hríb smrekový",
    "latinName": "Boletus edulis",
    "edibility": "edible",
    "lookAlikes": ["tylopilus-felleus"],
    "fruitingMonths": [6, 7, 8, 9, 10],
    "idealTempMinC": 12,
    "idealTempMaxC": 22,
    "rainfallSensitivity": "high",
    "habitat": "smrekové, borovicové a bukové lesy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "boletus-aereus",
    "commonNameSk": "Hríb bronzový",
    "latinName": "Boletus aereus",
    "edibility": "edible",
    "lookAlikes": ["tylopilus-felleus"],
    "fruitingMonths": [6, 7, 8, 9],
    "idealTempMinC": 16,
    "idealTempMaxC": 26,
    "rainfallSensitivity": "medium",
    "habitat": "teplomilné dubové lesy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "nitriansky"]
  },
  {
    "id": "boletus-reticulatus",
    "commonNameSk": "Hríb dubový (letný)",
    "latinName": "Boletus reticulatus",
    "edibility": "edible",
    "lookAlikes": ["tylopilus-felleus"],
    "fruitingMonths": [5, 6, 7, 8, 9],
    "idealTempMinC": 15,
    "idealTempMaxC": 25,
    "rainfallSensitivity": "medium",
    "habitat": "dubové a bukové lesy, teplejšie polohy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "nitriansky", "trenciansky", "banskobystricky"]
  },
  {
    "id": "tylopilus-felleus",
    "commonNameSk": "Horkuľa žlčová",
    "latinName": "Tylopilus felleus",
    "edibility": "caution",
    "lookAlikes": [],
    "fruitingMonths": [6, 7, 8, 9, 10],
    "idealTempMinC": 12,
    "idealTempMaxC": 22,
    "rainfallSensitivity": "medium",
    "habitat": "ihličnaté a zmiešané lesy, často pri koreňoch",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "leccinum-scabrum",
    "commonNameSk": "Kozák brezový",
    "latinName": "Leccinum scabrum",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [6, 7, 8, 9, 10],
    "idealTempMinC": 10,
    "idealTempMaxC": 20,
    "rainfallSensitivity": "medium",
    "habitat": "brezové lesy a porasty",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "leccinum-duriusculum",
    "commonNameSk": "Kozák topoľový",
    "latinName": "Leccinum duriusculum",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [7, 8, 9, 10],
    "idealTempMinC": 12,
    "idealTempMaxC": 22,
    "rainfallSensitivity": "medium",
    "habitat": "topoľové aleje a lesy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "cantharellus-cibarius",
    "commonNameSk": "Kuriatka (líška obyčajná)",
    "latinName": "Cantharellus cibarius",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [6, 7, 8, 9, 10],
    "idealTempMinC": 12,
    "idealTempMaxC": 20,
    "rainfallSensitivity": "high",
    "habitat": "listnaté a zmiešané lesy, medzi machom",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "craterellus-tubaeformis",
    "commonNameSk": "Kuriatko trúbkovité",
    "latinName": "Craterellus tubaeformis",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [8, 9, 10, 11],
    "idealTempMinC": 8,
    "idealTempMaxC": 16,
    "rainfallSensitivity": "high",
    "habitat": "mach v ihličnatých lesoch",
    "regionalAffinity": ["zilinsky", "presovsky", "banskobystricky", "trenciansky", "kosicky"]
  },
  {
    "id": "craterellus-cornucopioides",
    "commonNameSk": "Trúbovka čierna",
    "latinName": "Craterellus cornucopioides",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [8, 9, 10, 11],
    "idealTempMinC": 10,
    "idealTempMaxC": 18,
    "rainfallSensitivity": "high",
    "habitat": "bukové lesy, medzi machom",
    "regionalAffinity": ["zilinsky", "presovsky", "banskobystricky", "trenciansky"]
  },
  {
    "id": "macrolepiota-procera",
    "commonNameSk": "Bedľa vysoká",
    "latinName": "Macrolepiota procera",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [7, 8, 9, 10],
    "idealTempMinC": 12,
    "idealTempMaxC": 22,
    "rainfallSensitivity": "medium",
    "habitat": "lúky, okraje lesov, pasienky",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "lactarius-deliciosus",
    "commonNameSk": "Rýdzik pravý",
    "latinName": "Lactarius deliciosus",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [8, 9, 10, 11],
    "idealTempMinC": 8,
    "idealTempMaxC": 18,
    "rainfallSensitivity": "medium",
    "habitat": "borovicové lesy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "pleurotus-ostreatus",
    "commonNameSk": "Hliva ustricovitá",
    "latinName": "Pleurotus ostreatus",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [3, 4, 9, 10, 11, 12],
    "idealTempMinC": 2,
    "idealTempMaxC": 15,
    "rainfallSensitivity": "low",
    "habitat": "odumreté a oslabené listnaté stromy, najmä buk a topoľ",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "amanita-muscaria",
    "commonNameSk": "Muchotrávka červená",
    "latinName": "Amanita muscaria",
    "edibility": "poisonous",
    "lookAlikes": [],
    "fruitingMonths": [7, 8, 9, 10, 11],
    "idealTempMinC": 8,
    "idealTempMaxC": 18,
    "rainfallSensitivity": "medium",
    "habitat": "brezové a smrekové lesy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "amanita-phalloides",
    "commonNameSk": "Muchotrávka zelená",
    "latinName": "Amanita phalloides",
    "edibility": "poisonous",
    "lookAlikes": [],
    "fruitingMonths": [7, 8, 9, 10],
    "idealTempMinC": 12,
    "idealTempMaxC": 22,
    "rainfallSensitivity": "medium",
    "habitat": "listnaté lesy, najmä dub a buk",
    "regionalAffinity": ["bratislavsky", "trnavsky", "nitriansky", "trenciansky", "banskobystricky", "kosicky"]
  },
  {
    "id": "russula-vesca",
    "commonNameSk": "Plávka fúzatá",
    "latinName": "Russula vesca",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [6, 7, 8, 9, 10],
    "idealTempMinC": 12,
    "idealTempMaxC": 22,
    "rainfallSensitivity": "medium",
    "habitat": "listnaté a zmiešané lesy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "agaricus-campestris",
    "commonNameSk": "Pečiarka poľná",
    "latinName": "Agaricus campestris",
    "edibility": "edible",
    "lookAlikes": ["amanita-phalloides"],
    "fruitingMonths": [6, 7, 8, 9, 10],
    "idealTempMinC": 10,
    "idealTempMaxC": 20,
    "rainfallSensitivity": "medium",
    "habitat": "lúky, pasienky",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "coprinus-comatus",
    "commonNameSk": "Hnojník obyčajný",
    "latinName": "Coprinus comatus",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [5, 6, 7, 8, 9, 10, 11],
    "idealTempMinC": 8,
    "idealTempMaxC": 20,
    "rainfallSensitivity": "medium",
    "habitat": "lúky, okraje ciest, narušená pôda",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "hydnum-repandum",
    "commonNameSk": "Ježovka žltkastá",
    "latinName": "Hydnum repandum",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [7, 8, 9, 10, 11],
    "idealTempMinC": 10,
    "idealTempMaxC": 20,
    "rainfallSensitivity": "medium",
    "habitat": "zmiešané a ihličnaté lesy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "fistulina-hepatica",
    "commonNameSk": "Pečeňovka obyčajná",
    "latinName": "Fistulina hepatica",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [8, 9, 10, 11],
    "idealTempMinC": 12,
    "idealTempMaxC": 22,
    "rainfallSensitivity": "medium",
    "habitat": "staré duby a gaštany",
    "regionalAffinity": ["bratislavsky", "trnavsky", "nitriansky", "trenciansky"]
  },
  {
    "id": "laetiporus-sulphureus",
    "commonNameSk": "Trúdnik sírový",
    "latinName": "Laetiporus sulphureus",
    "edibility": "caution",
    "lookAlikes": [],
    "fruitingMonths": [5, 6, 7, 8, 9],
    "idealTempMinC": 12,
    "idealTempMaxC": 24,
    "rainfallSensitivity": "low",
    "habitat": "staré listnaté stromy, najmä dub a vŕba",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "suillus-luteus",
    "commonNameSk": "Masliak obyčajný",
    "latinName": "Suillus luteus",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [7, 8, 9, 10, 11],
    "idealTempMinC": 10,
    "idealTempMaxC": 20,
    "rainfallSensitivity": "medium",
    "habitat": "borovicové lesy a výsadby",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "tricholoma-terreum",
    "commonNameSk": "Čírovník sivý",
    "latinName": "Tricholoma terreum",
    "edibility": "caution",
    "lookAlikes": [],
    "fruitingMonths": [9, 10, 11],
    "idealTempMinC": 5,
    "idealTempMaxC": 15,
    "rainfallSensitivity": "medium",
    "habitat": "borovicové lesy, piesočnaté pôdy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "armillaria-mellea",
    "commonNameSk": "Podpňovka obyčajná (václavka)",
    "latinName": "Armillaria mellea",
    "edibility": "caution",
    "lookAlikes": [],
    "fruitingMonths": [9, 10, 11],
    "idealTempMinC": 8,
    "idealTempMaxC": 18,
    "rainfallSensitivity": "high",
    "habitat": "pne a korene listnatých aj ihličnatých stromov",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "xerocomus-badius",
    "commonNameSk": "Suchohríb hnedý",
    "latinName": "Xerocomus badius",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [6, 7, 8, 9, 10, 11],
    "idealTempMinC": 10,
    "idealTempMaxC": 22,
    "rainfallSensitivity": "medium",
    "habitat": "ihličnaté a zmiešané lesy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "calocybe-gambosa",
    "commonNameSk": "Penízovka hľuznatá (májovka)",
    "latinName": "Calocybe gambosa",
    "edibility": "edible",
    "lookAlikes": [],
    "fruitingMonths": [4, 5, 6],
    "idealTempMinC": 8,
    "idealTempMaxC": 18,
    "rainfallSensitivity": "medium",
    "habitat": "lúky, okraje lesov, hlohové kroviny",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "morchella-esculenta",
    "commonNameSk": "Smrčok jedlý",
    "latinName": "Morchella esculenta",
    "edibility": "edible",
    "lookAlikes": ["gyromitra-esculenta"],
    "fruitingMonths": [4, 5],
    "idealTempMinC": 8,
    "idealTempMaxC": 16,
    "rainfallSensitivity": "medium",
    "habitat": "lužné lesy, staré sady, spálené miesta",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  },
  {
    "id": "gyromitra-esculenta",
    "commonNameSk": "Ušiak obyčajný",
    "latinName": "Gyromitra esculenta",
    "edibility": "poisonous",
    "lookAlikes": ["morchella-esculenta"],
    "fruitingMonths": [3, 4, 5],
    "idealTempMinC": 3,
    "idealTempMaxC": 12,
    "rainfallSensitivity": "low",
    "habitat": "ihličnaté lesy, piesočnaté pôdy",
    "regionalAffinity": ["bratislavsky", "trnavsky", "trenciansky", "nitriansky", "zilinsky", "banskobystricky", "presovsky", "kosicky"]
  }
]
```

Save this as `MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json`.

- [ ] **Step 5: Implement the loader**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Data/SpeciesDatabase.swift
import Foundation

public enum SpeciesDatabaseError: Error, Equatable {
    case resourceNotFound
}

public enum SpeciesDatabase {
    public static func loadAll() throws -> [Species] {
        guard let url = Bundle.module.url(forResource: "species", withExtension: "json") else {
            throw SpeciesDatabaseError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([Species].self, from: data)
    }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter SpeciesDataTests`
Expected: PASS (6 tests)

- [ ] **Step 7: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalCore
git commit -m "feat: add 27-species dataset and loader"
```

---

### Task 4: Weather integration (Open-Meteo)

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift`

**Interfaces:**
- Consumes: `Region` (Task 1)
- Produces: `WeatherSnapshot` struct, `WeatherClient` protocol with `fetchSnapshot(for region: Region) async throws -> WeatherSnapshot`, `OpenMeteoClient: WeatherClient`, `WeatherClientError.invalidResponse`/`.emptyDailyData`

- [ ] **Step 1: Write the failing tests (with a mocked URLProtocol, no live network calls)**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/OpenMeteoClientTests.swift
import XCTest
@testable import MushroomSignalCore

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class OpenMeteoClientTests: XCTestCase {
    private func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let region = Region(id: "zilinsky", nameSk: "Žilinský kraj", latitude: 49.2231, longitude: 18.7394)

    func testFetchSnapshotParsesAverageTempAndTotalPrecipitation() async throws {
        let json = """
        { "daily": { "temperature_2m_mean": [10.0, 12.0, 14.0], "precipitation_sum": [0.0, 5.0, 3.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let snapshot = try await client.fetchSnapshot(for: region)

        XCTAssertEqual(snapshot.averageTempLast10DaysC, 12.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalPrecipitationLast10DaysMm, 8.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.regionId, "zilinsky")
    }

    func testFetchSnapshotIgnoresNullDailyValues() async throws {
        let json = """
        { "daily": { "temperature_2m_mean": [10.0, null, 14.0], "precipitation_sum": [null, 5.0, 3.0] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())
        let snapshot = try await client.fetchSnapshot(for: region)

        XCTAssertEqual(snapshot.averageTempLast10DaysC, 12.0, accuracy: 0.001)
        XCTAssertEqual(snapshot.totalPrecipitationLast10DaysMm, 8.0, accuracy: 0.001)
    }

    func testFetchSnapshotThrowsOnNonOKStatus() async throws {
        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
        }

        let client = OpenMeteoClient(session: makeMockedSession())

        do {
            _ = try await client.fetchSnapshot(for: region)
            XCTFail("Expected invalidResponse error")
        } catch WeatherClientError.invalidResponse {
            // expected
        }
    }

    func testFetchSnapshotThrowsOnEmptyDailyData() async throws {
        let json = """
        { "daily": { "temperature_2m_mean": [], "precipitation_sum": [] } }
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, json)
        }

        let client = OpenMeteoClient(session: makeMockedSession())

        do {
            _ = try await client.fetchSnapshot(for: region)
            XCTFail("Expected emptyDailyData error")
        } catch WeatherClientError.emptyDailyData {
            // expected
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter OpenMeteoClientTests`
Expected: FAIL to compile — types don't exist yet.

- [ ] **Step 3: Implement**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherSnapshot.swift
import Foundation

public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public let regionId: String
    public let averageTempLast10DaysC: Double
    public let totalPrecipitationLast10DaysMm: Double
    public let fetchedAt: Date

    public init(regionId: String, averageTempLast10DaysC: Double, totalPrecipitationLast10DaysMm: Double, fetchedAt: Date) {
        self.regionId = regionId
        self.averageTempLast10DaysC = averageTempLast10DaysC
        self.totalPrecipitationLast10DaysMm = totalPrecipitationLast10DaysMm
        self.fetchedAt = fetchedAt
    }
}
```

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Weather/WeatherClient.swift
import Foundation

public protocol WeatherClient: Sendable {
    func fetchSnapshot(for region: Region) async throws -> WeatherSnapshot
}
```

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Weather/OpenMeteoClient.swift
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
            URLQueryItem(name: "daily", value: "temperature_2m_mean,precipitation_sum"),
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
        let precipitation = decoded.daily.precipitationSum.compactMap { $0 }
        guard !temps.isEmpty, !precipitation.isEmpty else {
            throw WeatherClientError.emptyDailyData
        }

        let averageTemp = temps.reduce(0, +) / Double(temps.count)
        let totalPrecipitation = precipitation.reduce(0, +)

        return WeatherSnapshot(
            regionId: region.id,
            averageTempLast10DaysC: averageTemp,
            totalPrecipitationLast10DaysMm: totalPrecipitation,
            fetchedAt: Date()
        )
    }
}

struct OpenMeteoResponse: Codable {
    struct Daily: Codable {
        let temperature2mMean: [Double?]
        let precipitationSum: [Double?]

        enum CodingKeys: String, CodingKey {
            case temperature2mMean = "temperature_2m_mean"
            case precipitationSum = "precipitation_sum"
        }
    }
    let daily: Daily
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter OpenMeteoClientTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalCore
git commit -m "feat: add Open-Meteo weather client"
```

---

### Task 5: Signal algorithm

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SpeciesSignal.swift`
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift`

**Interfaces:**
- Consumes: `Species`, `WeatherSnapshot` (Tasks 1, 4)
- Produces: `SpeciesSignal` struct (`species`, `score: Int` 0-3, `reason: String?`), `SignalAlgorithm.computeSignal(species:weather:month:) -> SpeciesSignal`

Scoring design: calendar fit gates everything — if the current month isn't in or adjacent to the species' fruiting months, score is 0 regardless of weather (a species genuinely isn't fruiting out of season no matter how good conditions look). Inside season, temperature and rainfall fit each contribute up to 1 point on top of a calendar-based base, capped at 3. Shoulder-season months cap at 2 even with perfect weather, since it's not truly peak season yet.

- [ ] **Step 1: Write the failing tests**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/SignalAlgorithmTests.swift
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
        rainfallSensitivity: .high,
        habitat: "smrekové lesy",
        regionalAffinity: ["zilinsky"]
    )

    func testPeakSeasonWithGoodTempAndRainScoresThree() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8)

        XCTAssertEqual(signal.score, 3)
        XCTAssertNil(signal.reason)
    }

    func testOffSeasonScoresZeroRegardlessOfWeather() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        // January: not in fruitingMonths, not adjacent to them either.
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 1)

        XCTAssertEqual(signal.score, 0)
        XCTAssertEqual(signal.reason, "mimo hlavnej sezóny")
    }

    func testDrySpellPenalizesHighRainfallSensitivitySpecies() {
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 17, totalPrecipitationLast10DaysMm: 1, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 8)

        XCTAssertEqual(signal.score, 2)
        XCTAssertEqual(signal.reason, "málo zrážok v poslednej dobe")
    }

    func testShoulderMonthCapsScoreEvenWithGoodWeather() {
        // 24°C is 2°C above idealTempMaxC (22) — within the 3°C tolerance band, so partial temp credit.
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 24, totalPrecipitationLast10DaysMm: 25, fetchedAt: Date())

        // Month 11 is adjacent to fruitingMonths' last month (10) but not itself in season.
        let signal = SignalAlgorithm.computeSignal(species: sampleSpecies, weather: weather, month: 11)

        XCTAssertEqual(signal.score, 2)
        XCTAssertEqual(signal.reason, "teplota mimo ideálneho rozsahu")
    }

    func testLowRainfallSensitivitySpeciesIsNotPenalizedByDrySpell() {
        let lowSensitivitySpecies = Species(
            id: "pleurotus-ostreatus",
            commonNameSk: "Hliva ustricovitá",
            latinName: "Pleurotus ostreatus",
            edibility: .edible,
            lookAlikes: [],
            fruitingMonths: [9, 10, 11],
            idealTempMinC: 2,
            idealTempMaxC: 15,
            rainfallSensitivity: .low,
            habitat: "odumreté stromy",
            regionalAffinity: ["zilinsky"]
        )
        let weather = WeatherSnapshot(regionId: "zilinsky", averageTempLast10DaysC: 10, totalPrecipitationLast10DaysMm: 0, fetchedAt: Date())

        let signal = SignalAlgorithm.computeSignal(species: lowSensitivitySpecies, weather: weather, month: 10)

        XCTAssertEqual(signal.score, 3)
        XCTAssertNil(signal.reason)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter SignalAlgorithmTests`
Expected: FAIL to compile — types don't exist yet.

- [ ] **Step 3: Implement**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Signal/SpeciesSignal.swift
import Foundation

public struct SpeciesSignal: Equatable, Sendable {
    public let species: Species
    public let score: Int
    public let reason: String?

    public init(species: Species, score: Int, reason: String?) {
        self.species = species
        self.score = score
        self.reason = reason
    }
}
```

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Signal/SignalAlgorithm.swift
import Foundation

public enum SignalAlgorithm {
    public static func computeSignal(species: Species, weather: WeatherSnapshot, month: Int) -> SpeciesSignal {
        let calendarScore = calendarFit(species: species, month: month)

        guard calendarScore > 0 else {
            return SpeciesSignal(species: species, score: 0, reason: "mimo hlavnej sezóny")
        }

        let tempScore = temperatureFit(species: species, weather: weather)
        let rainScore = rainfallFit(species: species, weather: weather)
        let weatherScore = tempScore + rainScore

        let total = calendarScore == 1.0 ? 1.0 + weatherScore : weatherScore
        let score = Int(total.rounded())

        let reason = reasonText(species: species, tempScore: tempScore, rainScore: rainScore)

        return SpeciesSignal(species: species, score: min(3, max(0, score)), reason: reason)
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

    static func rainfallFit(species: Species, weather: WeatherSnapshot) -> Double {
        let precipitation = weather.totalPrecipitationLast10DaysMm
        switch species.rainfallSensitivity {
        case .high:
            if precipitation >= 20 { return 1.0 }
            if precipitation >= 8 { return 0.5 }
            return 0.0
        case .medium:
            if precipitation >= 10 { return 1.0 }
            if precipitation >= 3 { return 0.5 }
            return 0.0
        case .low:
            // Always full credit: drought-tolerant species must be genuinely
            // rain-invariant, not just usually so (fixed post-review — see ledger).
            return 1.0
        }
    }

    static func reasonText(species: Species, tempScore: Double, rainScore: Double) -> String? {
        if rainScore < 1.0 && species.rainfallSensitivity != .low {
            return "málo zrážok v poslednej dobe"
        }
        if tempScore < 1.0 {
            return "teplota mimo ideálneho rozsahu"
        }
        return nil
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter SignalAlgorithmTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalCore
git commit -m "feat: add mushroom signal scoring algorithm"
```

---

### Task 6: Shortlist ranking

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Signal/ShortlistRanker.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift`

**Interfaces:**
- Consumes: `SpeciesSignal` (Task 5)
- Produces: `ShortlistRanker.topSpecies(from: [SpeciesSignal], limit: Int) -> [SpeciesSignal]`

- [ ] **Step 1: Write the failing tests**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/ShortlistRankerTests.swift
import XCTest
@testable import MushroomSignalCore

final class ShortlistRankerTests: XCTestCase {
    private func makeSpecies(id: String, name: String, edibility: Edibility) -> Species {
        Species(
            id: id,
            commonNameSk: name,
            latinName: name,
            edibility: edibility,
            lookAlikes: [],
            fruitingMonths: [8],
            idealTempMinC: 10,
            idealTempMaxC: 20,
            rainfallSensitivity: .medium,
            habitat: "test",
            regionalAffinity: ["zilinsky"]
        )
    }

    func testReturnsTopNSortedByScoreDescending() {
        let signals = [
            SpeciesSignal(species: makeSpecies(id: "a", name: "A", edibility: .edible), score: 1, reason: nil),
            SpeciesSignal(species: makeSpecies(id: "b", name: "B", edibility: .edible), score: 3, reason: nil),
            SpeciesSignal(species: makeSpecies(id: "c", name: "C", edibility: .edible), score: 2, reason: nil)
        ]

        let top = ShortlistRanker.topSpecies(from: signals, limit: 3)

        XCTAssertEqual(top.map { $0.species.id }, ["b", "c", "a"])
    }

    func testLimitsResultCount() {
        let signals = (0..<5).map {
            SpeciesSignal(species: makeSpecies(id: "s\($0)", name: "S\($0)", edibility: .edible), score: $0, reason: nil)
        }

        let top = ShortlistRanker.topSpecies(from: signals, limit: 3)

        XCTAssertEqual(top.count, 3)
    }

    func testTiesBreakByEdibilityThenName() {
        let signals = [
            SpeciesSignal(species: makeSpecies(id: "poison", name: "Z Poison", edibility: .poisonous), score: 2, reason: nil),
            SpeciesSignal(species: makeSpecies(id: "edible", name: "A Edible", edibility: .edible), score: 2, reason: nil)
        ]

        let top = ShortlistRanker.topSpecies(from: signals, limit: 2)

        XCTAssertEqual(top.first?.species.id, "edible")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter ShortlistRankerTests`
Expected: FAIL to compile — `ShortlistRanker` does not exist.

- [ ] **Step 3: Implement**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Signal/ShortlistRanker.swift
import Foundation

public enum ShortlistRanker {
    public static func topSpecies(from signals: [SpeciesSignal], limit: Int) -> [SpeciesSignal] {
        guard limit > 0 else { return [] }
        return signals
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.species.edibility != rhs.species.edibility {
                    return edibilityRank(lhs.species.edibility) < edibilityRank(rhs.species.edibility)
                }
                return lhs.species.commonNameSk < rhs.species.commonNameSk
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func edibilityRank(_ edibility: Edibility) -> Int {
        switch edibility {
        case .edible: return 0
        case .caution: return 1
        case .poisonous: return 2
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter ShortlistRankerTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalCore
git commit -m "feat: add shortlist ranking"
```

---

### Task 7: Design system (nature palette + golden-ratio spacing)

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift`

**Interfaces:**
- Produces: `DesignSystem.goldenRatio`, `.spacingSmall/.spacingMedium/.spacingLarge/.spacingExtraLarge`, `.cardCornerRadius`, `DesignSystem.Colors.forestDeep/.forestMid/.bark/.water/.cloud/.mossAccent/.cardBackground`

- [ ] **Step 1: Write the failing tests**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/DesignSystemTests.swift
import XCTest
@testable import MushroomSignalCore

final class DesignSystemTests: XCTestCase {
    func testSpacingScaleIsIncreasing() {
        XCTAssertLessThan(DesignSystem.spacingSmall, DesignSystem.spacingMedium)
        XCTAssertLessThan(DesignSystem.spacingMedium, DesignSystem.spacingLarge)
        XCTAssertLessThan(DesignSystem.spacingLarge, DesignSystem.spacingExtraLarge)
    }

    func testSpacingRatiosApproximateGoldenRatio() {
        let ratio1 = DesignSystem.spacingMedium / DesignSystem.spacingSmall
        let ratio2 = DesignSystem.spacingLarge / DesignSystem.spacingMedium
        XCTAssertEqual(ratio1, DesignSystem.goldenRatio, accuracy: 0.001)
        XCTAssertEqual(ratio2, DesignSystem.goldenRatio, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter DesignSystemTests`
Expected: FAIL to compile — `DesignSystem` does not exist.

- [ ] **Step 3: Implement**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift
import SwiftUI

public enum DesignSystem {
    public static let goldenRatio: Double = 1.618

    private static let spacingUnit: Double = 8
    public static let spacingSmall: Double = spacingUnit
    public static let spacingMedium: Double = spacingSmall * goldenRatio
    public static let spacingLarge: Double = spacingMedium * goldenRatio
    public static let spacingExtraLarge: Double = spacingLarge * goldenRatio

    public static let cardCornerRadius: Double = 24

    public enum Colors {
        public static let forestDeep = Color(red: 0.11, green: 0.16, blue: 0.11)
        public static let forestMid = Color(red: 0.18, green: 0.25, blue: 0.16)
        public static let bark = Color(red: 0.29, green: 0.20, blue: 0.13)
        public static let water = Color(red: 0.30, green: 0.48, blue: 0.52)
        public static let cloud = Color(red: 0.94, green: 0.92, blue: 0.87)
        public static let mossAccent = Color(red: 0.42, green: 0.56, blue: 0.30)
        // Added post-review (Task 13): views needed a warning/error color that
        // isn't raw system red, for the poisonous-species badge and error text.
        public static let danger = Color(red: 0.72, green: 0.24, blue: 0.20)

        public static let cardBackground = LinearGradient(
            colors: [forestMid, forestDeep],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter DesignSystemTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalCore
git commit -m "feat: add forest-themed design system with golden-ratio spacing"
```

---

### Task 8: Shared region store (App Group-backed)

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Storage/RegionStore.swift`
- Test: `MushroomSignalCore/Tests/MushroomSignalCoreTests/RegionStoreTests.swift`

**Interfaces:**
- Consumes: `Region`, `RegionDatabase` (Tasks 1-2)
- Produces: `RegionStoreConstants.appGroupId/.selectedRegionKey/.defaultRegionId`, `RegionStore` with `init?(appGroupId:)`, `selectedRegion() -> Region`, `setSelectedRegion(_:)`

This is the mechanism the widget and the app use to agree on which region is selected — both read/write the same `UserDefaults(suiteName:)` backed by the App Group configured in Task 9's entitlements. `UserDefaults(suiteName:)` works standalone in `swift test` too (it just uses a locally-named plist), so this is fully testable now.

- [ ] **Step 1: Write the failing tests**

```swift
// MushroomSignalCore/Tests/MushroomSignalCoreTests/RegionStoreTests.swift
import XCTest
@testable import MushroomSignalCore

final class RegionStoreTests: XCTestCase {
    func testDefaultsToZilinskyWhenNothingStored() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let store = RegionStore(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(store.selectedRegion().id, "zilinsky")
    }

    func testPersistsSelectedRegion() {
        let suiteName = "test.suite.\(UUID().uuidString)"
        let store = RegionStore(appGroupId: suiteName)!
        defer { UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName) }

        let kosice = RegionDatabase.find(id: "kosicky")!
        store.setSelectedRegion(kosice)

        XCTAssertEqual(store.selectedRegion().id, "kosicky")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter RegionStoreTests`
Expected: FAIL to compile — `RegionStore` does not exist.

- [ ] **Step 3: Implement**

```swift
// MushroomSignalCore/Sources/MushroomSignalCore/Storage/RegionStore.swift
import Foundation

public enum RegionStoreConstants {
    public static let appGroupId = "group.com.alexandersalinka.MushroomSignal"
    public static let selectedRegionKey = "selectedRegionId"
    public static let defaultRegionId = "zilinsky"
}

public struct RegionStore {
    private let defaults: UserDefaults

    public init?(appGroupId: String = RegionStoreConstants.appGroupId) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return nil }
        self.defaults = defaults
    }

    public func selectedRegion() -> Region {
        let id = defaults.string(forKey: RegionStoreConstants.selectedRegionKey) ?? RegionStoreConstants.defaultRegionId
        // Falls back through the declared default before the [0] safety net, so a
        // stale/unrecognized stored id resolves to Žilinský, not Bratislavský.
        return RegionDatabase.find(id: id) ?? RegionDatabase.find(id: RegionStoreConstants.defaultRegionId) ?? RegionDatabase.all[0]
    }

    public func setSelectedRegion(_ region: Region) {
        defaults.set(region.id, forKey: RegionStoreConstants.selectedRegionKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore --filter RegionStoreTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Run the full Phase A test suite**

Run: `swift test --package-path ~/Coding/mushroom-signal/MushroomSignalCore`
Expected: PASS — all tests across all 8 tasks (roughly 24 tests total)

- [ ] **Step 6: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalCore
git commit -m "feat: add App Group-backed region store"
```

---

## Phase B — Xcode app + widget (requires full Xcode.app, not just Command Line Tools)

**Before starting Phase B:** confirm Xcode is fully installed:

```bash
xcode-select -p
```

If this prints `/Library/Developer/CommandLineTools` instead of a path inside `/Applications/Xcode.app`, Xcode isn't ready yet — wait for the App Store install to finish, then run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -version
```

Do not proceed with Task 9 until `xcodebuild -version` succeeds.

### Task 9: XcodeGen project scaffold

**Files:**
- Create: `project.yml`
- Create: `.gitignore` additions for Xcode artifacts
- Generates: `MushroomSignal.xcodeproj`, `MushroomSignal/MushroomSignal.entitlements`, `MushroomSignal/Info.plist`, `MushroomSignalWidget/MushroomSignalWidget.entitlements`, `MushroomSignalWidget/Info.plist` (all written by `xcodegen generate`, not hand-authored)

This YAML schema was validated in a throwaway spike before writing this plan (installed xcodegen, generated a project with an app target embedding a widget-extension target, App Group entitlements on both, and a local Swift package dependency — confirmed the entitlements, widget `Info.plist` `NSExtensionPointIdentifier`, and package linkage all landed correctly in the generated `.xcodeproj`).

- [ ] **Step 1: Install XcodeGen if not already present**

```bash
which xcodegen || brew install xcodegen
```

- [ ] **Step 2: Create the source directories XcodeGen will reference**

```bash
mkdir -p ~/Coding/mushroom-signal/MushroomSignal
mkdir -p ~/Coding/mushroom-signal/MushroomSignalWidget
```

- [ ] **Step 3: Write `project.yml`**

```yaml
# project.yml
name: MushroomSignal
options:
  bundleIdPrefix: com.alexandersalinka
  deploymentTarget:
    macOS: "14.0"
packages:
  MushroomSignalCore:
    path: MushroomSignalCore
targets:
  MushroomSignal:
    type: application
    platform: macOS
    sources:
      - path: MushroomSignal
    dependencies:
      - target: MushroomSignalWidgetExtension
        embed: true
      - package: MushroomSignalCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.alexandersalinka.MushroomSignal
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_STYLE: Automatic
    entitlements:
      path: MushroomSignal/MushroomSignal.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.application-groups:
          - group.com.alexandersalinka.MushroomSignal
        com.apple.security.network.client: true
    info:
      path: MushroomSignal/Info.plist
      properties:
        CFBundleDisplayName: Mushroom Signal
        LSMinimumSystemVersion: "14.0"

  MushroomSignalWidgetExtension:
    type: app-extension
    platform: macOS
    sources:
      - path: MushroomSignalWidget
    dependencies:
      - package: MushroomSignalCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.alexandersalinka.MushroomSignal.Widget
        MARKETING_VERSION: "1.0"
        CURRENT_PROJECT_VERSION: "1"
        CODE_SIGN_STYLE: Automatic
    entitlements:
      path: MushroomSignalWidget/MushroomSignalWidget.entitlements
      properties:
        com.apple.security.app-sandbox: true
        com.apple.security.application-groups:
          - group.com.alexandersalinka.MushroomSignal
        com.apple.security.network.client: true
    info:
      path: MushroomSignalWidget/Info.plist
      properties:
        CFBundleDisplayName: Mushroom Signal Widget
        NSExtension:
          NSExtensionPointIdentifier: com.apple.widgetkit-extension
```

- [ ] **Step 4: Generate the Xcode project**

```bash
cd ~/Coding/mushroom-signal
xcodegen generate
```

Expected: `Created project at .../MushroomSignal.xcodeproj`, plus generated entitlements/Info.plist files under `MushroomSignal/` and `MushroomSignalWidget/`.

- [ ] **Step 5: Verify both targets are registered**

Run: `xcodebuild -list -project MushroomSignal.xcodeproj`
Expected: Output lists both `MushroomSignal` and `MushroomSignalWidgetExtension` under Targets.

- [ ] **Step 6: Update `.gitignore`**

Append to the existing `.gitignore`:

```
DerivedData/
.build/
*.xcuserstate
xcuserdata/
```

- [ ] **Step 7: Commit**

```bash
cd ~/Coding/mushroom-signal
git add project.yml .gitignore MushroomSignal.xcodeproj MushroomSignal/*.entitlements MushroomSignal/Info.plist MushroomSignalWidget/*.entitlements MushroomSignalWidget/Info.plist
git commit -m "chore: scaffold Xcode project via XcodeGen (app + widget extension)"
```

---

### Task 10: Widget timeline provider

**Files:**
- Create: `MushroomSignalWidget/MushroomSignalWidgetBundle.swift`
- Create: `MushroomSignalWidget/MushroomSignalWidget.swift`

**Interfaces:**
- Consumes: `RegionStore`, `RegionDatabase`, `SpeciesDatabase`, `OpenMeteoClient`, `SignalAlgorithm`, `ShortlistRanker` (Phase A)
- Produces: `ShortlistEntry: TimelineEntry`, `ShortlistProvider: TimelineProvider`, `MushroomSignalWidget: Widget`

- [ ] **Step 1: Implement the widget bundle entry point**

```swift
// MushroomSignalWidget/MushroomSignalWidgetBundle.swift
import WidgetKit
import SwiftUI

@main
struct MushroomSignalWidgetBundle: WidgetBundle {
    var body: some Widget {
        MushroomSignalWidget()
    }
}
```

- [ ] **Step 2: Implement the timeline provider and widget declaration**

```swift
// MushroomSignalWidget/MushroomSignalWidget.swift
import WidgetKit
import SwiftUI
import MushroomSignalCore

struct ShortlistEntry: TimelineEntry {
    let date: Date
    let region: Region
    let signals: [SpeciesSignal]
}

struct ShortlistProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShortlistEntry {
        ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (ShortlistEntry) -> Void) {
        completion(ShortlistEntry(date: Date(), region: RegionDatabase.all[0], signals: []))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShortlistEntry>) -> Void) {
        Task {
            let entry = await buildEntry()
            let nextRefresh = Calendar.current.date(byAdding: .hour, value: 12, to: Date()) ?? Date().addingTimeInterval(12 * 3600)
            completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
        }
    }

    private func buildEntry() async -> ShortlistEntry {
        let region = RegionStore()?.selectedRegion() ?? RegionDatabase.all[0]

        do {
            let weather = try await OpenMeteoClient().fetchSnapshot(for: region)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let signals = allSpecies
                .filter { $0.regionalAffinity.contains(region.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            let shortlist = ShortlistRanker.topSpecies(from: signals, limit: 3)
            return ShortlistEntry(date: Date(), region: region, signals: shortlist)
        } catch {
            return ShortlistEntry(date: Date(), region: region, signals: [])
        }
    }
}

struct MushroomSignalWidget: Widget {
    let kind: String = "MushroomSignalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShortlistProvider()) { entry in
            ShortlistWidgetView(entry: entry)
        }
        .configurationDisplayName("Mushroom Signal")
        .description("Aktuálne huby vo vašom kraji")
        .supportedFamilies([.systemSmall])
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignalWidgetExtension -configuration Debug build`
Expected: `** BUILD SUCCEEDED **` (this task depends on Task 11's `ShortlistWidgetView` existing too — build both together if the scheme fails on the missing view)

- [ ] **Step 4: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalWidget
git commit -m "feat: add widget timeline provider"
```

---

### Task 11: Widget view (ranked shortlist card)

**Files:**
- Create: `MushroomSignalWidget/ShortlistWidgetView.swift`

**Interfaces:**
- Consumes: `ShortlistEntry`, `DesignSystem` (Task 10, Phase A Task 7)

- [ ] **Step 1: Implement**

```swift
// MushroomSignalWidget/ShortlistWidgetView.swift
import SwiftUI
import WidgetKit
import MushroomSignalCore

struct ShortlistWidgetView: View {
    let entry: ShortlistEntry

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
            Text(entry.region.nameSk)
                .font(.caption2)
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))

            VStack(alignment: .leading, spacing: DesignSystem.spacingSmall) {
                ForEach(entry.signals, id: \.species.id) { signal in
                    HStack {
                        Text(signal.species.commonNameSk)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.cloud)
                            .lineLimit(1)
                        Spacer()
                        Text(String(repeating: "●", count: signal.score) + String(repeating: "○", count: 3 - signal.score))
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.mossAccent)
                    }
                }
                if entry.signals.isEmpty {
                    Text("Žiadne údaje")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                }
            }

            Spacer(minLength: 0)

            Text(entry.date, style: .time)
                .font(.system(size: 8))
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
        }
        .padding(DesignSystem.spacingMedium)
        .containerBackground(for: .widget) {
            DesignSystem.Colors.cardBackground
        }
    }
}

#Preview(as: .systemSmall) {
    MushroomSignalWidget()
} timeline: {
    ShortlistEntry(date: .now, region: RegionDatabase.all[4], signals: [])
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignalWidgetExtension -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Open in Xcode and check the preview**

Open `MushroomSignal.xcodeproj` in Xcode, open `ShortlistWidgetView.swift`, and check the canvas preview renders the small widget card. This is the first real visual verification of the approved mockup design.

- [ ] **Step 4: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignalWidget
git commit -m "feat: implement ranked-shortlist widget view"
```

---

### Task 12: Companion app shell + region picker

**Files:**
- Create: `MushroomSignal/MushroomSignalApp.swift`
- Create: `MushroomSignal/AppState.swift`
- Create: `MushroomSignal/ContentView.swift`
- Create: `MushroomSignal/Views/RegionPickerView.swift`

**Interfaces:**
- Consumes: `RegionStore`, `RegionDatabase`, `SpeciesDatabase`, `OpenMeteoClient`, `WeatherClient`, `SignalAlgorithm`, `ShortlistRanker`, `DesignSystem` (Phase A)
- Produces: `AppState` (`@MainActor ObservableObject` with `selectedRegion`, `signals`, `isLoading`, `errorMessage`, `selectRegion(_:)`, `refresh() async`), `ContentView`, `RegionPickerView`

- [ ] **Step 1: Implement the app entry point**

```swift
// MushroomSignal/MushroomSignalApp.swift
import SwiftUI

@main
struct MushroomSignalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
```

- [ ] **Step 2: Implement app state**

```swift
// MushroomSignal/AppState.swift
import Foundation
import MushroomSignalCore

@MainActor
final class AppState: ObservableObject {
    @Published var selectedRegion: Region
    @Published var signals: [SpeciesSignal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let store: RegionStore?
    private let weatherClient: WeatherClient

    init(store: RegionStore? = RegionStore(), weatherClient: WeatherClient = OpenMeteoClient()) {
        self.store = store
        self.weatherClient = weatherClient
        self.selectedRegion = store?.selectedRegion() ?? RegionDatabase.all[0]
    }

    func selectRegion(_ region: Region) {
        selectedRegion = region
        store?.setSelectedRegion(region)
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let weather = try await weatherClient.fetchSnapshot(for: selectedRegion)
            let allSpecies = try SpeciesDatabase.loadAll()
            let month = Calendar.current.component(.month, from: Date())
            let allSignals = allSpecies
                .filter { $0.regionalAffinity.contains(selectedRegion.id) }
                .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
            signals = ShortlistRanker.topSpecies(from: allSignals, limit: allSignals.count)
        } catch {
            errorMessage = "Nepodarilo sa načítať údaje o počasí. Skúste to znova."
        }
    }
}
```

- [ ] **Step 3: Implement the region picker**

```swift
// MushroomSignal/Views/RegionPickerView.swift
import SwiftUI
import MushroomSignalCore

struct RegionPickerView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Picker("Kraj", selection: Binding(
            get: { appState.selectedRegion },
            set: { appState.selectRegion($0) }
        )) {
            ForEach(RegionDatabase.all) { region in
                Text(region.nameSk).tag(region)
            }
        }
        .pickerStyle(.menu)
    }
}
```

- [ ] **Step 4: Implement the root content view**

(References `ShortlistView` and `RegionMapView` from Tasks 13-14 — build after those exist, or stub them temporarily to verify this file compiles in isolation.)

```swift
// MushroomSignal/ContentView.swift
import SwiftUI
import MushroomSignalCore

struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var selectedTab: Tab = .shortlist

    enum Tab {
        case shortlist
        case map
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                ShortlistView(appState: appState)
                    .tabItem { Label("Zoznam", systemImage: "list.bullet") }
                    .tag(Tab.shortlist)

                RegionMapView(appState: appState)
                    .tabItem { Label("Mapa", systemImage: "map") }
                    .tag(Tab.map)
            }
            .navigationTitle("Mushroom Signal")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    RegionPickerView(appState: appState)
                }
            }
        }
        .task { await appState.refresh() }
        .frame(minWidth: 420, minHeight: 480)
    }
}
```

- [ ] **Step 5: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignal/MushroomSignalApp.swift MushroomSignal/AppState.swift MushroomSignal/ContentView.swift MushroomSignal/Views/RegionPickerView.swift
git commit -m "feat: add companion app shell, state, and region picker"
```

(Build verification for this task happens at the end of Task 13, once `ShortlistView` exists and the app target actually compiles end-to-end.)

---

### Task 13: Companion app — full shortlist view

**Files:**
- Create: `MushroomSignal/Views/ShortlistView.swift`

**Interfaces:**
- Consumes: `AppState`, `DesignSystem`, `SpeciesSignal` (Task 12, Phase A Task 7)

- [ ] **Step 1: Implement**

```swift
// MushroomSignal/Views/ShortlistView.swift
import SwiftUI
import MushroomSignalCore

struct ShortlistView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.spacingMedium) {
                if let error = appState.errorMessage {
                    Text(error).foregroundStyle(DesignSystem.Colors.danger)
                }

                ForEach(appState.signals, id: \.species.id) { signal in
                    signalRow(signal)
                }

                disclaimer
            }
            .padding(DesignSystem.spacingLarge)
        }
        .background(DesignSystem.Colors.forestDeep)
        .refreshable { await appState.refresh() }
    }

    private func signalRow(_ signal: SpeciesSignal) -> some View {
        let clampedScore = max(0, min(3, signal.score))
        return VStack(alignment: .leading, spacing: DesignSystem.spacingSmall / 2) {
            HStack {
                Text(signal.species.commonNameSk)
                    .font(.headline)
                    .foregroundStyle(DesignSystem.Colors.cloud)
                Spacer()
                Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 3 - clampedScore))
                    .foregroundStyle(DesignSystem.Colors.mossAccent)
            }
            Text(signal.species.latinName)
                .font(.caption)
                .italic()
                .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
            if let reason = signal.reason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            }
            if signal.species.edibility == .poisonous {
                Text("⚠️ Jedovatá")
                    .font(.caption2.bold())
                    .foregroundStyle(DesignSystem.Colors.danger)
            }
        }
        .padding(DesignSystem.spacingMedium)
        .background(DesignSystem.Colors.forestMid.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))
    }

    private var disclaimer: some View {
        Text("Tento zoznam je len orientačný odhad na základe počasia a sezóny. Pred zberom a konzumáciou húb si nález vždy overte s odborníkom alebo v spoľahlivom atlase húb.")
            .font(.caption2)
            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
            .padding(.top, DesignSystem.spacingMedium)
    }
}
```

- [ ] **Step 2: Build to verify the app target compiles**

(This requires `RegionMapView` from Task 14 too, since `ContentView` references it. If building this task in isolation before Task 14 exists, temporarily stub `RegionMapView` as an empty `View` to unblock the build, then remove the stub in Task 14.)

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignal/Views/ShortlistView.swift
git commit -m "feat: add full shortlist view with safety disclaimer"
```

---

### Task 14: Companion app — regional heat map

**Files:**
- Create: `MushroomSignal/Views/RegionMapView.swift`

**Interfaces:**
- Consumes: `AppState`, `RegionDatabase`, `OpenMeteoClient`, `SpeciesDatabase`, `SignalAlgorithm`, `DesignSystem` (Phase A, Task 12)

This is a schematic grid layout of the 8 kraje in their approximate relative positions (west-to-east, south-to-north) — not a geographically precise map. That matches the "mini regional map" concept approved during brainstorming (option C in the mockup), without fabricating precise geographic boundary data.

- [ ] **Step 1: Implement**

```swift
// MushroomSignal/Views/RegionMapView.swift
import SwiftUI
import MushroomSignalCore

struct RegionMapView: View {
    @ObservedObject var appState: AppState
    @State private var regionScores: [String: Int] = [:]
    @State private var isLoading = false

    // Approximate relative layout of Slovakia's 8 kraje (schematic, not geographically precise).
    private let layout: [[String?]] = [
        ["zilinsky", "zilinsky", "presovsky", "presovsky"],
        ["trenciansky", "banskobystricky", "banskobystricky", "kosicky"],
        ["bratislavsky", "trnavsky", "nitriansky", "kosicky"]
    ]

    var body: some View {
        VStack(spacing: DesignSystem.spacingMedium) {
            Text("Podmienky podľa kraja")
                .font(.headline)
                .foregroundStyle(DesignSystem.Colors.cloud)

            VStack(spacing: DesignSystem.spacingSmall / 2) {
                ForEach(0..<layout.count, id: \.self) { row in
                    HStack(spacing: DesignSystem.spacingSmall / 2) {
                        ForEach(0..<layout[row].count, id: \.self) { col in
                            regionCell(id: layout[row][col])
                        }
                    }
                }
            }

            if isLoading {
                ProgressView()
            }

            legend
        }
        .padding(DesignSystem.spacingLarge)
        .background(DesignSystem.Colors.forestDeep)
        .task { await loadAllRegionScores() }
    }

    @ViewBuilder
    private func regionCell(id: String?) -> some View {
        if let id, let region = RegionDatabase.find(id: id) {
            let score = regionScores[id] ?? 0
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3)
                .fill(color(for: score))
                .overlay(
                    Text(region.nameSk.replacingOccurrences(of: " kraj", with: ""))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(4)
                )
                .frame(minWidth: 60, minHeight: 44)
                .onTapGesture { appState.selectRegion(region) }
        } else {
            Color.clear.frame(minWidth: 60, minHeight: 44)
        }
    }

    private func color(for score: Int) -> Color {
        switch score {
        case 3: return DesignSystem.Colors.mossAccent
        case 2: return DesignSystem.Colors.mossAccent.opacity(0.55)
        case 1: return DesignSystem.Colors.bark.opacity(0.6)
        default: return DesignSystem.Colors.bark.opacity(0.3)
        }
    }

    private var legend: some View {
        HStack(spacing: DesignSystem.spacingMedium) {
            legendItem(color: DesignSystem.Colors.mossAccent, label: "Vysoká šanca")
            legendItem(color: DesignSystem.Colors.bark.opacity(0.6), label: "Nízka šanca")
        }
        .font(.caption2)
        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }

    private func loadAllRegionScores() async {
        isLoading = true
        defer { isLoading = false }
        let client = OpenMeteoClient()
        let month = Calendar.current.component(.month, from: Date())
        guard let allSpecies = try? SpeciesDatabase.loadAll() else { return }

        await withTaskGroup(of: (String, Int).self) { group in
            for region in RegionDatabase.all {
                group.addTask {
                    guard let weather = try? await client.fetchSnapshot(for: region) else {
                        return (region.id, 0)
                    }
                    let signals = allSpecies
                        .filter { $0.regionalAffinity.contains(region.id) }
                        .map { SignalAlgorithm.computeSignal(species: $0, weather: weather, month: month) }
                    return (region.id, signals.map(\.score).max() ?? 0)
                }
            }
            for await (id, score) in group {
                regionScores[id] = score
            }
        }
    }
}
```

- [ ] **Step 2: Build the full app target end-to-end**

Run: `xcodebuild -project MushroomSignal.xcodeproj -scheme MushroomSignal -configuration Debug build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run in Xcode and verify manually**

Open `MushroomSignal.xcodeproj` in Xcode, run the `MushroomSignal` scheme, and check: the app launches, region picker switches regions, shortlist populates after a refresh, map tab shows the 8-kraj grid colored by conditions, and tapping a map cell switches the selected region. Then check the widget: add it via System Settings → Widgets (or right-click desktop → Edit Widgets) and confirm the small widget renders the ranked shortlist for the same selected region.

- [ ] **Step 4: Commit**

```bash
cd ~/Coding/mushroom-signal
git add MushroomSignal/Views/RegionMapView.swift
git commit -m "feat: add regional conditions heat map"
```

