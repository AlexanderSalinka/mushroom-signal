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
