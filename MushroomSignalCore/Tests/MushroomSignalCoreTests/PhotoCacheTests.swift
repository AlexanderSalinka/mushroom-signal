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
        MockPhotoURLProtocol.requestHandler = { request in
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
