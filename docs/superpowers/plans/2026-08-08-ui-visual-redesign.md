# UI Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the full UI visual redesign from `docs/superpowers/specs/2026-08-08-ui-visual-redesign-design.md`: a 20pt app-wide (including widget) typography floor, a local photo cache fed by a real edible-species photo research pass, one shared photo-forward `SpeciesCardView` powering an adaptive grid on both Zoznam and Mapa's library, and a per-kraj polygon map overlay replacing the current grid-of-circles.

**Architecture:** Typography lands first since later tasks (the card, the widget redesign) consume its final token values. Photo infrastructure (cache, then the card that uses it) lands before the photo research pass, so the research task has something real to plug into and test against. The map redesign is architecturally independent of the other three — it reuses the existing `WeatherClient.fetchSnapshots(for: [GridPoint])` batched fetch (already implemented, no protocol change needed) by feeding it region-derived `GridPoint`s instead of `SlovakiaGrid`'s fine grid, and replaces `MapCircle` overlays with `MapPolygon` shapes.

**Tech Stack:** Swift, SwiftUI (`MapPolygon`/`MapKit` for the map, `LazyVGrid`/`GridItem(.adaptive)` for the responsive grid), Swift Package Manager (`MushroomSignalCore`), XCTest, `FileManager` for the local photo cache (no new dependencies).

## Global Constraints

- Every text element across the whole app, including the WidgetKit extension, must render at ≥20pt. (Spec §6, confirmed explicitly: "It includes the entire application. It is too small to read.")
- The card component's size is a qualitative target ("eye-catching but not too big"), not an enforced exact dimension — implementation should feel right, not hit a specific pixel value. (Spec §1, revised 2026-08-08.)
- Photos are sourced only for `edibility == .edible` species. `.caution`/`.poisonous` species get no photo, ever, in this pass. (Spec §3.)
- No cloud/remote photo storage — local disk cache only, download-once. (Spec §4.)
- No scraping of unlicensed sites for photos or geo data. Photo URLs for this pass are supplied directly by Alexander with license verification deferred as declared tech debt (Task 6, revised 2026-08-09) — not yet confirmed CC-licensed/reusable, must be checked before public release. Kraj shapes use hand-approximated original polygon data, not any external unlicensed dataset. (Spec §3, §5.)
- The widget gets the typography floor (§6) and nothing else from this plan — no card/grid/photo treatment. (Spec, Out of Scope.)
- Every commit must leave `swift test --package-path MushroomSignalCore` and the Xcode-level `MushroomSignalTests` target green — no intermediate broken states, same discipline as the 2026-08-07 scoring-intelligence plan.

---

## Task 1: Raise the Typography Floor in `DesignSystem`

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`

**Interfaces:**
- Produces: `DesignSystem.captionSize`, `bodySize`, `titleSize`, `heroSize` — same names, new values, all ≥20.

**Design decision, stated plainly rather than silently changed:** the current scale mechanically applies `goldenRatio` (1.618) four times from an 8pt floor (8 → 12.94 → 20.94 → 33.87). Applying the same multiplicative scale from a 20pt floor would produce a 20 → 32.36 → 52.36 → 84.72 progression — an 84pt hero size, which would be absurd in a widget's hero row (`MushroomSignalWidget/ShortlistWidgetView.swift`'s `heroRow` already renders at `heroSize` today). Alexander's complaint was specifically "too small to read," not "make the biggest text much bigger too." This task uses a gentler, still-clearly-graduated scale that satisfies the ≥20pt floor without the golden-ratio compounding: `captionSize: 20, bodySize: 24, titleSize: 28, heroSize: 36`. Flag this for Alexander's review during the task review — it's a deliberate deviation from mechanically reapplying the existing formula, not an oversight.

- [ ] **Step 1: Update the typography constants**

In `DesignSystem.swift`, replace:

```swift
    private static let typographyUnit: Double = 8
    public static let captionSize: Double = typographyUnit
    public static let bodySize: Double = captionSize * goldenRatio
    public static let titleSize: Double = bodySize * goldenRatio
    public static let heroSize: Double = titleSize * goldenRatio
```

with:

```swift
    // Floor raised to 20pt app-wide (including the widget) 2026-08-08 — "too small to
    // read" was Alexander's exact complaint, applying goldenRatio's full multiplicative
    // compounding from a 20pt floor would push heroSize to ~85pt, so this scale is a
    // gentler graduated progression that satisfies the floor without that blowup.
    public static let captionSize: Double = 20
    public static let bodySize: Double = 24
    public static let titleSize: Double = 28
    public static let heroSize: Double = 36
```

- [ ] **Step 2: Build the core package to confirm no compile errors**

Run: `swift build --package-path MushroomSignalCore`
Expected: SUCCEED — this is a pure constant-value change, nothing depends on the removed `typographyUnit` private constant outside this file.

- [ ] **Step 3: Run the full core package test suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS — no existing test asserts specific typography values (confirm this yourself by grepping the test suite for `captionSize`/`bodySize`/`titleSize`/`heroSize`; if you find one, it needs updating as part of this step, not left broken).

- [ ] **Step 4: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift
git commit -m "feat: raise DesignSystem typography floor to 20pt, app-wide"
```

---

## Task 2: Audit and Migrate Raw System Font Styles to `DesignSystem` Tokens

**Files:**
- Modify: `MushroomSignal/Views/ShortlistView.swift`
- Modify: `MushroomSignal/Views/SpeciesDetailView.swift`
- Modify: `MushroomSignal/Views/PhotoCreditsView.swift`
- Modify: `MushroomSignal/Views/InteractiveMapView.swift`
- Modify: `MushroomSignal/Views/SpeciesLibraryView.swift`

**Interfaces:**
- Consumes: `DesignSystem.captionSize/bodySize/titleSize/heroSize` (Task 1).
- Produces: no new interface — visual-only change, replacing raw `.caption`/`.caption2`/`.subheadline`/`.headline`/`.body`/`.title2` system font styles (which render well under 20pt) with explicit `.system(size: DesignSystem.<token>)` calls.

This project's own Hard Constraint already requires all styling to route through `DesignSystem` — this task also closes that long-standing, previously-undocumented-as-fixed gap for typography specifically, not just this pass's new UI.

- [ ] **Step 1: `ShortlistView.swift` — replace every raw font style**

Read the file first to confirm current line numbers before editing (they may have shifted since this plan was written). Replace each of the following, matching each `Text` call's existing modifier chain exactly except for the font:

- `.font(.headline)` (species name in `signalRow`) → `.font(.system(size: DesignSystem.titleSize, weight: .semibold))`
- `.font(.caption)` (Latin name) → `.font(.system(size: DesignSystem.captionSize).italic())`
- `.font(.caption2)` (reason text) → `.font(.system(size: DesignSystem.captionSize))`
- `.font(.caption2.bold())` (warning label) → `.font(.system(size: DesignSystem.captionSize, weight: .bold))`
- `.font(.caption2)` (disclaimer text) → `.font(.system(size: DesignSystem.captionSize))`

- [ ] **Step 2: `SpeciesDetailView.swift` — replace every raw font style**

Read the file first. Replace:

- `.font(.title2.bold())` (common name) → `.font(.system(size: DesignSystem.heroSize, weight: .bold))`
- `.font(.subheadline).italic()` (Latin name) → `.font(.system(size: DesignSystem.bodySize).italic())`
- `.font(.subheadline.bold())` (warning) → `.font(.system(size: DesignSystem.bodySize, weight: .bold))`
- `.font(.caption)` ("Zdroje fotografií" button) → `.font(.system(size: DesignSystem.captionSize))`
- In `detailRow(title:value:)`: `.font(.caption.bold())` (row title) → `.font(.system(size: DesignSystem.captionSize, weight: .bold))`, `.font(.body)` (row value) → `.font(.system(size: DesignSystem.bodySize))`

- [ ] **Step 3: `PhotoCreditsView.swift` — replace every raw font style**

Read the file first. Replace:

- `.font(.subheadline.bold())` (photographer name) → `.font(.system(size: DesignSystem.bodySize, weight: .bold))`
- `.font(.caption)` (license) → `.font(.system(size: DesignSystem.captionSize))`
- `.font(.caption2)` (source URL link) → `.font(.system(size: DesignSystem.captionSize))`

- [ ] **Step 4: `InteractiveMapView.swift` — replace the legend's raw font style**

Read the file first. Replace `.font(.caption2)` (species name in the legend) → `.font(.system(size: DesignSystem.captionSize))`.

- [ ] **Step 5: `SpeciesLibraryView.swift` — replace remaining raw font styles**

Read the file first. Replace:

- `.font(.headline)` ("Knižnica druhov" title) → `.font(.system(size: DesignSystem.titleSize, weight: .semibold))`
- `.font(.caption)` (species card name — note: this specific card is replaced entirely in Task 8, but fix it here anyway since Task 2 must land before Task 8 and every commit must stay internally consistent)

- [ ] **Step 6: Build and run the full Xcode test suite**

Run: `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Manual visual check**

Launch the app (a full signed build per this project's established `xcodebuild -configuration Release` pattern) and confirm text is visibly larger and reads comfortably across the shortlist, species detail sheet, and map legend. Build + visual check only — this project has no snapshot-testing setup, and adding one is out of scope for this pass (per the spec's Testing section).

- [ ] **Step 8: Commit**

```bash
git add MushroomSignal/Views/ShortlistView.swift MushroomSignal/Views/SpeciesDetailView.swift MushroomSignal/Views/PhotoCreditsView.swift MushroomSignal/Views/InteractiveMapView.swift MushroomSignal/Views/SpeciesLibraryView.swift
git commit -m "feat: migrate raw system font styles to DesignSystem's 20pt+ tokens"
```

---

## Task 3: Redesign the Widget's Small/Medium Family Layout for the 20pt Floor

**Files:**
- Modify: `MushroomSignalWidget/ShortlistWidgetView.swift`

**Interfaces:**
- Consumes: `DesignSystem.captionSize/bodySize/titleSize/heroSize` (Task 1, now ≥20).
- Produces: no new interface — same `ShortlistEntry`/`SpeciesSignal` inputs, redesigned layout.

**The real cost, named up front (per the spec's own framing):** the small widget family is ~155×155pt total. Its current layout fits 2-3 rows of forecast text (name + latin name + score dots per row) at sizes as small as `captionSize` (previously 8pt, now 24pt) with a `.minimumScaleFactor(0.8)` safety net. At the new floor, three full rows of ≥20pt text plus padding will not fit in 155pt of height — this is not a font-size tweak, it's a real content-density reduction.

**Design for this task:** reduce the small family to a **single hero-style row** (one species — the top-ranked one — with a fallback "+N more" indicator if there are additional signals) instead of trying to cram 2-3 rows. The medium family, with more horizontal but the same vertical room, keeps 2 rows instead of 3. The large family already uses a hero-row-plus-list layout with more vertical room (it's roughly 155×345pt) — it likely needs less restructuring, but must still be checked against the new sizes, not assumed fine.

- [ ] **Step 1: Read the current file in full**

The exact current layout (`smallBody`, `mediumBody`, `largeBody`, `row`, `heroRow` helper functions) is described in this plan's exploration but may have shifted — read it fresh before editing.

- [ ] **Step 2: Redesign `smallBody` to a single-species hero layout**

Replace the current `smallBody` (a list of up to ~2-3 `row(...)` calls) with a layout showing only `entry.signals.first` via a compact hero treatment (reuse `heroRow`, but confirm it actually fits ~155×155pt at the new sizes by building and visually checking — Step 6). If `entry.signals.count > 1`, add a small trailing indicator (e.g. `Text("+\(entry.signals.count - 1) ďalších")` at `captionSize`) so the user knows more exist without cramming them in. If `entry.signals.isEmpty`, keep the existing `emptyStateIfNeeded` treatment.

- [ ] **Step 3: Redesign `mediumBody` to 2 rows instead of 3**

Change `ForEach(entry.signals, ...)` in `mediumBody` to `ForEach(entry.signals.prefix(2), ...)`, keeping the existing `inlineLatin: true` row style. If `entry.signals.count > 2`, add the same small "+N ďalších" trailing indicator used in `smallBody`.

- [ ] **Step 4: Check `largeBody` against the new sizes**

`largeBody` already uses `heroRow` (for the top signal) plus `row(...)` for `entry.signals.dropFirst()` at `titleSize`. With `titleSize` now 28 (was ~20.94) and `heroSize` now 36 (was ~33.87), these are close to previous sizes, not a dramatic jump — but confirm via the Step 6 visual check that the existing 4-item layout (hero + 3 rows) still fits ~155×345pt without truncation before assuming no change is needed. If it doesn't fit, reduce to hero + 2 rows, following the same "fewer items, not smaller text" principle used for small/medium.

- [ ] **Step 5: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Manual visual check via Xcode preview, per family**

Open `ShortlistWidgetView.swift` in Xcode, check all three `#Preview` blocks (Small/Medium/Large) render without truncation, overlap, or `minimumScaleFactor` kicking in so hard the text looks visibly shrunk back down. This is the actual verification for this task — build success alone doesn't prove the layout fits.

- [ ] **Step 7: Commit**

```bash
git add MushroomSignalWidget/ShortlistWidgetView.swift
git commit -m "feat: redesign widget small/medium layout for the 20pt typography floor"
```

---

## Task 4: `PhotoCache` — Download-Once, Cache-Locally

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Weather/PhotoCache.swift` — actually, place in a new `Photos/` group for clarity: `MushroomSignalCore/Sources/MushroomSignalCore/Photos/PhotoCache.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/PhotoCacheTests.swift`

**Interfaces:**
- Consumes: nothing new from other tasks.
- Produces: `PhotoCache.cachedImageData(for url: URL) async throws -> Data` — Task 5's `CachedAsyncImage` consumes this.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import MushroomSignalCore

final class MockPhotoURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockPhotoURLProtocol.requestCount += 1
        guard let handler = MockPhotoURLProtocol.requestHandler else {
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

final class PhotoCacheTests: XCTestCase {
    private func makeMockedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockPhotoURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeTempCacheDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoCacheTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override func tearDown() {
        MockPhotoURLProtocol.requestHandler = nil
        MockPhotoURLProtocol.requestCount = 0
        super.tearDown()
    }

    func testCacheMissDownloadsAndPersists() async throws {
        let imageBytes = Data([0xFF, 0xD8, 0xFF]) // minimal JPEG-like byte sequence, content doesn't matter for this test
        MockPhotoURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, imageBytes)
        }
        let cacheDir = makeTempCacheDirectory()
        let cache = PhotoCache(session: makeMockedSession(), cacheDirectory: cacheDir)
        let url = URL(string: "https://upload.wikimedia.org/example.jpg")!

        let data = try await cache.cachedImageData(for: url)

        XCTAssertEqual(data, imageBytes)
        XCTAssertEqual(MockPhotoURLProtocol.requestCount, 1, "a cache miss must trigger exactly one network request")
    }

    func testCacheHitServesFromDiskWithoutASecondNetworkCall() async throws {
        let imageBytes = Data([0xFF, 0xD8, 0xFF])
        MockPhotoURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, imageBytes)
        }
        let cacheDir = makeTempCacheDirectory()
        let cache = PhotoCache(session: makeMockedSession(), cacheDirectory: cacheDir)
        let url = URL(string: "https://upload.wikimedia.org/example.jpg")!

        _ = try await cache.cachedImageData(for: url) // first call: cache miss, populates the cache
        XCTAssertEqual(MockPhotoURLProtocol.requestCount, 1)

        let secondData = try await cache.cachedImageData(for: url) // second call: must be a cache hit

        XCTAssertEqual(secondData, imageBytes)
        XCTAssertEqual(MockPhotoURLProtocol.requestCount, 1, "a cache hit must not trigger a second network request")
    }

    func testDifferentURLsCacheIndependently() async throws {
        let firstBytes = Data([0x01])
        let secondBytes = Data([0x02])
        var callCount = 0
        MockPhotoURLProtocol.requestHandler = { request in
            callCount += 1
            let bytes = request.url!.absoluteString.contains("first") ? firstBytes : secondBytes
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, bytes)
        }
        let cacheDir = makeTempCacheDirectory()
        let cache = PhotoCache(session: makeMockedSession(), cacheDirectory: cacheDir)

        let firstData = try await cache.cachedImageData(for: URL(string: "https://example.com/first.jpg")!)
        let secondData = try await cache.cachedImageData(for: URL(string: "https://example.com/second.jpg")!)

        XCTAssertEqual(firstData, firstBytes)
        XCTAssertEqual(secondData, secondBytes)
        XCTAssertEqual(MockPhotoURLProtocol.requestCount, 2)
    }

    func testThrowsOnNonOKStatus() async throws {
        MockPhotoURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data())
        }
        let cacheDir = makeTempCacheDirectory()
        let cache = PhotoCache(session: makeMockedSession(), cacheDirectory: cacheDir)

        do {
            _ = try await cache.cachedImageData(for: URL(string: "https://example.com/missing.jpg")!)
            XCTFail("Expected an error for a 404 response")
        } catch {
            // expected — exact error type not asserted, PhotoCache.swift defines it in Step 3
        }
    }
}
```

- [ ] **Step 2: Run to verify the tests fail**

Run: `swift test --package-path MushroomSignalCore --filter PhotoCacheTests`
Expected: FAIL — `PhotoCache` doesn't exist yet.

- [ ] **Step 3: Implement `PhotoCache`**

```swift
import Foundation

public enum PhotoCacheError: Error, Equatable {
    case invalidResponse
}

/// Downloads a photo once and persists it to local disk; subsequent requests for the same
/// URL are served from disk with no network call. Photos are static content (a species'
/// representative photo doesn't change), so there is no expiry — this is a permanent cache,
/// not a time-limited one. Matches this app's zero-backend, local-only architecture.
public struct PhotoCache: Sendable {
    private let session: URLSession
    private let cacheDirectory: URL

    public init(session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.session = session
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.cacheDirectory = base.appendingPathComponent("SpeciesPhotos", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    public func cachedImageData(for url: URL) async throws -> Data {
        let cacheFileURL = cacheDirectory.appendingPathComponent(cacheKey(for: url))

        if let cached = try? Data(contentsOf: cacheFileURL) {
            return cached
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw PhotoCacheError.invalidResponse
        }

        try? data.write(to: cacheFileURL)
        return data
    }

    private func cacheKey(for url: URL) -> String {
        // A stable, filesystem-safe key derived from the URL itself — no external hashing
        // dependency needed, Swift's String.hashValue is stable within a single process
        // run, but for a persistent on-disk key across launches, use a simple deterministic
        // transform instead: percent-decode-safe base of the URL's last path component plus
        // a short digest of the full URL to avoid collisions between same-named files from
        // different sources.
        let lastComponent = url.lastPathComponent.isEmpty ? "photo" : url.lastPathComponent
        var hasher = Hasher()
        hasher.combine(url.absoluteString)
        let digest = String(format: "%08x", UInt32(bitPattern: Int32(truncatingIfNeeded: hasher.finalize())))
        return "\(digest)-\(lastComponent)"
    }
}
```

- [ ] **Step 4: Run to verify all tests pass**

Run: `swift test --package-path MushroomSignalCore --filter PhotoCacheTests`
Expected: PASS — all 4 tests.

- [ ] **Step 5: Run the full core package suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Photos/PhotoCache.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/PhotoCacheTests.swift
git commit -m "feat: add PhotoCache for download-once, cache-locally species photos"
```

---

## Task 5: `CachedAsyncImage` View + Wire Into Existing Photo Call Sites

**Files:**
- Create: `MushroomSignal/Views/CachedAsyncImage.swift`
- Modify: `MushroomSignal/Views/SpeciesDetailView.swift`
- Modify: `MushroomSignal/Views/SpeciesLibraryView.swift`

**Interfaces:**
- Consumes: `PhotoCache.cachedImageData(for:)` (Task 4).
- Produces: `CachedAsyncImage(url:content:placeholder:)` — a SwiftUI view Task 7's `SpeciesCardView` also consumes.

- [ ] **Step 1: Implement `CachedAsyncImage`**

```swift
// MushroomSignal/Views/CachedAsyncImage.swift
import SwiftUI
import MushroomSignalCore

/// Like `AsyncImage`, but backed by `PhotoCache` — a photo already seen once loads
/// instantly from disk on every later appearance, including across app launches.
struct CachedAsyncImage<Content: View, PlaceholderContent: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> PlaceholderContent

    @State private var loadedImage: Image?
    private static var sharedCache: PhotoCache { PhotoCache() }

    var body: some View {
        Group {
            if let loadedImage {
                content(loadedImage)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            do {
                let data = try await Self.sharedCache.cachedImageData(for: url)
                #if canImport(AppKit)
                if let nsImage = NSImage(data: data) {
                    loadedImage = Image(nsImage: nsImage)
                }
                #endif
            } catch {
                loadedImage = nil
            }
        }
    }
}
```

- [ ] **Step 2: Replace `SpeciesDetailView.swift`'s `AsyncImage` usage**

Read the current file first (Task 2 already touched its fonts — build on that, don't revert it). Replace the `AsyncImage(url: photo.imageURL) { phase in ... }` block with:

```swift
CachedAsyncImage(url: photo.imageURL) { image in
    image.resizable().aspectRatio(contentMode: .fill)
} placeholder: {
    DesignSystem.Colors.bark.opacity(0.4)
}
.frame(width: DesignSystem.detailPhotoWidth, height: DesignSystem.detailPhotoHeight)
.clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 3))
```

(The `.frame`/`.clipShape` modifiers move outside the `CachedAsyncImage` call since it isn't itself a `View` requiring `.resizable()` first — confirm this compiles; if `CachedAsyncImage`'s generic constraints need adjustment to support this call shape, that's an acceptable implementation-time fix, not a plan violation.)

- [ ] **Step 3: Replace `SpeciesLibraryView.swift`'s `AsyncImage` usage**

Read the current file first. In `photoThumbnail(_:)`, replace the `AsyncImage(url: photo.imageURL) { phase in switch phase { ... } }` block with the same `CachedAsyncImage` pattern as Step 2, preserving the existing `.frame(height: DesignSystem.thumbnailHeight)` / `.clipShape(...)` modifiers applied outside it. (Note: this whole card is replaced in Task 9 anyway — this step exists so Task 5's commit is internally complete and consistent on its own, matching this plan's "every commit stays green" discipline.)

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual visual check**

Launch the app, open the species library (Mapa tab) and a species detail sheet — confirm photos still load correctly (they'll still be placeholders at this point, since Task 6's research pass hasn't populated `species-photos.json` yet — confirm the *placeholder* renders correctly, not a crash or blank view).

- [ ] **Step 6: Commit**

```bash
git add MushroomSignal/Views/CachedAsyncImage.swift MushroomSignal/Views/SpeciesDetailView.swift MushroomSignal/Views/SpeciesLibraryView.swift
git commit -m "feat: add CachedAsyncImage and wire it into existing photo call sites"
```

---

## Task 6: Photo Placeholder-URL Pass (Edible Species Only)

**Revised 2026-08-09** — descoped from a Commons research pass to a direct link-ingestion pass. Alexander is supplying exact image URLs himself (token cost of doing the Commons research + license verification per species isn't worth paying right now). See "Deferred: license verification" below for the tech debt this creates.

**Files:**
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/Data/species-photos.json`

**Interfaces:**
- Consumes: `SpeciesPhoto` model (unchanged — all 6 fields stay non-optional, see below), `Species.edibility` (existing field).
- Produces: nothing new — populates existing, currently-empty data.

- [ ] **Step 1: List every edible species**

Run: `python3 -c "import json; d=json.load(open('MushroomSignalCore/Sources/MushroomSignalCore/Data/species.json')); print([s['id'] for s in d if s['edibility']=='edible'])"`

20 species. Work through this list against the URLs Alexander supplies.

- [ ] **Step 2: For each edible species, take the URL Alexander supplies — no research, no license check**

Record:
- `imageURL`: the direct image URL as given.
- `sourceURL`: the same URL, unless Alexander gives a separate source/page link for that species.
- `photographer`: literal placeholder string `"UNVERIFIED"`.
- `license`: literal placeholder string `"UNVERIFIED"`.
- `speciesId`: the species' id from `species.json`.
- `id`: a stable unique id, e.g. `"<speciesId>-1"`.

**Deferred: license verification.** These placeholder `photographer`/`license` values mean the images' actual reusability has not been checked — some could turn out to be non-reusable (all-rights-reserved images sometimes get mirrored onto Commons/other sites incorrectly). This is fine for local personal use; it becomes a real requirement before any public release or distribution of the app. Tracked in `KNOWN_ISSUES.md` (Step 5b below).

- [ ] **Step 3: Append each entry to `species-photos.json`**

The file is currently `[]`. Each entry follows the `SpeciesPhoto` model's exact field names shown in Step 2. Multiple photos per species are allowed (the model and `SpeciesDetailView`'s horizontal gallery already support it) but not required — one URL per species is a fine outcome for this pass.

- [ ] **Step 4: Verify the JSON is well-formed and complete**

Run: `python3 -c "import json; d=json.load(open('MushroomSignalCore/Sources/MushroomSignalCore/Data/species-photos.json')); print(len(d))"`
Expected: a count ≥ the number of edible species (some may reasonably get more than one photo).

- [ ] **Step 5: Add a schema-validation test**

Add to `MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesPhotoDatabaseTests.swift` (read the file first — it already has 2 tests per this project's history; add to them, don't replace):

```swift
    func testEveryEdibleSpeciesHasAtLeastOnePhoto() throws {
        let species = try SpeciesDatabase.loadAll()
        let photos = try SpeciesPhotoDatabase.loadAll()
        let speciesIdsWithPhotos = Set(photos.map(\.speciesId))
        let edibleSpeciesIds = Set(species.filter { $0.edibility == .edible }.map(\.id))

        let missing = edibleSpeciesIds.subtracting(speciesIdsWithPhotos)
        XCTAssertTrue(missing.isEmpty, "edible species missing a photo: \(missing.sorted())")
    }

    func testNoCautionOrPoisonousSpeciesHasAPhoto() throws {
        let species = try SpeciesDatabase.loadAll()
        let photos = try SpeciesPhotoDatabase.loadAll()
        let speciesIdsWithPhotos = Set(photos.map(\.speciesId))
        let nonEdibleSpeciesIds = Set(species.filter { $0.edibility != .edible }.map(\.id))

        let violating = nonEdibleSpeciesIds.intersection(speciesIdsWithPhotos)
        XCTAssertTrue(violating.isEmpty, "non-edible species should never have a sourced photo: \(violating.sorted())")
    }

    func testEveryPhotoReferencesARealSpecies() throws {
        let species = try SpeciesDatabase.loadAll()
        let speciesIds = Set(species.map(\.id))
        let photos = try SpeciesPhotoDatabase.loadAll()

        for photo in photos {
            XCTAssertTrue(speciesIds.contains(photo.speciesId), "\(photo.id) references unknown species \(photo.speciesId)")
        }
    }
```

- [ ] **Step 6: Run the full core package suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS — including the 3 new tests, proving every edible species has a photo, no non-edible species does, and every reference resolves.

- [ ] **Step 7: Add a `KNOWN_ISSUES.md` entry**

Add a line noting `species-photos.json` currently carries placeholder `photographer`/`license` values (`"UNVERIFIED"`) for all entries — image reusability has not been checked and must be verified before any public release or distribution of the app.

- [ ] **Step 8: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Data/species-photos.json MushroomSignalCore/Tests/MushroomSignalCoreTests/SpeciesPhotoDatabaseTests.swift docs/superpowers/KNOWN_ISSUES.md
git commit -m "data: populate species-photos.json with placeholder image URLs (unverified license)"
```

- [ ] **Step 9: Flag for Alexander's review**

Two things pending his review, not automatically final: (1) content — is each photo a good, representative, clearly-identifiable shot of the species; (2) the deferred license-verification tech debt from Step 2, before any public release.

---

## Task 7: Shared `SpeciesCardView`

**Files:**
- Create: `MushroomSignal/Views/SpeciesCardView.swift`
- Modify: `MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift`

**Interfaces:**
- Consumes: `CachedAsyncImage` (Task 5), `DesignSystem` typography tokens (Task 1), `SpeciesSignal`/`Species`/`SpeciesPhoto` (existing).
- Produces: `SpeciesCardView` — Tasks 8 and 9 consume this to replace Zoznam's list and the library's small-card grid.

**Size, per the spec's revised §1 — a starting point, not an enforced value:** add one new `DesignSystem` token, `speciesCardMinWidth: Double = 340`, used as the adaptive grid's minimum column width (Task 8/9). The card's height is driven by its content (photo aspect ratio + text), not a second hard-coded dimension — this keeps the "not enforced" spirit real in the code, not just in prose.

- [ ] **Step 1: Add the new `DesignSystem` token**

In `DesignSystem.swift`, add alongside the other layout constants (near `cardCornerRadius`):

```swift
    /// Minimum column width for the adaptive species-card grid (Zoznam, Mapa library) — a
    /// starting point for "eye-catching but not too big," not an enforced exact size. See
    /// the 2026-08-08 UI redesign spec §1.
    public static let speciesCardMinWidth: Double = 340
```

- [ ] **Step 2: Implement `SpeciesCardView`**

```swift
// MushroomSignal/Views/SpeciesCardView.swift
import SwiftUI
import MushroomSignalCore

/// One shared card, used by both Zoznam's shortlist grid and Mapa's species library grid —
/// same visual identity everywhere. `signal` carries score/reason for Zoznam's forecast
/// context; pass `nil` for library-context cards where only identity (name, photo, active
/// state) matters, not a live forecast.
struct SpeciesCardView: View {
    let species: Species
    let photo: SpeciesPhoto?
    let signal: SpeciesSignal?
    let isActiveOnMap: Bool?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: photo?.imageURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                ZStack {
                    DesignSystem.Colors.bark.opacity(0.4)
                    Image(systemName: "photo")
                        .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.5))
                }
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fill)
            .clipped()

            LinearGradient(
                colors: [.clear, DesignSystem.Colors.forestDeep.opacity(0.9)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: DesignSystem.spacingTight) {
                Text(species.commonNameSk)
                    .font(.system(size: DesignSystem.bodySize, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.cloud)
                    .lineLimit(1)
                Text(species.latinName)
                    .font(.system(size: DesignSystem.captionSize).italic())
                    .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.7))
                    .lineLimit(1)

                if let signal {
                    let clampedScore = max(0, min(4, signal.score))
                    Text(String(repeating: "●", count: clampedScore) + String(repeating: "○", count: 4 - clampedScore))
                        .font(.system(size: DesignSystem.captionSize))
                        .foregroundStyle(DesignSystem.Colors.mossAccent)
                    if let reason = signal.reason {
                        Text(reason)
                            .font(.system(size: DesignSystem.captionSize))
                            .foregroundStyle(DesignSystem.Colors.cloud.opacity(0.6))
                            .lineLimit(2)
                    }
                }

                if let warning = DesignSystem.warningLabelSk(for: species.edibility) {
                    Text(warning)
                        .font(.system(size: DesignSystem.captionSize, weight: .bold))
                        .foregroundStyle(DesignSystem.warningColor(for: species.edibility))
                }
            }
            .padding(DesignSystem.spacingSmall)
        }
        .background(DesignSystem.Colors.forestMid)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.cardCornerRadius / 2)
                .stroke(isActiveOnMap == true ? DesignSystem.Colors.mossAccent : .clear, lineWidth: DesignSystem.borderWidth)
        )
    }
}
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **` — `SpeciesCardView` isn't used anywhere yet (Tasks 8/9 wire it in), so this just confirms it compiles standalone.

- [ ] **Step 4: Commit**

```bash
git add MushroomSignal/Views/SpeciesCardView.swift MushroomSignalCore/Sources/MushroomSignalCore/DesignSystem/DesignSystem.swift
git commit -m "feat: add shared SpeciesCardView"
```

---

## Task 8: Zoznam — Adaptive Grid + Unified Navigation

**Files:**
- Modify: `MushroomSignal/Views/ShortlistView.swift`

**Interfaces:**
- Consumes: `SpeciesCardView` (Task 7).
- Produces: no new interface — `ShortlistView`'s public shape (`init(appState:)`) is unchanged.

- [ ] **Step 1: Replace the vertical list with an adaptive grid of `SpeciesCardView`**

Read the current file first (Task 1/2 already touched it — build on that). Replace the body's `ForEach(appState.signals, id: \.species.id) { signal in signalRow(signal) }` (inside the `VStack` inside `ScrollView`) with:

```swift
LazyVGrid(columns: [GridItem(.adaptive(minimum: DesignSystem.speciesCardMinWidth), spacing: DesignSystem.spacingSmall)], spacing: DesignSystem.spacingSmall) {
    ForEach(appState.signals, id: \.species.id) { signal in
        SpeciesCardView(species: signal.species, photo: nil, signal: signal, isActiveOnMap: nil)
            .onTapGesture { detailSpecies = signal.species }
    }
}
```

Remove the now-unused `signalRow(_:)` private method entirely — `SpeciesCardView` replaces it.

- [ ] **Step 2: Add species-detail navigation state and photo lookup**

`ShortlistView` doesn't currently load `SpeciesPhoto` data at all (that's `MapScreenState`'s job today) — it needs its own lightweight access to photos for the cards. Add:

```swift
    @State private var detailSpecies: Species?
    @State private var photosBySpeciesID: [String: [SpeciesPhoto]] = [:]
```

In the grid code from Step 1, replace `photo: nil` with `photo: photosBySpeciesID[signal.species.id]?.first`.

Load photos once when the view appears — add a `.task` modifier (alongside or merged into any existing `.task`/`.onAppear` on the view's root) that loads `SpeciesPhotoDatabase.loadAll()` (existing method) into `photosBySpeciesID`, grouped by `speciesId` the same way `MapScreenState`'s `init` already does it (`Dictionary(grouping: photos, by: \.speciesId)`), with a `try?` fallback to an empty dictionary on failure (photos are enhancement, not core functionality — a failure here should never block the shortlist itself from working).

- [ ] **Step 3: Wire the detail sheet**

Add, alongside the grid (same level as the existing `.background`/`.refreshable` modifiers):

```swift
.sheet(item: $detailSpecies) { species in
    SpeciesDetailView(species: species, photos: photosBySpeciesID[species.id] ?? [])
}
```

(`Species` already conforms to `Identifiable` via its `id: String` — confirm this compiles with `.sheet(item:)` directly; if `Species` needs `Identifiable` conformance added, check first whether it already has it via `SpeciesDatabase`'s existing usage elsewhere in the app before assuming a change is needed.)

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual visual check**

Launch the app, open Zoznam. Confirm: cards render in a grid (not a list), resizing the app window changes how many cards fit per row, tapping a card opens the species detail sheet, and the disclaimer text (kept unchanged, still below the grid) is still present.

- [ ] **Step 6: Commit**

```bash
git add MushroomSignal/Views/ShortlistView.swift
git commit -m "feat: redesign Zoznam as an adaptive grid of SpeciesCardView"
```

---

## Task 9: Mapa Library — Adaptive Grid, Preserving Toggle-on-Tap

**Files:**
- Modify: `MushroomSignal/Views/SpeciesLibraryView.swift`

**Interfaces:**
- Consumes: `SpeciesCardView` (Task 7).
- Produces: no new interface — `SpeciesLibraryView`'s public shape is unchanged.

- [ ] **Step 1: Replace the manual-stepper grid with the adaptive grid**

Read the current file first (Task 2/5 already touched it). Replace:

```swift
    @State private var columnCount = 3
    ...
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DesignSystem.spacingSmall), count: columnCount)
    }
```

Remove `columnCount` and `columns` entirely, and the `Stepper("Stĺpce: \(columnCount)", ...)` in the header `HStack` (keep the "Knižnica druhov" title, remove just the stepper — leaving the header a plain title, no trailing control, unless that leaves an awkward empty `Spacer()`; if so, remove the now-purposeless `Spacer()` too).

Replace the `LazyVGrid(columns: columns, ...)` call's `columns:` argument with:

```swift
[GridItem(.adaptive(minimum: DesignSystem.speciesCardMinWidth), spacing: DesignSystem.spacingSmall)]
```

- [ ] **Step 2: Replace the existing `speciesCard(_:)` helper with `SpeciesCardView`**

Replace the `ForEach(mapState.allSpecies) { species in speciesCard(species) }` body with:

```swift
ForEach(mapState.allSpecies) { species in
    SpeciesCardView(
        species: species,
        photo: mapState.photosBySpeciesID[species.id]?.first,
        signal: nil,
        isActiveOnMap: mapState.isActive(species.id)
    )
    .overlay(alignment: .topTrailing) {
        Button {
            detailSpecies = species
        } label: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(DesignSystem.Colors.cloud)
                .background(Circle().fill(DesignSystem.Colors.forestDeep.opacity(0.7)))
        }
        .buttonStyle(.plain)
        .padding(DesignSystem.iconButtonPadding)
    }
    .onTapGesture { mapState.toggleSpecies(species.id) }
}
```

This preserves the existing interaction exactly: tapping the card toggles the species active on the map (unchanged), the small "i" button (unchanged in placement/behavior) opens the detail sheet. Remove the old `speciesCard(_:)`, `photoThumbnail(_:)`, and `placeholder` private helpers entirely — `SpeciesCardView` (with its own `CachedAsyncImage`-backed placeholder from Task 7) replaces all of it.

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual visual check**

Launch the app, open Mapa's species library. Confirm: cards render via the new shared style, tapping a card's body toggles it active (colors on the map update), the small "i" button still opens the detail sheet, resizing the window reflows columns.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignal/Views/SpeciesLibraryView.swift
git commit -m "feat: migrate Mapa's species library to the shared SpeciesCardView"
```

---

## Task 10: Hand-Approximated Kraj Boundary Polygons

**Files:**
- Create: `MushroomSignalCore/Sources/MushroomSignalCore/Data/RegionBoundaries.swift`
- Create: `MushroomSignalCore/Tests/MushroomSignalCoreTests/RegionBoundariesTests.swift`

**Interfaces:**
- Produces: `RegionBoundaries.polygon(for regionId: String) -> [(latitude: Double, longitude: Double)]?` — Task 11's `InteractiveMapView` consumes this.

**Explicitly approximate, per the spec and `CLAUDE.md`'s alpha-stage permission** — these coordinates are original hand-drawn approximations of each kraj's real shape and adjacency (referenced against the "Kraje Slovenska" Wikimedia map viewed during brainstorming), not sourced from any external dataset. They're a first pass, expected to be visually tuned once rendered (Step 5) — treat the numbers below as a real starting point to adjust, not a frozen final answer.

- [ ] **Step 1: Implement `RegionBoundaries` with a first-pass coordinate set per kraj**

```swift
import Foundation

/// Approximate polygon boundaries for Slovakia's 8 kraje, for the map's per-region heat
/// overlay. Explicitly not survey-grade — hand-approximated during the 2026-08-08 UI
/// redesign, sanctioned by Alexander for this alpha pass (see CLAUDE.md's Project
/// Conventions). Coordinates are (latitude, longitude) pairs forming each kraj's rough
/// outline, ordered to trace a simple (non-self-intersecting) polygon.
public enum RegionBoundaries {
    public static func polygon(for regionId: String) -> [(latitude: Double, longitude: Double)]? {
        coordinates[regionId]
    }

    private static let coordinates: [String: [(latitude: Double, longitude: Double)]] = [
        "bratislavsky": [
            (48.00, 16.85), (48.30, 16.95), (48.30, 17.25), (48.05, 17.30), (47.90, 17.05)
        ],
        "trnavsky": [
            (47.75, 17.10), (48.05, 17.05), (48.30, 17.25), (48.30, 17.60), (48.05, 17.95),
            (47.75, 17.75), (47.70, 17.35)
        ],
        "trenciansky": [
            (48.60, 17.35), (48.95, 17.55), (49.25, 18.05), (49.10, 18.55), (48.75, 18.45),
            (48.55, 17.95), (48.50, 17.55)
        ],
        "nitriansky": [
            (47.70, 17.35), (48.05, 17.95), (48.30, 17.60), (48.55, 17.95), (48.50, 18.55),
            (48.20, 18.85), (47.80, 18.60), (47.68, 18.10)
        ],
        "zilinsky": [
            (48.95, 17.55), (49.25, 18.05), (49.60, 18.35), (49.55, 19.30), (49.20, 19.60),
            (48.95, 19.15), (48.75, 18.45), (49.10, 18.55)
        ],
        "banskobystricky": [
            (48.20, 18.85), (48.50, 18.55), (48.75, 18.45), (48.95, 19.15), (49.20, 19.60),
            (48.85, 20.25), (48.35, 20.05), (48.05, 19.50), (47.95, 18.95)
        ],
        "presovsky": [
            (48.85, 20.25), (49.20, 19.60), (49.55, 19.30), (49.60, 21.00), (49.50, 22.55),
            (48.95, 22.20), (48.60, 21.30), (48.65, 20.55)
        ],
        "kosicky": [
            (48.35, 20.05), (48.85, 20.25), (48.60, 21.30), (48.95, 22.20), (48.55, 22.55),
            (48.20, 21.90), (48.00, 21.00), (48.10, 20.35)
        ]
    ]
}
```

- [ ] **Step 2: Write a schema-validation test**

```swift
import XCTest
@testable import MushroomSignalCore

final class RegionBoundariesTests: XCTestCase {
    func testEveryRegionHasAPolygon() {
        for region in RegionDatabase.all {
            let polygon = RegionBoundaries.polygon(for: region.id)
            XCTAssertNotNil(polygon, "\(region.id) has no boundary polygon")
            XCTAssertGreaterThanOrEqual(polygon?.count ?? 0, 3, "\(region.id)'s polygon needs at least 3 points to be a real shape")
        }
    }

    func testEveryPolygonPointFallsWithinSlovakiaGridBounds() {
        for region in RegionDatabase.all {
            guard let polygon = RegionBoundaries.polygon(for: region.id) else { continue }
            for point in polygon {
                XCTAssertTrue(SlovakiaGrid.latitudeRange.contains(point.latitude), "\(region.id) has a point outside the expected latitude range: \(point.latitude)")
                XCTAssertTrue(SlovakiaGrid.longitudeRange.contains(point.longitude), "\(region.id) has a point outside the expected longitude range: \(point.longitude)")
            }
        }
    }

    func testUnknownRegionIdReturnsNil() {
        XCTAssertNil(RegionBoundaries.polygon(for: "not-a-real-region"))
    }
}
```

(`SlovakiaGrid.latitudeRange`/`longitudeRange` still exist at this point in the plan — Task 12 removes `SlovakiaGrid` itself, after this task and Task 11 no longer need it. If Task 12 has already landed when this test runs, replace the bounds check with literal values `47.7...49.6` / `16.8...22.6` instead — but per this plan's task order, Task 10 runs before Task 12, so the reference is valid as written.)

- [ ] **Step 3: Run the tests**

Run: `swift test --package-path MushroomSignalCore --filter RegionBoundariesTests`
Expected: PASS — all 3 tests, confirming all 8 regions have valid, in-bounds polygons.

- [ ] **Step 4: Run the full core package suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS, no regressions.

- [ ] **Step 5: Commit**

```bash
git add MushroomSignalCore/Sources/MushroomSignalCore/Data/RegionBoundaries.swift MushroomSignalCore/Tests/MushroomSignalCoreTests/RegionBoundariesTests.swift
git commit -m "feat: add hand-approximated kraj boundary polygons"
```

**Note for Task 11's implementer:** after wiring these into the actual map (Task 11), visually check the rendered shapes against the reference "Kraje Slovenska" map and adjust individual coordinates if a kraj looks visibly wrong (inverted, badly overlapping a neighbor, or floating disconnected) — this task's coordinates are a first draft, not guaranteed pixel-perfect on the first render.

---

## Task 11: Map Redesign — Per-Kraj `MapPolygon` Overlay

**Files:**
- Modify: `MushroomSignal/MapScreenState.swift`
- Modify: `MushroomSignal/Views/InteractiveMapView.swift`
- Modify: `MushroomSignalTests/MapScreenStateTests.swift`

**Interfaces:**
- Consumes: `RegionBoundaries.polygon(for:)` (Task 10), the existing `WeatherClient.fetchSnapshots(for: [GridPoint])` (unchanged signature, fed different input), `DominantSpeciesResolver`/`SpeciesColorAssigner` (unchanged).
- Produces: no new public interface — `MapScreenState`'s and `InteractiveMapView`'s internal shape changes, but `MapScreenView`'s usage of them (if any wraps them) should need no changes.

- [ ] **Step 1: Read both files in full**

Confirm current exact state before editing — `MapScreenState`'s `gridPoints`/`snapshots`/`loadGrid()`/`dominantSpecies(at:)`, and `InteractiveMapView`'s `MapCircle` rendering loop, may have shifted since this plan was written.

- [ ] **Step 2: Replace `MapScreenState`'s grid-point sampling with region-derived points**

Replace:

```swift
    let gridPoints: [GridPoint]
```

with:

```swift
    let regionPoints: [GridPoint]
```

In `init`, replace `self.gridPoints = SlovakiaGrid.generate()` with:

```swift
        self.regionPoints = RegionDatabase.all.map { GridPoint(id: $0.id, latitude: $0.latitude, longitude: $0.longitude) }
```

This reuses `GridPoint` and the existing batched `fetchSnapshots(for: [GridPoint])` method exactly as before — just feeding it 8 region-coordinate points instead of ~39 fine-grid points. No `WeatherClient` protocol change needed.

Rename `loadGrid()` to `loadRegions()` for clarity (update its one call site in `InteractiveMapView`'s `.task` modifier in Step 3), and inside it, replace `snapshots = try await weatherClient.fetchSnapshots(for: gridPoints)` with `snapshots = try await weatherClient.fetchSnapshots(for: regionPoints)`. The `snapshots: [String: WeatherSnapshot]` dictionary itself, and `dominantSpecies(at pointID: String)`, need no change — they're already keyed generically by a String id, and a region's `id` (e.g. `"zilinsky"`) works identically to a grid point's `id` (e.g. `"grid-07"") as a lookup key. Consider renaming the parameter to `dominantSpecies(forRegion regionId: String)` for clarity, updating its one call site in `InteractiveMapView`.

- [ ] **Step 3: Replace `InteractiveMapView`'s `MapCircle` loop with `MapPolygon`**

Replace:

```swift
            Map(position: $cameraPosition) {
                ForEach(mapState.gridPoints) { point in
                    MapCircle(center: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude), radius: gridPointRadiusMeters)
                        .foregroundStyle(color(for: point))
                        .stroke(.clear)
                }
            }
```

with:

```swift
            Map(position: $cameraPosition) {
                ForEach(RegionDatabase.all) { region in
                    if let boundary = RegionBoundaries.polygon(for: region.id) {
                        MapPolygon(coordinates: boundary.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                            .foregroundStyle(color(forRegion: region.id))
                            .stroke(DesignSystem.Colors.forestDeep, lineWidth: 1)
                    }
                }
            }
```

Remove the now-unused `gridPointRadiusMeters` constant and its doc comment. Replace `color(for point: GridPoint) -> Color` with `color(forRegion regionId: String) -> Color`, updating its body to call `mapState.dominantSpecies(forRegion: regionId)` (matching Step 2's rename) instead of `mapState.dominantSpecies(at: point.id)`. Update the `.task { await mapState.loadGrid() }` call to `.task { await mapState.loadRegions() }`.

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -scheme MushroomSignal -configuration Debug -derivedDataPath DerivedData build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Update `MapScreenStateTests.swift`**

Read the file first — it likely references `mapState.gridPoints`/`loadGrid()`/`dominantSpecies(at:)` directly by their old names, which no longer exist after Steps 2-3. Update each reference to the new names (`regionPoints`/`loadRegions()`/`dominantSpecies(forRegion:)`), preserving each test's actual assertions and intent — this is a rename-following exercise, not a logic change. If a test constructed a `GridPoint` with a `"grid-NN"`-style id to simulate a grid point, replace it with a real region id (e.g. `"zilinsky"`) matching how the production code now actually calls this API.

- [ ] **Step 6: Run the full Xcode test suite**

Run: `xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 7: Manual visual check — this is the real verification for this task**

Launch the app (signed build), open Mapa, toggle 2-3 species active. Confirm: 8 solid-colored kraj-shaped regions render (not circles), shapes roughly resemble Slovakia's real kraj boundaries (compare against the reference "Kraje Slovenska" image), no region is obviously inverted/disconnected/wildly wrong, and colors are visibly cleaner/less patchy than the old circle-grid version. If any kraj's shape looks clearly broken, adjust its coordinates in `RegionBoundaries.swift` (Task 10's file) directly — this is expected tuning, not a sign the approach is wrong.

- [ ] **Step 8: Commit**

```bash
git add MushroomSignal/MapScreenState.swift MushroomSignal/Views/InteractiveMapView.swift MushroomSignalTests/MapScreenStateTests.swift
git commit -m "feat: replace the map's grid-of-circles with per-kraj polygon overlays"
```

---

## Task 12: Remove `SlovakiaGrid` (Dead Code)

**Files:**
- Delete: `MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift`
- Delete: `MushroomSignalCore/Tests/MushroomSignalCoreTests/SlovakiaGridTests.swift` (if it exists — check first)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing — pure removal.

Per the spec's resolved open question: `SlovakiaGrid.generate()` is unused after Task 11 (region-derived `GridPoint`s replace it). `GridPoint` itself and `WeatherClient.fetchSnapshots(for: [GridPoint])` remain — they're still alive, just fed different input now. Leaning toward removing the unused grid-generation logic now (YAGNI) rather than leaving it as unreferenced dead code, re-addable later if the mentioned-but-undesigned future route-planner idea actually needs point-based sampling again.

- [ ] **Step 1: Confirm `SlovakiaGrid` has no remaining references**

Run: `grep -rn "SlovakiaGrid" --include="*.swift" . | grep -v DerivedData`
Expected: no results outside the file(s) being deleted — if anything else still references it, STOP and investigate before deleting (this plan's Task 11 should have already removed the one production call site, but confirm rather than assume).

- [ ] **Step 2: Delete the file(s)**

```bash
git rm MushroomSignalCore/Sources/MushroomSignalCore/Data/SlovakiaGrid.swift
```

If `MushroomSignalCore/Tests/MushroomSignalCoreTests/SlovakiaGridTests.swift` exists (check with `find . -iname "SlovakiaGridTests.swift"` first), remove it too — its tests validated grid-generation logic that no longer exists.

- [ ] **Step 3: Run the full core package suite**

Run: `swift test --package-path MushroomSignalCore`
Expected: PASS, no regressions, no missing-symbol errors.

- [ ] **Step 4: Full Xcode build + test**

Run: `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData`
Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git commit -m "chore: remove SlovakiaGrid, unused after the per-kraj map redesign"
```

---

## Final Verification

- [ ] Run `swift test --package-path MushroomSignalCore` — full pass.
- [ ] Run `xcodegen generate && xcodebuild test -scheme MushroomSignal -destination 'platform=macOS' -derivedDataPath DerivedData` — full pass.
- [ ] Full signed Release build, launch the app, and manually walk through: Zoznam's grid + card tap → detail sheet, Mapa's library grid + card tap-to-toggle + info-button → detail sheet, the map's per-kraj shapes and colors, and legible ≥20pt text throughout the app.
- [ ] Launch the widget (small/medium/large via Xcode previews at minimum, a real desktop placement if practical) and confirm the redesigned layouts fit without truncation.
- [ ] Update `docs/superpowers/KNOWN_ISSUES.md` with what shipped from this pass, matching this project's established convention.
